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
    /// Antall samplede utdelinger per vrak-kandidat i byttefasen.
    var verdenerVedBytte = 20
}

/// Søkebasert toppspiller («President»-nivået). Tre grep gjør den sterk:
///
/// 1. **Determinisert Monte Carlo**: de ukjente kortene samples i mange
///    mulige verdener som stemmer med alt setet lovlig vet (renonser,
///    makkerplikt-slutninger, hvem som kan ha det etterlyste kortet – og
///    at vrakede byttekort kan skjule det).
/// 2. **Eksakt sluttspill**: hver verden spilles grådig fram til få stikk
///    gjenstår, og resten løses optimalt med dobbeltdummy-søk.
/// 3. **Simulerte valg**: bud, byttekort-vrak, trumf og makkerkort
///    sammenliknes på forventet resultat over de samme samplede verdenene.
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
        let regler = engine.rules
        let hånd = engine.hands[sete]
        let minHånd = Kortmaske.maske(hånd)
        let minsteBud = lovlige.compactMap { action -> Int? in
            if case .bud(let n) = action { return n }
            return nil
        }.min()

        // Amerikaner vurderes bare når hånden i det hele tatt er i nærheten –
        // ellers er utfallet −målPoeng gitt på forhånd.
        let (heuristiskFarge, estimat) = AIPlayer.besteTrumf(hånd: hånd)
        let vurderAmerikaner = lovlige.contains(.amerikaner)
            && estimat + Double(regler.antallByttekort) * 0.4 >= 10.0

        var deklStikk: [Int] = []
        var passVerdier: [Double] = []
        var amerikanerKlart = 0
        var amerikanerTalt = 0

        for _ in 0..<konfig.verdenerVedBud {
            let (hender, talon) = sampleUtdeling(
                pool: Kortmaske.alle & ~minHånd,
                perSete: regler.kortPerSpiller, minHånd: minHånd
            )

            // Scenario 1: jeg vinner budrunden med min beste farge.
            if let plan = deklarasjonsplan(
                hånd: minHånd, farge: heuristiskFarge, hender: hender,
                talon: talon, regler: regler
            ) {
                deklStikk.append(GrådigSpiller.lagStikk(plan, eksaktFra: konfig.eksaktStikkGrense))
            }

            // Scenario 2: jeg passer, og den sterkeste motstanderen spiller.
            passVerdier.append(passVerdi(hender: hender, talon: talon, regler: regler))

            // Scenario 3: Amerikaner – alle stikkene alene, uten trumf.
            if vurderAmerikaner {
                var minH = minHånd | talon
                if regler.antallByttekort > 0 {
                    minH &= ~Self.heuristiskVrak(hånd: minH, antall: regler.antallByttekort, trumfFarge: nil)
                }
                var soloHender = hender
                soloHender[sete] = minH
                let solo = Spilltilstand(
                    hender: soloHender, leder: sete, pågående: [], trumfFarge: nil,
                    lagMaske: 1 << UInt8(sete), budgiver: sete,
                    pliktkort: nil, førsteStikk: true
                )
                amerikanerTalt += 1
                if GrådigSpiller.lagStikk(solo, eksaktFra: konfig.eksaktStikkGrense) == regler.kortPerSpiller {
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
        if vurderAmerikaner, amerikanerTalt > 0 {
            let p = Double(amerikanerKlart) / Double(amerikanerTalt)
            let ev = Double(engine.rules.målPoeng) * (2 * p - 1)
            if ev > besteEV {
                besteAction = .amerikaner
                besteEV = ev
            }
        }
        return besteAction
    }

    // MARK: - Byttekort

    /// Hvilke kort vrakes: kandidat-vrak genereres for de beste trumffargene
    /// (behold trumf/ess, tøm korte sidefarger for renons) og spilles ut mot
    /// samplede verdener; det vraket som oftest berger budet vinner.
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
        let trumfKandidater: [Int?]
        if engine.erAmerikaner {
            trumfKandidater = [nil]
        } else {
            let rangerte = Kortmaske.farger
                .map { suit in (Kortmaske.fargeIndeks(suit), AIPlayer.estimerStikk(hånd: engine.hands[sete], trumf: suit)) }
                .sorted { $0.1 > $1.1 }
            trumfKandidater = rangerte.prefix(2).map { Optional($0.0) }
        }

        var kandidater: [(trumf: Int?, vrak: UInt64)] = []
        var sett = Set<UInt64>()
        func leggTil(_ trumf: Int?, _ vrak: UInt64) {
            let nøkkel = vrak | (UInt64((trumf ?? 4) + 1) << 56)
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

        var klarte = [Int](repeating: 0, count: kandidater.count)
        var sumStikk = [Int](repeating: 0, count: kandidater.count)
        for _ in 0..<konfig.verdenerVedBytte {
            let (hender, _) = sampleUtdeling(
                pool: Kortmaske.alle & ~hånd16,
                perSete: regler.kortPerSpiller, minHånd: hånd16
            )
            for (i, kandidat) in kandidater.enumerated() {
                var h = hender
                h[sete] = hånd16 & ~kandidat.vrak
                var lag: UInt8 = 1 << UInt8(sete)
                var plikt: Int?
                if let trumf = kandidat.trumf {
                    // Be om høyeste trumf jeg ikke så i talongen – den lever
                    // garantert hos en motstander.
                    if let ønske = høyesteManglende(i: trumf, utenfor: hånd16),
                       let makker = eier(av: ønske, i: h) {
                        lag |= 1 << UInt8(makker)
                        plikt = ønske
                    }
                }
                let tilstand = Spilltilstand(
                    hender: h, leder: sete, pågående: [], trumfFarge: kandidat.trumf,
                    lagMaske: lag, budgiver: sete, pliktkort: plikt, førsteStikk: true
                )
                let stikk = GrådigSpiller.lagStikk(tilstand, eksaktFra: konfig.eksaktStikkGrense)
                if stikk >= mål { klarte[i] += 1 }
                sumStikk[i] += stikk
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

    // MARK: - Trumf og makker

    func velgTrumfOgMakker(engine: GameEngine) -> (Suit, Card)? {
        guard engine.phase == .velgTrumf, engine.budgiverSeat == sete,
              engine.rules.antallSpillere == 4 else { return nil }
        guard case .bud(let mål)? = engine.høyesteBud?.action else { return nil }
        let regler = engine.rules
        let minHånd = Kortmaske.maske(engine.hands[sete])
        let kastet = Kortmaske.maske(engine.kastet)

        // Kandidat per farge: be om det høyeste trumfkortet man mangler –
        // men aldri et kort man selv la i vraket (da spilte man jo alene).
        var kandidater: [(suit: Suit, ønsket: Card)] = []
        for suit in Kortmaske.farger {
            let ønskbare = engine.kortSomKanØnskes(trumf: suit)
            if let ønsket = ønskbare.first(where: { !engine.kastet.contains($0) }) ?? ønskbare.first {
                kandidater.append((suit, ønsket))
            }
        }
        guard !kandidater.isEmpty else { return nil }

        var klarte = [Int](repeating: 0, count: kandidater.count)
        var sumStikk = [Int](repeating: 0, count: kandidater.count)
        for _ in 0..<konfig.verdenerVedBud {
            let (hender, _) = sampleUtdeling(
                pool: Kortmaske.alle & ~minHånd & ~kastet,
                perSete: regler.kortPerSpiller, minHånd: minHånd
            )
            for (i, kandidat) in kandidater.enumerated() {
                let ønskeIdx = Kortmaske.indeks(kandidat.ønsket)
                let makker = eier(av: ønskeIdx, i: hender)
                let tilstand = Spilltilstand(
                    hender: hender, leder: sete, pågående: [],
                    trumfFarge: Kortmaske.fargeIndeks(kandidat.suit),
                    lagMaske: 1 << UInt8(sete) | (makker.map { 1 << UInt8($0) } ?? 0),
                    budgiver: sete, pliktkort: makker != nil ? ønskeIdx : nil,
                    førsteStikk: true
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
    /// forsvaret det motsatte.
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
        case .amerikaner, .pass: mål = innsikt.stikkTotalt
        }
        let suksess = lagStikk >= mål
        return innsikt.jegErBudgiverlag
            ? (suksess ? 1000.0 : 0.0) + Double(lagStikk)
            : (suksess ? 0.0 : 1000.0) + Double(innsikt.stikkTotalt - lagStikk)
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
            // Jeg blir med på laget: gevinsten er budet – eller tapet av det.
            let lagStikk = perSete[besteSete] + perSete[sete]
            return lagStikk >= deresBud ? Double(deresBud) : -Double(deresBud)
        }
        return Double(perSete[sete])
    }
}
