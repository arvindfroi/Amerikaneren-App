import Foundation

/// Innstillinger for informasjonssett-søket (SO-ISMCTS).
struct ISMCTSKonfig {
    /// Myk tidsgrense for ett kortvalg. Søket itererer til den er brukt opp.
    var tidsbudsjett: TimeInterval = 0.45
    /// Hardt tak på iterasjoner PER TRE. Brukes av iterasjonskurven, der
    /// tiden ikke skal være bindende.
    var maksIterasjoner = Int.max
    /// Utforskningskonstanten i UCB. Snittverdien normaliseres til [0, 1]
    /// mot spennet søket faktisk har sett, så konstanten er skalafri.
    var utforskning = 0.7
    /// Antall uavhengige trær (rotparallellisering). 1 = entrådet.
    var tråder = 1
    /// Når så mange stikk (eller færre) gjenstår ved bladet, løses resten
    /// eksakt med dobbeltdummy i stedet for grådig utrulling. 0 = ren
    /// grådig utrulling til rundeslutt (ingen fasit noe sted i søket).
    var bladstikk = 0
    /// Vekt samplede verdener mot budhistorikken – samme fordeling som PIMC.
    var budvekting = true
    /// Maks antall forkastede verdener per iterasjon i vektingen.
    var maksVektforsøk = 8
    /// Hvor ofte klokka leses (i iterasjoner).
    var tidssjekk = 64

    /// Standard for benchmark: entrådet, ren grådig utrulling.
    static func standard(tid: TimeInterval) -> ISMCTSKonfig {
        var k = ISMCTSKonfig()
        k.tidsbudsjett = tid
        return k
    }
}

// MARK: - Treet

/// Én kant ut fra en node: ett konkret kort.
private struct ISKant {
    var kort: Int
    var barn = -1            // nodeindeks, −1 = ikke ekspandert
    var besøk = 0            // N(a) – ganger handlingen ble VALGT
    var tilgjengelig = 0     // A(a) – ganger handlingen var LOVLIG i verdenen
    var sum = 0.0            // Σ verdi for setet som handler i noden
}

/// Én node = ett informasjonssett sett fra søkerens sete. Hvilket sete som
/// handler er bestemt av kortsekvensen fra roten (stikkvinneren følger av de
/// spilte kortene), så setet er det samme i alle determiniseringer – men
/// hvilke kort som er LOVLIGE varierer, og det er nettopp derfor kantene
/// trenger et eget tilgjengelighetstall.
private struct ISNode {
    var sete: Int
    var besøk = 0
    var kanter: [ISKant] = []
}

/// Ett SO-ISMCTS-tre. Hvert tre eier sin egen tilfeldighetskilde og sin egen
/// dobbeltdummy-løser, så flere trær kan kjøre samtidig uten delt tilstand.
private final class ISTre {
    private let innsikt: Spillinnsikt
    private let konfig: ISMCTSKonfig
    private let rotkandidater: [Int]
    /// Dobbeltdummy ved bladet må aldri strekke seg inn i første stikk –
    /// der gjelder utspills- og makkerplikt, som løserens nøkkel ikke ser.
    private let bladstikk: Int
    private var rng: SeededGenerator
    private var noder: [ISNode]
    private lazy var løser = Dobbeltdummy(kapasitet: 1 << 12)

    /// Verdiene i denne målfunksjonen spenner fra noen få stikkpoeng til
    /// ±målPoeng når målstreken står på spill. UCB krever et normalisert
    /// snitt, så søket normaliserer mot spennet det selv har observert –
    /// PER SETE, fordi budgiverens skala (±2×budet) og en forsvarers skala
    /// (antall egne stikk) er helt ulike. Med ett felles spenn ville alle
    /// forsvarernes snittverdier klemmes sammen i en tynn stripe, og
    /// utforskningsleddet ville gjøre motstandermodellen nesten tilfeldig.
    private var lav = SIMD4<Double>(repeating: .infinity)
    private var høy = SIMD4<Double>(repeating: -.infinity)

    private(set) var iterasjoner = 0

    // MARK: Instrumentering: hvor mye av utfallet treet faktisk bestemmer
    //
    // Kjernepåstanden bak ISMCTS er at treet gradvis OVERTAR for den faste
    // utrullingspolicyen: beslutningen flyttes fra håndskreven regel til
    // innsamlet statistikk. Vokser dybden med iterasjonstallet samtidig som
    // styrken vokser, er det treet – og ikke ren variansreduksjon – som gjør
    // jobben. Alt her er O(1) per iterasjon.

    /// Antall kort som gjenstår å spille fra rotstillingen. Hver iterasjon
    /// tar nøyaktig så mange beslutninger, fordelt på tre og utrulling.
    private(set) var kortIgjenVedRot = 0
    /// Sum av tredybden (antall beslutninger tatt inne i treet, medregnet
    /// ekspansjonstrekket) over alle iterasjoner.
    private(set) var dybdeSum = 0
    /// Sum av utvalgsdybden: beslutninger tatt av availability-UCB alene,
    /// altså uten ekspansjonstrekket som velges tilfeldig blant ubesøkte.
    private(set) var utvalgSum = 0
    private(set) var dybdeMaks = 0
    /// `dybdeHist[d]` = antall iterasjoner med tredybde nøyaktig `d`.
    private(set) var dybdeHist: [Int] = []

    init(innsikt: Spillinnsikt, konfig: ISMCTSKonfig, rotkandidater: [Int], frø: UInt64) {
        self.innsikt = innsikt
        self.konfig = konfig
        self.rotkandidater = rotkandidater
        self.bladstikk = max(0, min(konfig.bladstikk, 6))
        self.rng = SeededGenerator(seed: frø == 0 ? 0xD1B5_4A32_D192_ED03 : frø)
        self.noder = [ISNode(sete: innsikt.sete)]
        noder.reserveCapacity(4096)
        self.kortIgjenVedRot = (0..<4).reduce(0) { $0 + innsikt.antallKort[$1] }
        self.dybdeHist = [Int](repeating: 0, count: kortIgjenVedRot + 2)
    }

    // MARK: Kjøring

    func kjør(frist: Date?, maksIterasjoner: Int) {
        var teller = 0
        while iterasjoner < maksIterasjoner {
            if let frist, teller % konfig.tidssjekk == 0, iterasjoner > 0, Date() >= frist { break }
            teller += 1
            énIterasjon()
        }
    }

    /// Rotstatistikken i kandidatrekkefølge: besøk og verdisum per kort.
    func rotstatistikk(_ kandidater: [Int]) -> (besøk: [Int], sum: [Double]) {
        var b = [Int](repeating: 0, count: kandidater.count)
        var s = [Double](repeating: 0, count: kandidater.count)
        for (i, kort) in kandidater.enumerated() {
            guard let k = noder[0].kanter.first(where: { $0.kort == kort }) else { continue }
            b[i] = k.besøk
            s[i] = k.sum
        }
        return (b, s)
    }

    // MARK: Én iterasjon

    private func énIterasjon() {
        guard let verden = sampleVerden() else { return }
        var t = Spilltilstand(
            hender: verden.hender, leder: innsikt.leder, pågående: innsikt.pågående,
            trumfFarge: innsikt.trumfFarge, lagMaske: verden.lagMaske,
            budgiver: innsikt.budgiver, pliktkort: innsikt.pliktkort,
            førsteStikk: innsikt.trickNummer == 0
        )
        var perSete = [0, 0, 0, 0]
        var sti: [(node: Int, kant: Int)] = []
        sti.reserveCapacity(16)

        // ── Utvelgelse + ekspansjon ─────────────────────────────────────
        var node = 0
        var ekspanderte = false
        while true {
            let lovlige = node == 0 ? rotkandidater : lovligeTrekk(t)
            if lovlige.isEmpty { break }
            let (kant, nyGren) = velgKant(node: node, lovlige: lovlige)
            if nyGren { ekspanderte = true }
            sti.append((node, kant))
            let kort = noder[node].kanter[kant].kort
            if let vinner = Spillregler.utfør(&t, indeks: kort) { perSete[vinner] += 1 }
            if tomt(t) { break }
            if nyGren {
                noder.append(ISNode(sete: Spillregler.aktivtSete(t)))
                noder[node].kanter[kant].barn = noder.count - 1
                break
            }
            node = noder[node].kanter[kant].barn
        }

        // ── Bladevaluering ──────────────────────────────────────────────
        var restLagStikk = 0
        if !tomt(t) {
            t = GrådigSpiller.spillUt(t, stoppVedStikkIgjen: bladstikk, perSete: &perSete)
            if !tomt(t) {
                // Løseren gjenbrukes gjennom hele søket (transposisjonstabellen
                // er gull verdt), men tømmes før den spiser minne.
                if løser.lagredeStillinger > 200_000 { løser.tøm() }
                restLagStikk = løser.løs(t)
            }
        }
        let verdier = innsikt.måltall(
            lagMaske: verden.lagMaske, perSete: perSete, restLagStikk: restLagStikk
        )

        // ── Tilbakepropagering ──────────────────────────────────────────
        for (n, k) in sti {
            let s = noder[n].sete
            let verdi = verdier[s]
            if verdi < lav[s] { lav[s] = verdi }
            if verdi > høy[s] { høy[s] = verdi }
            noder[n].besøk += 1
            noder[n].kanter[k].besøk += 1
            noder[n].kanter[k].sum += verdi
        }

        // Hvor stor del av runden treet selv bestemte i denne iterasjonen.
        let dybde = sti.count
        dybdeSum += dybde
        utvalgSum += ekspanderte ? max(0, dybde - 1) : dybde
        if dybde > dybdeMaks { dybdeMaks = dybde }
        if dybde < dybdeHist.count { dybdeHist[dybde] += 1 }

        iterasjoner += 1
    }

    // MARK: Utvelgelse

    /// Availability-basert UCB. Utforskningsleddet bruker A(a) – hvor mange
    /// ganger handlingen var LOVLIG i den samplede verdenen – ikke nodens
    /// besøkstall. Uten dette ville et kort som sjelden er lovlig (typisk
    /// fordi det bare kan spilles i noen determiniseringer) fått et
    /// kunstig høyt utforskningsledd og blitt overvurdert.
    ///
    /// Returnerer kantindeksen og om dette er en ubesøkt gren (ekspansjon).
    private func velgKant(node: Int, lovlige: [Int]) -> (Int, Bool) {
        var indekser = [Int]()
        indekser.reserveCapacity(lovlige.count)
        for kort in lovlige {
            let i: Int
            if let funnet = noder[node].kanter.firstIndex(where: { $0.kort == kort }) {
                i = funnet
            } else {
                noder[node].kanter.append(ISKant(kort: kort))
                i = noder[node].kanter.count - 1
            }
            noder[node].kanter[i].tilgjengelig += 1
            indekser.append(i)
        }

        // Ubesøkte lovlige handlinger prøves først, i tilfeldig rekkefølge.
        var uprøvde = [Int]()
        for i in indekser where noder[node].kanter[i].besøk == 0 { uprøvde.append(i) }
        if !uprøvde.isEmpty {
            let valgt = uprøvde[Int.random(in: 0..<uprøvde.count, using: &rng)]
            return (valgt, true)
        }

        let s = noder[node].sete
        let bunn = lav[s]
        let spenn = max(1e-9, høy[s] - bunn)
        var beste = indekser[0]
        var besteScore = -Double.infinity
        for i in indekser {
            let k = noder[node].kanter[i]
            let snitt = (k.sum / Double(k.besøk) - bunn) / spenn
            let utforsk = konfig.utforskning
                * (log(Double(k.tilgjengelig)) / Double(k.besøk)).squareRoot()
            let score = snitt + utforsk
            if score > besteScore {
                besteScore = score
                beste = i
            }
        }
        return (beste, false)
    }

    // MARK: Hjelpere

    private func tomt(_ t: Spilltilstand) -> Bool {
        t.hender[0] | t.hender[1] | t.hender[2] | t.hender[3] == 0
    }

    private func lovligeTrekk(_ t: Spilltilstand) -> [Int] {
        let m = Spillregler.lovligMaske(t)
        if m == 0 { return [] }
        if m & (m - 1) == 0 { return [Kortmaske.laveste(m)] }
        let union = t.pågående.reduce(t.hender[0] | t.hender[1] | t.hender[2] | t.hender[3]) {
            $0 | (1 << UInt64($1.indeks))
        }
        return Spillregler.reduserteTrekk(lovlig: m, union: union)
    }

    /// Determinisering: én verden som er konsistent med informasjonssettet.
    /// Budvektingen håndteres med forkastningsutvalg, slik at treet ser
    /// nøyaktig samme verdensfordeling som PIMC-søket vekter med – bare
    /// uttrykt som frekvens i stedet for som vekt, som er det MCTS-
    /// statistikken trenger.
    private func sampleVerden() -> Verden? {
        guard konfig.budvekting else { return innsikt.sampleVerden(rng: &rng) }
        var siste: Verden?
        for _ in 0..<konfig.maksVektforsøk {
            guard let v = innsikt.sampleVerden(rng: &rng) else { return siste }
            let vekt = innsikt.budVekt(hender: v.hender)
            if vekt >= 1 || Double.random(in: 0..<1, using: &rng) < vekt { return v }
            siste = v
        }
        return siste
    }
}

// MARK: - Hvor mye av utfallet treet bestemmer

/// Måletall for ETT kortvalg: hvor dypt treet rekker, og hvor stor andel av
/// beslutningene fram til rundeslutt som tas av treets egen statistikk
/// framfor av den faste utrullingspolicyen.
///
/// Dette er den mekanistiske testen på om ISMCTS virker slik teorien sier:
/// vokser dybden med iterasjonstallet SAMTIDIG som styrken vokser, er det
/// treet som gjør jobben – ikke bare at flere utrullinger demper støyen.
struct Treprofil {
    var iterasjoner = 0
    /// Kort som gjenstår å spille fra rotstillingen = beslutninger per iterasjon.
    var beslutningerTotalt = 0
    /// Absolutt stikknummer ved roten (0-basert) og kort alt lagt i stikket.
    var rotStikk = 0
    var pågåendeVedRot = 0
    /// Snittdybde: beslutninger tatt inne i treet per iterasjon (medregnet
    /// ekspansjonstrekket).
    var snittDybde = 0.0
    /// Som over, men uten ekspansjonstrekket – rene UCB-beslutninger.
    var snittUtvalgsdybde = 0.0
    var maksDybde = 0
    /// `andelTre[i]` = andel av iterasjonene der beslutning nr. `i` etter
    /// roten ble tatt inne i treet. Faller monotont fra 1 mot 0.
    var andelTre: [Double] = []

    /// Andel av ALLE beslutningene fram til rundeslutt som treet tok.
    var andelAvRunden: Double {
        beslutningerTotalt > 0 ? snittDybde / Double(beslutningerTotalt) : 0
    }

    /// Hvilket absolutt stikk beslutning nr. `i` etter roten hører til.
    func stikk(forBeslutning i: Int) -> Int {
        rotStikk + (i + pågåendeVedRot) / 4
    }
}

// MARK: - Spilleren

/// **SO-ISMCTS** (single-observer information set Monte Carlo tree search,
/// Cowling/Powley/Whitehouse 2012) for stikkspillet i Amerikaneren.
///
/// Motivasjonen er diagnosen av PIMC-søket i `MesterAI`: der løses hver
/// samplet verden med dobbeltdummy, altså med fasit. Søket oppfører seg
/// derfor som om det senere vil VITE hvor kortene ligger, og kan velge ulikt
/// kort i ulike verdener ved samme informasjonssett – strategifusjon. Mer
/// regnekraft forsterker illusjonen, og målingene viste da også null
/// styrkegevinst av 17× flere verdener.
///
/// ISMCTS fjerner strategifusjonen ved konstruksjon:
///
/// 1. **Ett tre over informasjonssett.** Statistikken samles i ÉN struktur
///    på tvers av alle determiniseringer, så roten må velge ett kort som er
///    godt i snitt – ikke det beste kortet i hver verden for seg.
/// 2. **Ny verden per iterasjon.** Hver iterasjon sampler en verden med
///    `Spillinnsikt.sampleVerden` (verifisert lekkasjefri) og lar bare kort
///    som er lovlige I DEN verdenen bli valgt.
/// 3. **Availability-basert UCB.** Utforskningen teller hvor ofte en
///    handling var tilgjengelig, ikke hvor mange ganger noden ble besøkt.
/// 4. **Max^n-tilbakepropagering.** Verdien i bladet regnes ut for alle fire
///    seter med `Spillinnsikt.måltall` – samme målfunksjon som
///    `MesterAI.vurder` – og hver node får verdien for det setet som handler
///    der. Det håndterer at makkeren er ukjent: lagtilhørigheten varierer
///    mellom determiniseringer, mens «hvert sete vil maksimere sin egen
///    poengendring» gjelder i alle.
///
/// Bud, byttekort og trumfvalg er ikke rørt – de kjøres fortsatt av
/// `MesterAI`.
final class MesterISMCTS {
    let sete: Int
    var konfig: ISMCTSKonfig
    private var rng: SeededGenerator

    /// Overstyring for benchmarks.
    static var overstyrKonfig: ISMCTSKonfig?

    /// Måletall fra siste `velgKort`.
    private(set) var sisteIterasjoner = 0
    private(set) var sisteRotfordeling: [(kort: Card, besøk: Int, snitt: Double)] = []
    private(set) var sisteTreprofil = Treprofil()

    init(sete: Int, konfig: ISMCTSKonfig = ISMCTSKonfig(), seed: UInt64? = nil) {
        self.sete = sete
        self.konfig = konfig
        self.rng = SeededGenerator(seed: seed ?? UInt64.random(in: 1...UInt64.max))
    }

    func velgKort(engine: GameEngine) -> Card? {
        let lovlige = engine.lovligeKort(for: sete)
        guard !lovlige.isEmpty else { return nil }
        sisteIterasjoner = 0
        sisteRotfordeling = []
        sisteTreprofil = Treprofil()
        if lovlige.count == 1 { return lovlige[0] }
        guard let innsikt = Spillinnsikt(engine: engine, sete: sete) else { return nil }

        // Likeverdige kort (ingen gjenværende kort imellom) prøves bare én
        // gang – nøyaktig samme rotkandidater som MesterAI vurderer.
        let pågåendeMaske = innsikt.pågående.reduce(UInt64(0)) { $0 | (1 << UInt64($1.indeks)) }
        let union = innsikt.ukjente | innsikt.minHånd | pågåendeMaske
        let kandidater = Spillregler.reduserteTrekk(lovlig: Kortmaske.maske(lovlige), union: union)
        if kandidater.isEmpty { return nil }
        if kandidater.count == 1 { return Kortmaske.kort(kandidater[0]) }

        let frist: Date? = konfig.tidsbudsjett > 0
            ? Date().addingTimeInterval(konfig.tidsbudsjett) : nil
        let arbeidere = max(1, min(konfig.tråder, ProcessInfo.processInfo.activeProcessorCount))
        let basefrø = rng.next()

        var besøk = [Int](repeating: 0, count: kandidater.count)
        var sum = [Double](repeating: 0, count: kandidater.count)
        let beslutninger = (0..<4).reduce(0) { $0 + innsikt.antallKort[$1] }
        var dybdeSum = 0, utvalgSum = 0, dybdeMaks = 0
        var dybdeHist = [Int](repeating: 0, count: beslutninger + 2)

        if arbeidere == 1 {
            let tre = ISTre(innsikt: innsikt, konfig: konfig,
                            rotkandidater: kandidater, frø: Self.avledetFrø(basefrø, 0))
            tre.kjør(frist: frist, maksIterasjoner: konfig.maksIterasjoner)
            (besøk, sum) = tre.rotstatistikk(kandidater)
            sisteIterasjoner = tre.iterasjoner
            dybdeSum = tre.dybdeSum
            utvalgSum = tre.utvalgSum
            dybdeMaks = tre.dybdeMaks
            for (d, n) in tre.dybdeHist.enumerated() where d < dybdeHist.count { dybdeHist[d] += n }
        } else {
            // Rotparallellisering: uavhengige trær som slås sammen på roten.
            // Valgt framfor tre-parallellisering med lås fordi trærne ikke
            // deler noe muterbart i det hele tatt – ingen låser, ingen
            // datakappløp, og resultatet er uavhengig av trådplanleggingen.
            // Prisen er at hvert tre er grunnere enn ett stort tre ville
            // vært; til gjengjeld er varians på roten det parallelliseringen
            // er best til å redusere.
            let antall = kandidater.count
            var delbesøk = [Int](repeating: 0, count: arbeidere * antall)
            var delsum = [Double](repeating: 0, count: arbeidere * antall)
            // Per arbeider: [iterasjoner, dybdeSum, utvalgSum, dybdeMaks].
            var deltall = [Int](repeating: 0, count: arbeidere * 4)
            let histBredde = dybdeHist.count
            var delhist = [Int](repeating: 0, count: arbeidere * histBredde)
            delbesøk.withUnsafeMutableBufferPointer { bBuf in
                delsum.withUnsafeMutableBufferPointer { sBuf in
                    deltall.withUnsafeMutableBufferPointer { tBuf in
                        delhist.withUnsafeMutableBufferPointer { hBuf in
                            DispatchQueue.concurrentPerform(iterations: arbeidere) { w in
                                let tre = ISTre(innsikt: innsikt, konfig: konfig,
                                                rotkandidater: kandidater,
                                                frø: Self.avledetFrø(basefrø, w))
                                tre.kjør(frist: frist, maksIterasjoner: konfig.maksIterasjoner)
                                let (b, s) = tre.rotstatistikk(kandidater)
                                for i in 0..<antall {
                                    bBuf[w * antall + i] = b[i]
                                    sBuf[w * antall + i] = s[i]
                                }
                                tBuf[w * 4] = tre.iterasjoner
                                tBuf[w * 4 + 1] = tre.dybdeSum
                                tBuf[w * 4 + 2] = tre.utvalgSum
                                tBuf[w * 4 + 3] = tre.dybdeMaks
                                for (d, n) in tre.dybdeHist.enumerated() where d < histBredde {
                                    hBuf[w * histBredde + d] = n
                                }
                            }
                        }
                    }
                }
            }
            for w in 0..<arbeidere {
                for i in 0..<antall {
                    besøk[i] += delbesøk[w * antall + i]
                    sum[i] += delsum[w * antall + i]
                }
                sisteIterasjoner += deltall[w * 4]
                dybdeSum += deltall[w * 4 + 1]
                utvalgSum += deltall[w * 4 + 2]
                dybdeMaks = max(dybdeMaks, deltall[w * 4 + 3])
                for d in 0..<histBredde { dybdeHist[d] += delhist[w * histBredde + d] }
            }
        }

        if sisteIterasjoner > 0 {
            var profil = Treprofil()
            profil.iterasjoner = sisteIterasjoner
            profil.beslutningerTotalt = beslutninger
            profil.rotStikk = innsikt.trickNummer
            profil.pågåendeVedRot = innsikt.pågående.count
            profil.snittDybde = Double(dybdeSum) / Double(sisteIterasjoner)
            profil.snittUtvalgsdybde = Double(utvalgSum) / Double(sisteIterasjoner)
            profil.maksDybde = dybdeMaks
            // Andel av iterasjonene der beslutning nr. i lå INNE i treet:
            // halen av dybdehistogrammet.
            var andel = [Double](repeating: 0, count: beslutninger)
            var hale = sisteIterasjoner
            for i in 0..<beslutninger {
                // Beslutning nr. i lå i treet når dybden var minst i+1.
                if i < dybdeHist.count { hale -= dybdeHist[i] }
                andel[i] = Double(hale) / Double(sisteIterasjoner)
            }
            profil.andelTre = andel
            sisteTreprofil = profil
        }

        sisteRotfordeling = kandidater.enumerated().map {
            (Kortmaske.kort($1), besøk[$0], besøk[$0] > 0 ? sum[$0] / Double(besøk[$0]) : 0)
        }
        guard sisteIterasjoner > 0, besøk.contains(where: { $0 > 0 }) else {
            // Ingen iterasjoner rakk igjennom – fall tilbake på billigste kort.
            return Kortmaske.kort(kandidater.min {
                Kortmaske.kostnad($0, trumfFarge: innsikt.trumfFarge)
                    < Kortmaske.kostnad($1, trumfFarge: innsikt.trumfFarge)
            }!)
        }

        // Rotvalg: mest besøkte handling. Mer robust enn høyeste snittverdi,
        // som kan bli dratt av én heldig utrulling i en tynt besøkt gren.
        var beste = 0
        for i in kandidater.indices.dropFirst() {
            let flere = besøk[i] > besøk[beste]
            let liktMenBilligere = besøk[i] == besøk[beste]
                && Kortmaske.kostnad(kandidater[i], trumfFarge: innsikt.trumfFarge)
                    < Kortmaske.kostnad(kandidater[beste], trumfFarge: innsikt.trumfFarge)
            if flere || liktMenBilligere { beste = i }
        }
        return Kortmaske.kort(kandidater[beste])
    }

    /// Frø til tre nummer `i`, avledet av gyllen-snitt-konstanten slik at
    /// trærne sampler uavhengig av hverandre og av trådplanleggingen.
    private static func avledetFrø(_ base: UInt64, _ i: Int) -> UInt64 {
        let f = base &+ UInt64(bitPattern: Int64(i)) &* 0x9E37_79B9_7F4A_7C15
        return f == 0 ? 0xD1B5_4A32_D192_ED03 : f
    }
}
