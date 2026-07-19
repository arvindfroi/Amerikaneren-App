import Foundation

/// Innstillinger for søket i MesterAI. Standardverdiene er balansert for å
/// holde trekktiden godt under et halvt sekund på en telefon.
struct MesterKonfig {
    /// Maks antall samplede verdener per kortvalg.
    var maksVerdener = 28
    /// Minste antall verdener som alltid evalueres, uansett tidsbudsjett.
    var minVerdener = 8
    /// Når så mange stikk (eller færre) gjenstår, løses resten eksakt med
    /// dobbeltdummy; før det spilles grådig fram til grensen.
    var eksaktStikkGrense = 6
    /// Myk tidsgrense for ett kortvalg.
    var tidsbudsjett: TimeInterval = 0.45
    /// Antall samplede utdelinger for budvurdering og trumfvalg.
    var verdenerVedBud = 48
}

/// Søkebasert toppspiller («President»-nivået). Tre grep gjør den sterk:
///
/// 1. **Determinisert Monte Carlo**: de ukjente kortene samples i mange
///    mulige verdener som stemmer med alt setet lovlig vet (renonser,
///    makkerplikt-slutninger, hvem som kan ha det etterlyste kortet).
/// 2. **Eksakt sluttspill**: hver verden spilles grådig fram til få stikk
///    gjenstår, og resten løses optimalt med dobbeltdummy-søk.
/// 3. **Simulert budgivning**: bud, pass og Amerikaner-melding sammenliknes
///    på forventet poengsum over de samme samplede verdenene.
///
/// Den ser aldri skjulte kort – all innsikt kommer fra `Spillinnsikt`.
final class MesterAI {
    let sete: Int
    var konfig: MesterKonfig
    private var rng: SeededGenerator

    init(sete: Int, konfig: MesterKonfig = MesterKonfig(), seed: UInt64? = nil) {
        self.sete = sete
        self.konfig = konfig
        self.rng = SeededGenerator(seed: seed ?? UInt64.random(in: 1...UInt64.max))
    }

    // MARK: - Budgivning

    func velgBud(engine: GameEngine) -> BidAction {
        let lovlige = engine.lovligeBud(for: sete)
        guard !lovlige.isEmpty, engine.rules.antallSpillere == 4 else { return .pass }
        let hånd = engine.hands[sete]
        let minHånd = Kortmaske.maske(hånd)
        let minsteBud = lovlige.compactMap { action -> Int? in
            if case .bud(let n) = action { return n }
            return nil
        }.min()

        // Amerikaner vurderes bare når hånden i det hele tatt er i nærheten –
        // ellers er utfallet −52 gitt på forhånd.
        let (heuristiskFarge, estimat) = AIPlayer.besteTrumf(hånd: hånd)
        let vurderAmerikaner = lovlige.contains(.amerikaner) && estimat >= 10.0

        var deklStikk: [Int] = []
        var passVerdier: [Double] = []
        var amerikanerKlart = 0

        for _ in 0..<konfig.verdenerVedBud {
            let hender = sampleUtdeling(minHånd: minHånd)

            // Scenario 1: jeg vinner budrunden med min beste farge.
            if let plan = deklarasjonsplan(hånd: minHånd, farge: heuristiskFarge, hender: hender) {
                deklStikk.append(GrådigSpiller.lagStikk(plan, eksaktFra: konfig.eksaktStikkGrense))
            }

            // Scenario 2: jeg passer, og den sterkeste motstanderen spiller.
            passVerdier.append(passVerdi(hender: hender))

            // Scenario 3: Amerikaner – alle 13 alene, uten trumf.
            if vurderAmerikaner {
                let solo = Spilltilstand(
                    hender: hender, leder: sete, pågående: [], trumfFarge: nil,
                    lagMaske: 1 << UInt8(sete), budgiver: sete,
                    pliktkort: nil, førsteStikk: true
                )
                if GrådigSpiller.lagStikk(solo, eksaktFra: konfig.eksaktStikkGrense) == 13 {
                    amerikanerKlart += 1
                }
            }
        }

        let antall = Double(max(1, deklStikk.count))
        let evPass = passVerdier.isEmpty ? 0 : passVerdier.reduce(0, +) / Double(passVerdier.count)
        var besteAction = BidAction.pass
        var besteEV = evPass

        if let b = minsteBud {
            let p = Double(deklStikk.filter { $0 >= b }.count) / antall
            let ev = Double(b) * (2 * p - 1)
            if ev > besteEV {
                besteAction = .bud(b)
                besteEV = ev
            }
        }
        if vurderAmerikaner {
            let p = Double(amerikanerKlart) / Double(konfig.verdenerVedBud)
            let ev = Double(engine.rules.målPoeng) * (2 * p - 1)
            if ev > besteEV {
                besteAction = .amerikaner
                besteEV = ev
            }
        }
        return besteAction
    }

    // MARK: - Trumf og makker

    func velgTrumfOgMakker(engine: GameEngine) -> (Suit, Card)? {
        guard engine.phase == .velgTrumf, engine.budgiverSeat == sete,
              engine.rules.antallSpillere == 4 else { return nil }
        guard case .bud(let mål)? = engine.høyesteBud?.action else { return nil }
        let minHånd = Kortmaske.maske(engine.hands[sete])

        // Kandidat per farge: be om det høyeste trumfkortet man mangler –
        // da blir den sterkeste manglende trumfen med på laget.
        var kandidater: [(suit: Suit, ønsket: Card)] = []
        for suit in Kortmaske.farger {
            if let ønsket = engine.kortSomKanØnskes(trumf: suit).first {
                kandidater.append((suit, ønsket))
            }
        }
        guard !kandidater.isEmpty else { return nil }

        var klarte = [Int](repeating: 0, count: kandidater.count)
        var sumStikk = [Int](repeating: 0, count: kandidater.count)
        for _ in 0..<konfig.verdenerVedBud {
            let hender = sampleUtdeling(minHånd: minHånd)
            for (i, kandidat) in kandidater.enumerated() {
                let ønskeIdx = Kortmaske.indeks(kandidat.ønsket)
                let makker = eier(av: ønskeIdx, i: hender)
                let tilstand = Spilltilstand(
                    hender: hender, leder: sete, pågående: [],
                    trumfFarge: Kortmaske.fargeIndeks(kandidat.suit),
                    lagMaske: 1 << UInt8(sete) | (makker.map { 1 << UInt8($0) } ?? 0),
                    budgiver: sete, pliktkort: ønskeIdx, førsteStikk: true
                )
                let stikk = GrådigSpiller.lagStikk(tilstand, eksaktFra: konfig.eksaktStikkGrense)
                if stikk >= mål { klarte[i] += 1 }
                sumStikk[i] += stikk
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
        var verdener = 0
        while verdener < konfig.maksVerdener {
            if verdener >= konfig.minVerdener, Date() >= frist { break }
            guard let verden = innsikt.sampleVerden(rng: &rng) else { break }
            let dd = Dobbeltdummy()   // deles på tvers av kandidatene i samme verden
            for (i, kandidat) in kandidater.enumerated() {
                sum[i] += vurder(kandidat: kandidat, verden: verden, innsikt: innsikt, dd: dd)
            }
            verdener += 1
        }
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
    /// fram til sluttspillgrensen, løs resten eksakt, og mål resultatet mot
    /// budet. Budgiverlaget teller suksess først og stikk deretter;
    /// forsvaret teller det motsatte.
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

        var lagStikk = dd.løs(t)
        for s in 0..<4 where verden.lagMaske & (1 << UInt8(s)) != 0 {
            lagStikk += innsikt.stikkTatt[s] + perSete[s]
        }

        let mål: Int
        switch innsikt.bud {
        case .bud(let n): mål = n
        case .amerikaner: mål = 13
        case .pass: mål = 13
        }
        let suksess = lagStikk >= mål
        return innsikt.jegErBudgiverlag
            ? (suksess ? 1000.0 : 0.0) + Double(lagStikk)
            : (suksess ? 0.0 : 1000.0) + Double(13 - lagStikk)
    }

    // MARK: - Sampling før spillet

    /// Tilfeldig fordeling av de 39 ukjente kortene før første stikk.
    private func sampleUtdeling(minHånd: UInt64) -> SIMD4<UInt64> {
        var pool = Kortmaske.indekser(Kortmaske.alle & ~minHånd)
        pool.shuffle(using: &rng)
        var hender = SIMD4<UInt64>(repeating: 0)
        hender[sete] = minHånd
        var neste = 0
        for s in 0..<4 where s != sete {
            for kortIdx in pool[neste..<(neste + 13)] {
                hender[s] |= 1 << UInt64(kortIdx)
            }
            neste += 13
        }
        return hender
    }

    private func eier(av kortIdx: Int, i hender: SIMD4<UInt64>) -> Int? {
        (0..<4).first { hender[$0] & (1 << UInt64(kortIdx)) != 0 }
    }

    /// Tilstanden der jeg deklarerer med gitt trumffarge i en samplet verden.
    private func deklarasjonsplan(hånd: UInt64, farge: Suit, hender: SIMD4<UInt64>) -> Spilltilstand? {
        let fargeIdx = Kortmaske.fargeIndeks(farge)
        var ønskeIdx: Int?
        for valør in stride(from: 12, through: 0, by: -1) {
            let idx = fargeIdx * 13 + valør
            if hånd & (1 << UInt64(idx)) == 0 { ønskeIdx = idx; break }
        }
        guard let ønskeIdx, let makker = eier(av: ønskeIdx, i: hender) else { return nil }
        return Spilltilstand(
            hender: hender, leder: sete, pågående: [], trumfFarge: fargeIdx,
            lagMaske: 1 << UInt8(sete) | 1 << UInt8(makker),
            budgiver: sete, pliktkort: ønskeIdx, førsteStikk: true
        )
    }

    /// Hva passer jeg til? Den sterkeste av de andre henter sitt beste bud i
    /// denne verdenen, og jeg teller stikkene (eller makkergevinsten) mine.
    private func passVerdi(hender: SIMD4<UInt64>) -> Double {
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
        var ønskeIdx: Int?
        for valør in stride(from: 12, through: 0, by: -1) {
            let idx = fargeIdx * 13 + valør
            if hender[besteSete] & (1 << UInt64(idx)) == 0 { ønskeIdx = idx; break }
        }
        let makker = ønskeIdx.flatMap { eier(av: $0, i: hender) }
        let lag: UInt8 = 1 << UInt8(besteSete) | (makker.map { 1 << UInt8($0) } ?? 0)
        let tilstand = Spilltilstand(
            hender: hender, leder: besteSete, pågående: [], trumfFarge: fargeIdx,
            lagMaske: lag, budgiver: besteSete, pliktkort: ønskeIdx, førsteStikk: true
        )
        var perSete = [0, 0, 0, 0]
        _ = GrådigSpiller.spillUt(tilstand, perSete: &perSete)

        let deresBud = max(5, min(13, Int(besteEstimat.rounded())))
        if makker == sete {
            // Jeg blir med på laget: gevinsten er budet – eller tapet av det.
            let lagStikk = perSete[besteSete] + perSete[sete]
            return lagStikk >= deresBud ? Double(deresBud) : -Double(deresBud)
        }
        return Double(perSete[sete])
    }
}
