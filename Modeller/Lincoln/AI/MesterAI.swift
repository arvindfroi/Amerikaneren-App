import Foundation

/// Innstillinger for søket i MesterAI. Standardverdiene er balansert for å
/// holde trekktiden godt under et halvt sekund på en telefon.
struct MesterKonfig {
    /// Maks antall samplede verdener per kortvalg.
    var maksVerdener = 28
    /// Verdenstak i sluttspillet, der hver verden løses eksakt uten grådig
    /// fase og koster mikrosekunder: med det ordinære taket blir jevne valg
    /// (typisk 4/9 mot 3/9 for hvem som sitter med hva) rene terningkast,
    /// enda tidsbudsjettet rekker tusenvis av verdener.
    var maksVerdenerSluttspill = 1200
    /// Minste antall verdener som alltid evalueres, uansett tidsbudsjett.
    var minVerdener = 8
    /// Når så mange stikk (eller færre) gjenstår, løses resten eksakt med
    /// dobbeltdummy; før det spilles grådig fram til grensen.
    var eksaktStikkGrense = 6
    /// Myk tidsgrense for ett kortvalg.
    var tidsbudsjett: TimeInterval = 0.45
    /// Antall samplede utdelinger for budvurdering og trumfvalg.
    var verdenerVedBud = 48
    /// Antall samplede utdelinger per vrak-kandidat i byttefasen.
    var verdenerVedBytte = 20
    /// Vekt samplede verdener mot budhistorikken (pass = svak hånd,
    /// høyt bud = sterk hånd).
    var budvekting = true
    /// Matchbevisst budgivning: ligger man langt bak sent i partiet, er
    /// varians en venn (våg mer); leder man, er trygghet verdt mer enn
    /// marginale bud. Virker i begge partiformater.
    var matchbevisst = true

    /// Skalerer søket etter maskinvaren: flere kjerner gir flere verdener og
    /// dypere eksakt sluttspill innenfor samme tidsbudsjett.
    static func automatisk() -> MesterKonfig {
        var k = MesterKonfig()
        if ProcessInfo.processInfo.activeProcessorCount >= 6 {
            k.maksVerdener = 36
            k.verdenerVedBud = 64
            k.eksaktStikkGrense = 7
        }
        return k
    }
}

/// Søkebasert toppspiller («President»-nivået). Tre grep gjør den sterk:
///
/// 1. **Determinisert Monte Carlo**: de ukjente kortene samples i mange
///    mulige verdener som stemmer med alt setet lovlig vet (renonser,
///    makkerplikt-slutninger, hvem som kan ha det etterlyste kortet og
///    hvilke kort som kan ligge i vraket).
/// 2. **Eksakt sluttspill**: hver verden spilles grådig fram til få stikk
///    gjenstår, og resten løses optimalt med dobbeltdummy-søk.
/// 3. **Simulerte valg**: bud, byttekort-vrak, trumf og etterlysning
///    sammenliknes på forventet poengsum over de samme samplede verdenene –
///    med de riktige poengsatsene (2×bud/1×bud, Amerikaner ±50/±25, solo
///    ±100 ved mål på 100).
///
/// Den ser aldri skjulte kort – all innsikt kommer fra `Spillinnsikt`.
final class MesterAI {
    let sete: Int
    var konfig: MesterKonfig
    private var rng: SeededGenerator

    /// Overstyring for benchmarks/AB-testing – brukes av AIPlayer om satt.
    static var overstyrKonfig: MesterKonfig?

    /// Fast basefrø for benchmarks: gjør de samplede verdenene reproduserbare,
    /// slik at en parret A/B måler tiltaket og ikke bare Monte Carlo-støyen.
    /// Setet legges til, så setene ikke deler tallrekke.
    static var overstyrFrø: UInt64?

    /// Hvor mange verdener siste `velgKort` rakk. Kun for måling.
    private(set) var sisteVerdenstall = 0

    init(sete: Int, konfig: MesterKonfig = MesterKonfig(), seed: UInt64? = nil) {
        self.sete = sete
        self.konfig = konfig
        self.rng = SeededGenerator(seed: seed ?? UInt64.random(in: 1...UInt64.max))
    }

    // MARK: - Budgivning

    func velgBud(engine: GameEngine) -> BidAction {
        let lovlige = engine.lovligeBud(for: sete)
        guard !lovlige.isEmpty, engine.rules.antallSpillere == 4 else { return .pass }
        let regler = engine.rules
        let hånd = engine.hands[sete]
        let minHånd = Kortmaske.maske(hånd)
        let minsteBud = lovlige.compactMap { action -> Int? in
            if case .bud(let n) = action { return n }
            return nil
        }.min()

        let (heuristiskFarge, estimat) = AIPlayer.besteTrumf(hånd: hånd)
        let alleStikk = regler.maksBud

        // Matchbevissthet: «senhet» er hvor nær partiet er slutten (nærhet
        // til målpoeng, eller andel spilte runder i rundeformatet).
        // Desperasjon (bak sent) premierer varians; trygghet (ledelse sent)
        // premierer pass og straffer marginale bud.
        var desperasjon = 0.0
        var trygghet = 0.0
        if konfig.matchbevisst {
            let mål = Double(regler.målPoeng)
            let minPoeng = Double(engine.scores[sete])
            let besteAndre = Double((0..<4).filter { $0 != sete }.map { engine.scores[$0] }.max() ?? 0)
            let senhet: Double
            if let maksRunder = regler.maksRunder {
                senhet = min(1, Double(engine.rundeResultater.count) / Double(max(1, maksRunder)))
            } else {
                senhet = min(1, max(minPoeng, besteAndre) / mål)
            }
            desperasjon = min(1, max(0, (besteAndre - minPoeng) / mål * 2)) * senhet
            trygghet = min(1, max(0, (minPoeng - besteAndre) / mål * 2)) * senhet
        }

        // Solo-amerikaner simuleres bare når hånden er i nærheten av å bære
        // alle stikkene alene – desperasjon senker terskelen litt.
        let vurderSolo = lovlige.contains(.soloAmerikaner)
            && estimat + Double(regler.antallByttekort) * 0.4
                >= Double(alleStikk) - 2.5 - desperasjon * 1.5

        var deklStikk: [(stikk: Int, vekt: Double)] = []
        var passVerdier: [(verdi: Double, vekt: Double)] = []
        var soloKlart = 0.0
        var soloTalt = 0.0
        let profiler = BudProfil.fra(bids: engine.bids, minsteBud: regler.minsteBud)

        for _ in 0..<konfig.verdenerVedBud {
            let (hender, talon) = sampleUtdeling(
                pool: Kortmaske.alle & ~minHånd,
                perSete: regler.kortPerSpiller, minHånd: minHånd
            )
            let vekt = budVekt(profiler: profiler, hender: hender,
                               spiltAv: nil, stikkTotalt: regler.kortPerSpiller)

            // Scenario 1: jeg vinner budrunden med min beste farge (dekker
            // både tallbud og Amerikaner – samme lag, samme spill).
            if let plan = deklarasjonsplan(
                hånd: minHånd, farge: heuristiskFarge, hender: hender,
                talon: talon, regler: regler
            ) {
                deklStikk.append((GrådigSpiller.lagStikk(plan, eksaktFra: konfig.eksaktStikkGrense), vekt))
            }

            // Scenario 2: jeg passer, og den sterkeste motstanderen spiller.
            passVerdier.append((passVerdi(hender: hender, talon: talon, regler: regler), vekt))

            // Scenario 3: solo-amerikaner – alle stikkene alene, med trumf
            // og et valgfritt uttrekkskort i første stikk.
            if vurderSolo, let solo = soloPlan(
                hånd: minHånd, farge: heuristiskFarge, hender: hender,
                talon: talon, regler: regler
            ) {
                soloTalt += vekt
                if GrådigSpiller.lagStikk(solo, eksaktFra: konfig.eksaktStikkGrense) == alleStikk {
                    soloKlart += vekt
                }
            }
        }

        let deklVekt = max(1e-9, deklStikk.reduce(0) { $0 + $1.vekt })
        let passVekt = max(1e-9, passVerdier.reduce(0) { $0 + $1.vekt })
        let evPass = passVerdier.reduce(0) { $0 + $1.verdi * $1.vekt } / passVekt
            + trygghet * 1.5
        var besteAction = BidAction.pass
        var besteEV = evPass

        if let b = minsteBud, !deklStikk.isEmpty {
            let p = deklStikk.filter { $0.stikk >= b }.reduce(0) { $0 + $1.vekt } / deklVekt
            // Budvinneren vinner/taper det dobbelte av budet.
            let ev = Double(2 * b) * (2 * p - 1)
                + desperasjon * Double(b) * 0.6 - trygghet * Double(b) * 0.4
            if ev > besteEV {
                besteAction = .bud(b)
                besteEV = ev
            }
        }
        if lovlige.contains(.amerikaner), !deklStikk.isEmpty {
            // Amerikaner: laget må ta alle stikkene; budvinner ±målPoeng/2.
            let p = deklStikk.filter { $0.stikk >= alleStikk }.reduce(0) { $0 + $1.vekt } / deklVekt
            let ev = Double(regler.målPoeng / 2) * (2 * p - 1)
                + desperasjon * Double(regler.målPoeng) * 0.10
            if ev > besteEV {
                besteAction = .amerikaner
                besteEV = ev
            }
        }
        if vurderSolo, soloTalt > 0 {
            let p = soloKlart / soloTalt
            let ev = Double(regler.målPoeng) * (2 * p - 1)
                + desperasjon * Double(regler.målPoeng) * 0.15
            if ev > besteEV {
                besteAction = .soloAmerikaner
                besteEV = ev
            }
        }
        return besteAction
    }

    // MARK: - Byttekort

    /// Hvilke kort vrakes: kandidat-vrak genereres for de beste trumffargene
    /// (behold trumf/ess, tøm korte sidefarger for renons – pluss nettets
    /// forslag) og spilles ut mot samplede verdener; vraket som oftest
    /// berger meldingen vinner.
    func velgByttekort(engine: GameEngine) -> [Card] {
        let regler = engine.rules
        guard engine.phase == .byttekort, engine.budgiverSeat == sete,
              regler.antallSpillere == 4, regler.antallByttekort > 0,
              let budAction = engine.høyesteBud?.action else { return [] }
        let hånd16 = Kortmaske.maske(engine.hands[sete])
        let antall = regler.antallByttekort
        let mål: Int
        if case .bud(let n) = budAction { mål = n } else { mål = regler.kortPerSpiller }

        // Trumfkandidater: de to beste fargene på den store hånden.
        let rangerte = Kortmaske.farger
            .map { suit in (Kortmaske.fargeIndeks(suit), AIPlayer.estimerStikk(hånd: engine.hands[sete], trumf: suit)) }
            .sorted { $0.1 > $1.1 }
        let trumfKandidater = rangerte.prefix(2).map(\.0)

        var kandidater: [(trumf: Int, vrak: UInt64)] = []
        var sett = Set<UInt64>()
        func leggTil(_ trumf: Int, _ vrak: UInt64) {
            let nøkkel = vrak | (UInt64(trumf + 1) << 56)
            if sett.insert(nøkkel).inserted {
                kandidater.append((trumf, vrak))
            }
        }
        for trumf in trumfKandidater {
            for vrak in vrakKandidater(hånd: hånd16, antall: antall, trumfFarge: trumf) {
                leggTil(trumf, vrak)
            }
            // Det nevrale nettets forslag prøves som egen kandidat – det er
            // trent på nettopp dette valget, og simuleringen dømmer det på
            // lik linje med de heuristiske kandidatene.
            if let hjerne = NevroHjerne.delt {
                let forslag = NevroSpiller(sete: sete, hjerne: hjerne).velgByttekort(engine: engine)
                if forslag.count == antall {
                    leggTil(trumf, Kortmaske.maske(forslag))
                }
            }
        }
        guard !kandidater.isEmpty else { return [] }

        var klarte = [Double](repeating: 0, count: kandidater.count)
        var sumStikk = [Double](repeating: 0, count: kandidater.count)
        let profiler = BudProfil.fra(bids: engine.bids, minsteBud: regler.minsteBud)
        for _ in 0..<konfig.verdenerVedBytte {
            let (hender, _) = sampleUtdeling(
                pool: Kortmaske.alle & ~hånd16,
                perSete: regler.kortPerSpiller, minHånd: hånd16
            )
            let vekt = budVekt(profiler: profiler, hender: hender,
                               spiltAv: nil, stikkTotalt: regler.kortPerSpiller)
            for (i, kandidat) in kandidater.enumerated() {
                var h = hender
                let minH = hånd16 & ~kandidat.vrak
                h[sete] = minH
                var lag: UInt8 = 1 << UInt8(sete)
                var plikt: Int?
                if engine.erSolo {
                    // Valgfritt uttrekk: en trumf jeg selv kan stikke over.
                    plikt = soloUttrekk(farge: kandidat.trumf, minHånd: minH, sett: hånd16)
                } else if let ønske = høyesteManglende(i: kandidat.trumf, utenfor: hånd16),
                          let makker = eier(av: ønske, i: h) {
                    lag |= 1 << UInt8(makker)
                    plikt = ønske
                }
                let tilstand = Spilltilstand(
                    hender: h, leder: sete, pågående: [], trumfFarge: kandidat.trumf,
                    lagMaske: lag, budgiver: sete, pliktkort: plikt, førsteStikk: true
                )
                let stikk = GrådigSpiller.lagStikk(tilstand, eksaktFra: konfig.eksaktStikkGrense)
                if stikk >= mål { klarte[i] += vekt }
                sumStikk[i] += vekt * Double(stikk)
            }
        }
        let beste = kandidater.indices.max { a, b in
            (klarte[a], sumStikk[a]) < (klarte[b], sumStikk[b])
        }!
        return Kortmaske.kortliste(kandidater[beste].vrak)
    }

    /// Kandidat-vrak for en gitt trumffarge: det heuristiske grunnvraket
    /// pluss varianter som tømmer korte sidefarger helt (renons).
    private func vrakKandidater(hånd: UInt64, antall: Int, trumfFarge: Int?) -> [UInt64] {
        var resultat = [Self.heuristiskVrak(hånd: hånd, antall: antall, trumfFarge: trumfFarge)]
        for farge in 0..<4 where farge != trumfFarge {
            let iFargen = hånd & Kortmaske.fargeMaske(farge)
            let lengde = iFargen.nonzeroBitCount
            guard lengde > 0, lengde <= antall else { continue }
            var vrak = iFargen
            if lengde < antall {
                vrak |= Self.heuristiskVrak(
                    hånd: hånd & ~iFargen, antall: antall - lengde, trumfFarge: trumfFarge
                )
            }
            resultat.append(vrak)
        }
        return resultat
    }

    /// Raskt vrak uten søk: behold trumf, ess og lange farger; kast lave
    /// kort fra korte sidefarger.
    static func heuristiskVrak(hånd: UInt64, antall: Int, trumfFarge: Int?) -> UInt64 {
        let indekser = Kortmaske.indekser(hånd)
        func beholdVerdi(_ idx: Int) -> Int {
            let farge = idx / 13
            let lengde = (hånd & Kortmaske.fargeMaske(farge)).nonzeroBitCount
            return (farge == trumfFarge ? 1000 : 0)
                + (idx % 13 == 12 ? 500 : 0)
                + idx % 13
                + lengde * 3
        }
        return indekser
            .sorted { beholdVerdi($0) < beholdVerdi($1) }
            .prefix(antall)
            .reduce(0) { $0 | (1 << UInt64($1)) }
    }

    // MARK: - Trumf og etterlysning

    /// Trumfvalg og etterlysning simulert per kandidat. Ved tallbud og
    /// Amerikaner er etterlysningen makkeren (høyeste manglende trumf);
    /// ved solo prøves både ingen etterlysning og et uttrekkskort man selv
    /// kan stikke over.
    func velgTrumfOgMakker(engine: GameEngine) -> (Suit, Card?)? {
        guard engine.phase == .velgTrumf, engine.budgiverSeat == sete,
              engine.rules.antallSpillere == 4,
              let budAction = engine.høyesteBud?.action else { return nil }
        let regler = engine.rules
        let mål: Int
        if case .bud(let n) = budAction { mål = n } else { mål = regler.kortPerSpiller }
        let minHånd = Kortmaske.maske(engine.hands[sete])
        let kastet = Kortmaske.maske(engine.kastet)

        var kandidater: [(suit: Suit, ønsket: Card?)] = []
        for suit in Kortmaske.farger {
            let ønskbare = engine.kortSomKanØnskes(trumf: suit)
            if engine.erSolo {
                kandidater.append((suit, nil))
                let fargeIdx = Kortmaske.fargeIndeks(suit)
                if let uttrekk = soloUttrekk(farge: fargeIdx, minHånd: minHånd, sett: minHånd | kastet) {
                    kandidater.append((suit, Kortmaske.kort(uttrekk)))
                }
            } else if let ønsket = ønskbare.first {
                kandidater.append((suit, ønsket))
            }
        }
        guard !kandidater.isEmpty else { return nil }

        var klarte = [Double](repeating: 0, count: kandidater.count)
        var sumStikk = [Double](repeating: 0, count: kandidater.count)
        let profiler = BudProfil.fra(bids: engine.bids, minsteBud: regler.minsteBud)
        for _ in 0..<konfig.verdenerVedBud {
            let (hender, _) = sampleUtdeling(
                pool: Kortmaske.alle & ~minHånd & ~kastet,
                perSete: regler.kortPerSpiller, minHånd: minHånd
            )
            let vekt = budVekt(profiler: profiler, hender: hender,
                               spiltAv: nil, stikkTotalt: regler.kortPerSpiller)
            for (i, kandidat) in kandidater.enumerated() {
                let ønskeIdx = kandidat.ønsket.map(Kortmaske.indeks)
                var lag: UInt8 = 1 << UInt8(sete)
                if !engine.erSolo, let ønskeIdx, let makker = eier(av: ønskeIdx, i: hender) {
                    lag |= 1 << UInt8(makker)
                }
                let tilstand = Spilltilstand(
                    hender: hender, leder: sete, pågående: [],
                    trumfFarge: Kortmaske.fargeIndeks(kandidat.suit),
                    lagMaske: lag, budgiver: sete, pliktkort: ønskeIdx,
                    førsteStikk: true
                )
                let stikk = GrådigSpiller.lagStikk(tilstand, eksaktFra: konfig.eksaktStikkGrense)
                if stikk >= mål { klarte[i] += vekt }
                sumStikk[i] += vekt * Double(stikk)
            }
        }
        let beste = kandidater.indices.max { a, b in
            (klarte[a], sumStikk[a]) < (klarte[b], sumStikk[b])
        }!
        return kandidater[beste]
    }

    // MARK: - Kortspill

    func velgKort(engine: GameEngine) -> Card? {
        let lovlige = engine.lovligeKort(for: sete)
        guard !lovlige.isEmpty else { return nil }
        if lovlige.count == 1 { return lovlige[0] }
        guard let innsikt = Spillinnsikt(engine: engine, sete: sete) else { return nil }

        // Likeverdige kort (ingen gjenværende kort imellom) prøves bare én gang.
        let pågåendeMaske = innsikt.pågående.reduce(UInt64(0)) { $0 | (1 << UInt64($1.indeks)) }
        let union = innsikt.ukjente | innsikt.minHånd | pågåendeMaske
        let kandidater = Spillregler.reduserteTrekk(lovlig: Kortmaske.maske(lovlige), union: union)
        if kandidater.count == 1 { return Kortmaske.kort(kandidater[0]) }

        let frist = Date().addingTimeInterval(konfig.tidsbudsjett)
        var sum = [Double](repeating: 0, count: kandidater.count)
        // Når hele resten løses eksakt gjelder sluttspillstaket; ellers det
        // ordinære taket (der begrenser tidsbudsjettet uansett først).
        let stikkIgjen = innsikt.antallKort[innsikt.leder] + (innsikt.pågående.isEmpty ? 0 : 1)
        let tak = stikkIgjen <= konfig.eksaktStikkGrense
            ? konfig.maksVerdenerSluttspill : konfig.maksVerdener
        var verdener = 0
        while verdener < tak {
            if verdener >= konfig.minVerdener, Date() >= frist { break }
            guard let verden = innsikt.sampleVerden(rng: &rng) else { break }
            // Verdener som strider mot budhistorikken teller mindre.
            let vekt = budVekt(profiler: innsikt.budProfiler, hender: verden.hender,
                               spiltAv: innsikt.spiltAvSete, stikkTotalt: innsikt.stikkTotalt)
            let dd = Dobbeltdummy()   // deles på tvers av kandidatene i samme verden
            for (i, kandidat) in kandidater.enumerated() {
                sum[i] += vekt * vurder(kandidat: kandidat, verden: verden, innsikt: innsikt, dd: dd)
            }
            verdener += 1
        }
        sisteVerdenstall = verdener
        guard verdener > 0 else { return nil }

        var besteIndeks = kandidater[0]
        var besteSum = sum[0]
        for (i, kandidat) in kandidater.enumerated().dropFirst() {
            let bedre = sum[i] > besteSum + 1e-9
            let liktMenBilligere = abs(sum[i] - besteSum) <= 1e-9
                && Kortmaske.kostnad(kandidat, trumfFarge: innsikt.trumfFarge)
                    < Kortmaske.kostnad(besteIndeks, trumfFarge: innsikt.trumfFarge)
            if bedre || liktMenBilligere {
                besteIndeks = kandidat
                besteSum = sum[i]
            }
        }
        return Kortmaske.kort(besteIndeks)
    }

    /// Verdien av å legge `kandidat` i den samplede verdenen: spill grådig
    /// fram til sluttspillgrensen, løs resten eksakt, og mål **forventet
    /// poengendring for eget sete** minus motstandernes – vektet mot
    /// stillingen i partiet. Kontrakten dominerer av seg selv (±2n/±n er
    /// de store poengene), egne stikk teller fullt utenfor budlaget, og å
    /// krysse målstreken (eller fôre en motstander over den) trumfer alt.
    private func vurder(kandidat: Int, verden: Verden, innsikt: Spillinnsikt, dd: Dobbeltdummy) -> Double {
        var t = Spilltilstand(
            hender: verden.hender, leder: innsikt.leder, pågående: innsikt.pågående,
            trumfFarge: innsikt.trumfFarge, lagMaske: verden.lagMaske,
            budgiver: innsikt.budgiver, pliktkort: innsikt.pliktkort,
            førsteStikk: innsikt.trickNummer == 0
        )
        var perSete = [0, 0, 0, 0]
        if let vinnerSete = Spillregler.utfør(&t, indeks: kandidat) {
            perSete[vinnerSete] += 1
        }
        t = GrådigSpiller.spillUt(t, stoppVedStikkIgjen: konfig.eksaktStikkGrense, perSete: &perSete)

        // Selve regnestykket bor i `Spillinnsikt.måltall`, slik at ISMCTS
        // bruker nøyaktig samme målfunksjon; her hentes bare egen komponent.
        let verdier = innsikt.måltall(
            lagMaske: verden.lagMaske, perSete: perSete, restLagStikk: dd.løs(t)
        )
        return verdier[innsikt.sete]
    }

    // MARK: - Budvekting

    /// Hvor sannsynlig er denne verdenen gitt det setene meldte? En hånd som
    /// er altfor svak for budet sitt – eller altfor sterk for passen sin –
    /// vektes ned. Vurderingen bruker setets FULLE hånd (gjenværende + spilt).
    private func budVekt(profiler: [BudProfil], hender: SIMD4<UInt64>,
                         spiltAv: [UInt64]?, stikkTotalt: Int) -> Double {
        guard konfig.budvekting else { return 1 }
        return Budvekt.vekt(profiler: profiler, hender: hender, spiltAv: spiltAv,
                            stikkTotalt: stikkTotalt, egetSete: sete)
    }

    // MARK: - Sampling før spillet

    /// Fordeler potten av ukjente kort tilfeldig: `perSete` kort til hvert av
    /// de tre andre setene, resten (talong/vrak) returneres separat.
    private func sampleUtdeling(pool: UInt64, perSete: Int, minHånd: UInt64) -> (hender: SIMD4<UInt64>, rest: UInt64) {
        var indekser = Kortmaske.indekser(pool)
        indekser.shuffle(using: &rng)
        var hender = SIMD4<UInt64>(repeating: 0)
        hender[sete] = minHånd
        var neste = 0
        for s in 0..<4 where s != sete {
            for kortIdx in indekser[neste..<(neste + perSete)] {
                hender[s] |= 1 << UInt64(kortIdx)
            }
            neste += perSete
        }
        let rest = indekser[neste...].reduce(UInt64(0)) { $0 | (1 << UInt64($1)) }
        return (hender, rest)
    }

    private func eier(av kortIdx: Int, i hender: SIMD4<UInt64>) -> Int? {
        (0..<4).first { hender[$0] & (1 << UInt64(kortIdx)) != 0 }
    }

    /// Høyeste kort i fargen som ikke ligger i den gitte masken.
    private func høyesteManglende(i farge: Int, utenfor maske: UInt64) -> Int? {
        for valør in stride(from: 12, through: 0, by: -1) {
            let idx = farge * 13 + valør
            if maske & (1 << UInt64(idx)) == 0 { return idx }
        }
        return nil
    }

    /// Solo-uttrekk: høyeste trumf utenfor `sett` (hånd + vrak) som ligger
    /// UNDER mitt eget toppkort i fargen – den kan tvinges fram i første
    /// stikk og stikkes over.
    private func soloUttrekk(farge: Int, minHånd: UInt64, sett: UInt64) -> Int? {
        let mine = minHånd & Kortmaske.fargeMaske(farge)
        guard mine != 0 else { return nil }
        let minTopp = Kortmaske.høyeste(mine)
        for valør in stride(from: 12, through: 0, by: -1) {
            let idx = farge * 13 + valør
            if idx >= minTopp { continue }
            if sett & (1 << UInt64(idx)) == 0 { return idx }
        }
        return nil
    }

    /// Tilstanden der jeg deklarerer med gitt trumffarge i en samplet verden:
    /// talongen tas opp, et heuristisk vrak legges bort, og makkeren er den
    /// som har det høyeste trumfkortet jeg aldri så.
    private func deklarasjonsplan(
        hånd: UInt64, farge: Suit, hender: SIMD4<UInt64>, talon: UInt64, regler: GameRules
    ) -> Spilltilstand? {
        let fargeIdx = Kortmaske.fargeIndeks(farge)
        var minH = hånd | talon
        if regler.antallByttekort > 0 {
            minH &= ~Self.heuristiskVrak(hånd: minH, antall: regler.antallByttekort, trumfFarge: fargeIdx)
        }
        guard let ønskeIdx = høyesteManglende(i: fargeIdx, utenfor: hånd | talon) else { return nil }
        var h = hender
        h[sete] = minH
        guard let makker = eier(av: ønskeIdx, i: h) else { return nil }
        return Spilltilstand(
            hender: h, leder: sete, pågående: [], trumfFarge: fargeIdx,
            lagMaske: 1 << UInt8(sete) | 1 << UInt8(makker),
            budgiver: sete, pliktkort: ønskeIdx, førsteStikk: true
        )
    }

    /// Solo-scenario i en samplet verden: alene med trumf, og et valgfritt
    /// uttrekkskort som må legges i første stikk.
    private func soloPlan(
        hånd: UInt64, farge: Suit, hender: SIMD4<UInt64>, talon: UInt64, regler: GameRules
    ) -> Spilltilstand? {
        let fargeIdx = Kortmaske.fargeIndeks(farge)
        var minH = hånd | talon
        if regler.antallByttekort > 0 {
            minH &= ~Self.heuristiskVrak(hånd: minH, antall: regler.antallByttekort, trumfFarge: fargeIdx)
        }
        var h = hender
        h[sete] = minH
        let uttrekk = soloUttrekk(farge: fargeIdx, minHånd: minH, sett: hånd | talon)
        return Spilltilstand(
            hender: h, leder: sete, pågående: [], trumfFarge: fargeIdx,
            lagMaske: 1 << UInt8(sete), budgiver: sete,
            pliktkort: uttrekk, førsteStikk: true
        )
    }

    /// Hva passer jeg til? Den sterkeste av de andre henter sitt beste bud i
    /// denne verdenen, og jeg teller stikkene (eller makkergevinsten) mine.
    private func passVerdi(hender: SIMD4<UInt64>, talon: UInt64, regler: GameRules) -> Double {
        var besteSete = -1
        var besteEstimat = -1.0
        var besteFarge = Suit.spar
        for s in 0..<4 where s != sete {
            let (farge, estimat) = AIPlayer.besteTrumf(hånd: Kortmaske.kortliste(hender[s]))
            if estimat > besteEstimat {
                besteSete = s
                besteEstimat = estimat
                besteFarge = farge
            }
        }
        guard besteSete >= 0 else { return 0 }
        let fargeIdx = Kortmaske.fargeIndeks(besteFarge)
        var h = hender
        var deresHånd = hender[besteSete] | talon
        if regler.antallByttekort > 0 {
            deresHånd &= ~Self.heuristiskVrak(hånd: deresHånd, antall: regler.antallByttekort, trumfFarge: fargeIdx)
        }
        h[besteSete] = deresHånd
        let ønskeIdx = høyesteManglende(i: fargeIdx, utenfor: hender[besteSete] | talon)
        let makker = ønskeIdx.flatMap { eier(av: $0, i: h) }
        let lag: UInt8 = 1 << UInt8(besteSete) | (makker.map { 1 << UInt8($0) } ?? 0)
        let tilstand = Spilltilstand(
            hender: h, leder: besteSete, pågående: [], trumfFarge: fargeIdx,
            lagMaske: lag, budgiver: besteSete,
            pliktkort: makker != nil ? ønskeIdx : nil, førsteStikk: true
        )
        var perSete = [0, 0, 0, 0]
        _ = GrådigSpiller.spillUt(tilstand, perSete: &perSete)

        let deresBud = max(regler.minsteBud, min(regler.maksBud, Int(besteEstimat.rounded())))
        if makker == sete {
            // Jeg blir med på laget: makkeren vinner eller taper budet (1×).
            let lagStikk = perSete[besteSete] + perSete[sete]
            return lagStikk >= deresBud ? Double(deresBud) : -Double(deresBud)
        }
        return Double(perSete[sete])
    }
}
