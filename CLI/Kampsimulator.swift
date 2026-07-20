import Foundation

/// Kjører hele partier med motoren og AI-ene i terminalen – slik at
/// MesterAI kan ses i aksjon (og måles) uten Mac, Xcode eller simulator.
struct Kampsimulator {
    struct Innstillinger {
        /// Vanskelighetsgrad per sete (indeks = sete).
        var nivåer: [AIDifficulty] = [.president, .vanskelig, .vanskelig, .vanskelig]
        /// Frø for utdelingene og MesterAI-ens sampling. Merk: setene som
        /// ikke spiller President bruker useedet støy, så full determinisme
        /// krever President på alle seter.
        var seed: UInt64?
        /// nil = først til målPoeng; ellers fast antall runder.
        var maksRunder: Int?
        var målPoeng = 100
        /// Tidsbudsjett per MesterAI-kortvalg (sekunder).
        var tidsbudsjett = 0.2
        var utskrift = true
    }

    struct Partiresultat {
        var sluttpoeng: [Int]
        var vinner: Int
        var runder: [RoundResult]
        var varighet: TimeInterval
    }

    let innstillinger: Innstillinger
    private let navn: [String]

    init(innstillinger: Innstillinger) {
        self.innstillinger = innstillinger
        self.navn = innstillinger.nivåer.enumerated().map { "S\($0.offset) \($0.element.rawValue)" }
    }

    /// MesterAI-konfigurasjon skalert til CLI-ens tidsbudsjett: ved korte
    /// budsjetter (CI) reduseres antall samplede verdener tilsvarende.
    static func mesterKonfig(tidsbudsjett: Double) -> MesterKonfig {
        var k = MesterKonfig.automatisk()
        k.tidsbudsjett = tidsbudsjett
        if tidsbudsjett <= 0.1 {
            k.maksVerdener = 12
            k.minVerdener = 4
            k.verdenerVedBud = 20
            k.verdenerVedBytte = 10
        }
        return k
    }

    // MARK: - Ett parti

    func spillParti() -> Partiresultat? {
        let inn = innstillinger
        var rules = GameRules()
        rules.målPoeng = inn.målPoeng
        rules.maksRunder = inn.maksRunder
        let engine = GameEngine(rules: rules)

        let konfig = Self.mesterKonfig(tidsbudsjett: inn.tidsbudsjett)
        // Heuristikk-setene (via AIPlayer) skal bruke samme budsjett om
        // noen av dem er President uten eget frø.
        MesterAI.overstyrKonfig = konfig

        // President-seter kjøres rett mot MesterAI slik at frøet styrer
        // samplingen; øvrige seter spiller via AIPlayer-heuristikken.
        var mestere: [Int: MesterAI] = [:]
        var heuristikere: [Int: AIPlayer] = [:]
        for (sete, nivå) in inn.nivåer.enumerated() {
            if nivå.spillerPerfekt {
                mestere[sete] = MesterAI(
                    sete: sete, konfig: konfig,
                    seed: inn.seed.map { $0 &+ UInt64(sete) &* 7919 }
                )
            } else {
                heuristikere[sete] = AIPlayer(sete: sete, nivå: nivå)
            }
        }

        let start = Date()
        var rundeNr = 0
        skriv("🃏 Nytt parti – \(inn.maksRunder.map { "\($0) runder" } ?? "først til \(inn.målPoeng) poeng")")
        skriv("   Seter: " + navn.joined(separator: " · "))
        if let seed = inn.seed { skriv("   Frø: \(seed)") }

        while engine.phase != .spillFerdig {
            rundeNr += 1
            guard rundeNr <= 200 else {
                skriv("⚠️ Avbrutt: over 200 runder uten avgjørelse.")
                return nil
            }
            engine.startRunde(seed: inn.seed.map { $0 &+ UInt64(rundeNr) &* 0x9E37 })
            skriv("")
            skriv("── Runde \(rundeNr) ──────────────────────────────")
            guard spillRunde(engine: engine, mestere: mestere, heuristikere: heuristikere) else { return nil }
            skrivRundeResultat(engine: engine)
        }

        let vinner = engine.vinnerSeat ?? 0
        skriv("")
        skriv("🏁 Partiet er ferdig etter \(engine.rundeResultater.count) runder!")
        skriv("   Sluttpoeng: " + poengLinje(engine.scores))
        skriv("🏆 Vinner: \(navn[vinner])")
        return Partiresultat(
            sluttpoeng: engine.scores, vinner: vinner,
            runder: engine.rundeResultater,
            varighet: Date().timeIntervalSince(start)
        )
    }

    /// Spiller én runde fra budrunde til rundeFerdig/spillFerdig.
    private func spillRunde(engine: GameEngine, mestere: [Int: MesterAI], heuristikere: [Int: AIPlayer]) -> Bool {
        var budLinje: [String] = []
        var vakt = 0
        while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
            vakt += 1
            guard vakt <= 500 else {
                skriv("⚠️ Avbrutt: runden kom aldri i mål.")
                return false
            }
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                let bud = velgBud(sete: sete, engine: engine, mestere: mestere, heuristikere: heuristikere)
                budLinje.append("\(navn[sete]): \(bud.beskrivelse)")
                let førBudCount = engine.bids.count
                engine.giBud(seat: sete, action: bud)
                if engine.bids.count <= førBudCount {
                    // Alle passet: motoren delte ut på nytt.
                    skriv("Budrunde: " + budLinje.joined(separator: " · "))
                    skriv("Alle passet – deler ut på nytt.")
                    budLinje = []
                }
                if engine.phase != .budrunde {
                    skriv("Budrunde: " + budLinje.joined(separator: " · "))
                    if let vinner = engine.høyesteBud {
                        skriv("→ \(navn[vinner.seat]) vant budrunden med \(vinner.action.beskrivelse)")
                    }
                }
            case .byttekort:
                let sete = engine.budgiverSeat!
                let vrak = velgByttekort(sete: sete, engine: engine, mestere: mestere, heuristikere: heuristikere)
                engine.kastByttekort(vrak, seat: sete)
                skriv("\(navn[sete]) tar opp talongen og vraker \(vrak.count) kort (skjult).")
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                let (suit, ønsket) = velgTrumf(sete: sete, engine: engine, mestere: mestere, heuristikere: heuristikere)
                engine.velgTrumf(suit: suit, ønsket: ønsket)
                var linje = "\(navn[sete]) velger trumf \(suit.rawValue) \(suit.navn)"
                if let ønsket { linje += " og etterlyser \(ønsket.kortSymbol)" }
                skriv(linje + ".")
            case .spill:
                let sete = engine.aktivSpiller
                let kort = velgKort(sete: sete, engine: engine, mestere: mestere, heuristikere: heuristikere)
                let stikkNr = engine.trickNummer + 1
                engine.spill(kort: kort, seat: sete)
                if engine.currentTrick.isEmpty, let vinner = engine.sisteStikkVinner {
                    let lagt = engine.sisteStikk
                        .map { "\(kortNavn($0.seat)) \($0.card.kortSymbol)" }
                        .joined(separator: "  ")
                    var linje = "Stikk \(String(format: "%2d", stikkNr)): \(lagt) → \(navn[vinner])"
                    if engine.makkerAvslørt, engine.sisteStikk.contains(where: { $0.card == engine.ønsketKort }) {
                        linje += "  (makkeren avslørt!)"
                    }
                    skriv(linje)
                }
            default:
                return true
            }
        }
        return true
    }

    private func skrivRundeResultat(engine: GameEngine) {
        guard let runde = engine.sisteRunde else { return }
        let lag = runde.makker.map { "laget (\(navn[runde.budgiver]) + \(navn[$0]))" } ?? navn[runde.budgiver]
        let stikk = [runde.budgiver, runde.makker].compactMap { $0 }
            .reduce(0) { $0 + runde.stikkPerSpiller[$1] }
        skriv("Resultat: \(lag) tok \(stikk) stikk på \(runde.bud.beskrivelse) → \(runde.klarte ? "KLARTE DET ✓" : "røk ✗")")
        skriv("Poeng:  " + poengLinje(engine.scores))
    }

    // MARK: - Setevalg med trygge fallbacks (samme mønster som testene)

    private func velgBud(sete: Int, engine: GameEngine, mestere: [Int: MesterAI], heuristikere: [Int: AIPlayer]) -> BidAction {
        let lovlige = engine.lovligeBud(for: sete)
        if let mester = mestere[sete] {
            let bud = mester.velgBud(engine: engine)
            if lovlige.contains(bud) { return bud }
        }
        if let ai = heuristikere[sete] {
            let bud = ai.velgBud(engine: engine)
            if lovlige.contains(bud) { return bud }
        }
        return .pass
    }

    private func velgByttekort(sete: Int, engine: GameEngine, mestere: [Int: MesterAI], heuristikere: [Int: AIPlayer]) -> [Card] {
        let antall = engine.rules.antallByttekort
        let hånd = engine.hands[sete]
        if let mester = mestere[sete] {
            let vrak = mester.velgByttekort(engine: engine)
            if vrak.count == antall, vrak.allSatisfy({ hånd.contains($0) }) { return vrak }
        }
        if let ai = heuristikere[sete] {
            let vrak = ai.velgByttekort(engine: engine)
            if vrak.count == antall, vrak.allSatisfy({ hånd.contains($0) }) { return vrak }
        }
        return Array(hånd.suffix(antall))
    }

    private func velgTrumf(sete: Int, engine: GameEngine, mestere: [Int: MesterAI], heuristikere: [Int: AIPlayer]) -> (Suit, Card?) {
        if let mester = mestere[sete], let valg = mester.velgTrumfOgMakker(engine: engine),
           valg.1 == nil || engine.kortSomKanØnskes(trumf: valg.0).contains(valg.1!) {
            return valg
        }
        if let ai = heuristikere[sete], let valg = ai.velgTrumfOgMakker(engine: engine) {
            return valg
        }
        return (.spar, engine.kortSomKanØnskes(trumf: .spar).first)
    }

    private func velgKort(sete: Int, engine: GameEngine, mestere: [Int: MesterAI], heuristikere: [Int: AIPlayer]) -> Card {
        let lovlige = engine.lovligeKort(for: sete)
        if let mester = mestere[sete], let kort = mester.velgKort(engine: engine), lovlige.contains(kort) {
            return kort
        }
        if let ai = heuristikere[sete], let kort = ai.velgKort(engine: engine), lovlige.contains(kort) {
            return kort
        }
        return lovlige[0]
    }

    // MARK: - Utskrift

    private func kortNavn(_ sete: Int) -> String { "S\(sete)" }

    private func poengLinje(_ poeng: [Int]) -> String {
        poeng.enumerated()
            .map { "\(navn[$0.offset]): \($0.element)" }
            .joined(separator: " · ")
    }

    private func skriv(_ tekst: String) {
        if innstillinger.utskrift { print(tekst) }
    }
}

private extension AIPlayer {
    init(sete: Int, nivå: AIDifficulty) {
        self.init(seat: sete, difficulty: nivå, personality: .balansert)
    }
}
