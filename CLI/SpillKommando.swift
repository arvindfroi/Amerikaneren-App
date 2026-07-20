import Foundation

/// Interaktivt hot-seat-spill i terminalen: mennesker og AI-er om
/// hverandre ved samme tastatur. Hendene holdes hemmelige ved at skjermen
/// tømmes når tastaturet bytter menneske. Alle valg gjøres via nummererte
/// menyer, så en strøm av «1» spiller alltid lovlig (brukes i røyktesten).
enum SpillKommando {

    enum Aktør {
        case menneske(String)
        case ai(AIDifficulty)

        var erMenneske: Bool { if case .menneske = self { return true }; return false }
    }

    struct Oppsett {
        var aktører: [Aktør] = [
            .menneske("Spiller 1"), .ai(.president),
            .menneske("Spiller 2"), .ai(.president),
        ]
        var seed: UInt64?
        var maksRunder: Int?
        var målPoeng = 100
        var tidsbudsjett = 0.2
    }

    // MARK: - Oppstart

    static func kjør(argv: [String], innstillinger: Kampsimulator.Innstillinger) {
        var oppsett = Oppsett()
        oppsett.seed = innstillinger.seed
        oppsett.maksRunder = innstillinger.maksRunder
        oppsett.målPoeng = innstillinger.målPoeng
        oppsett.tidsbudsjett = innstillinger.tidsbudsjett

        if let tekst = flagg("seter", argv) {
            let deler = tekst.components(separatedBy: ",")
            let aktører = deler.compactMap(aktør(fra:))
            if aktører.count == 4 {
                oppsett.aktører = aktører
            } else {
                print("⚠️ --seter trenger fire av menneske|lett|middels|vanskelig|president – bruker standard.")
            }
        }
        if let tekst = flagg("navn", argv) {
            var navn = tekst.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for i in oppsett.aktører.indices {
                if case .menneske = oppsett.aktører[i], !navn.isEmpty {
                    oppsett.aktører[i] = .menneske(navn.removeFirst())
                }
            }
        }
        var bord = Spillbord(oppsett: oppsett)
        bord.spill()
    }

    private static func flagg(_ navn: String, _ argv: [String]) -> String? {
        guard let i = argv.firstIndex(of: "--\(navn)"), i + 1 < argv.count else { return nil }
        return argv[i + 1]
    }

    private static func aktør(fra tekst: String) -> Aktør? {
        let t = tekst.trimmingCharacters(in: .whitespaces).lowercased()
        if t == "menneske" || t == "m" { return .menneske("Spiller") }
        return AIDifficulty.allCases.first { $0.rawValue.lowercased() == t }.map { .ai($0) }
    }
}

/// Selve bordet: kjører partiet og veksler mellom menneske- og AI-seter.
private struct Spillbord {
    let oppsett: SpillKommando.Oppsett
    let navn: [String]
    let engine: GameEngine
    var mestere: [Int: MesterAI] = [:]
    var heuristikere: [Int: AIPlayer] = [:]
    /// Setet til mennesket som så skjermen sist – styrer når den tømmes.
    var sisteMenneske: Int?

    init(oppsett: SpillKommando.Oppsett) {
        self.oppsett = oppsett

        var navneteller = 0
        self.navn = oppsett.aktører.enumerated().map { sete, aktør in
            switch aktør {
            case .menneske(let n):
                navneteller += 1
                return n == "Spiller" ? "Spiller \(navneteller)" : n
            case .ai(let nivå):
                return "\(nivå.rawValue) S\(sete)"
            }
        }

        var rules = GameRules()
        rules.målPoeng = oppsett.målPoeng
        rules.maksRunder = oppsett.maksRunder
        self.engine = GameEngine(rules: rules)

        let konfig = Kampsimulator.mesterKonfig(tidsbudsjett: oppsett.tidsbudsjett)
        MesterAI.overstyrKonfig = konfig
        for (sete, aktør) in oppsett.aktører.enumerated() {
            guard case .ai(let nivå) = aktør else { continue }
            if nivå.spillerPerfekt {
                mestere[sete] = MesterAI(
                    sete: sete, konfig: konfig,
                    seed: oppsett.seed.map { $0 &+ UInt64(sete) &* 7919 }
                )
            } else {
                heuristikere[sete] = AIPlayer(seat: sete, difficulty: nivå, personality: .balansert)
            }
        }
    }

    // MARK: - Partiløkke

    mutating func spill() {
        print("🃏 Amerikaneren – hot-seat: \(navn.joined(separator: " · "))")
        print("   \(oppsett.maksRunder.map { "\($0) runder" } ?? "Først til \(oppsett.målPoeng) poeng"). Menneskene deler tastatur; skjermen tømmes ved bytte.")

        var rundeNr = 0
        while engine.phase != .spillFerdig {
            rundeNr += 1
            engine.startRunde(seed: oppsett.seed.map { $0 &+ UInt64(rundeNr) &* 0x9E37 })
            print("")
            print("── Runde \(rundeNr) ──────────────────────────────")
            spillRunde()
            skrivRundeResultat()
        }

        let vinner = engine.vinnerSeat ?? 0
        print("")
        print("🏁 Ferdig etter \(engine.rundeResultater.count) runder!  " + poengLinje())
        print("🏆 \(navn[vinner]) vant\(oppsett.aktører[vinner].erMenneske ? "" : " – AI-en sto imot denne gangen")!")
    }

    private mutating func spillRunde() {
        var budLinje: [String] = []
        var vakt = 0
        while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
            vakt += 1
            guard vakt <= 500 else { print("⚠️ Runden kom aldri i mål – avbryter."); exit(1) }
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                let bud = velgBud(sete: sete)
                budLinje.append("\(navn[sete]): \(bud.beskrivelse)")
                let før = engine.bids.count
                engine.giBud(seat: sete, action: bud)
                if engine.bids.count <= før {
                    print("Alle passet – deler ut på nytt.")
                    budLinje = []
                }
                if engine.phase != .budrunde, let vinner = engine.høyesteBud {
                    print("Budrunde: " + budLinje.joined(separator: " · "))
                    print("→ \(navn[vinner.seat]) vant budrunden med \(vinner.action.beskrivelse)")
                }
            case .byttekort:
                let sete = engine.budgiverSeat!
                engine.kastByttekort(velgVrak(sete: sete), seat: sete)
                print("\(navn[sete]) tar opp talongen og vraker \(engine.rules.antallByttekort) kort (skjult).")
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                let (suit, ønsket) = velgTrumf(sete: sete)
                engine.velgTrumf(suit: suit, ønsket: ønsket)
                var linje = "\(navn[sete]) velger trumf \(suit.rawValue) \(suit.navn)"
                if let ønsket { linje += " og etterlyser \(ønsket.kortSymbol)" }
                print(linje + ".")
            case .spill:
                let sete = engine.aktivSpiller
                let kort = velgKort(sete: sete)
                let stikkNr = engine.trickNummer + 1
                engine.spill(kort: kort, seat: sete)
                if engine.currentTrick.isEmpty, let vinner = engine.sisteStikkVinner {
                    let lagt = engine.sisteStikk.map { "\(navn[$0.seat]) \($0.card.kortSymbol)" }.joined(separator: "  ")
                    var linje = "Stikk \(stikkNr): \(lagt) → \(navn[vinner])"
                    if engine.makkerAvslørt, engine.sisteStikk.contains(where: { $0.card == engine.ønsketKort }) {
                        linje += "  (makkeren avslørt!)"
                    }
                    print(linje)
                }
            default:
                return
            }
        }
    }

    // MARK: - Menneskevalg

    private mutating func velgBud(sete: Int) -> BidAction {
        let lovlige = engine.lovligeBud(for: sete)
        guard oppsett.aktører[sete].erMenneske else { return aiBud(sete: sete, lovlige: lovlige) }
        visPrivat(sete: sete)
        if let høyeste = engine.høyesteBud {
            print("Høyeste bud: \(navn[høyeste.seat]) – \(høyeste.action.beskrivelse)")
        } else {
            print("Ingen bud ennå.")
        }
        let valg = meny("Ditt bud, \(navn[sete])", lovlige.map(\.beskrivelse))
        return lovlige[valg]
    }

    private mutating func velgVrak(sete: Int) -> [Card] {
        let antall = engine.rules.antallByttekort
        guard oppsett.aktører[sete].erMenneske else { return aiVrak(sete: sete, antall: antall) }
        visPrivat(sete: sete)
        print("Du tok opp talongen og har \(engine.hands[sete].count) kort – vrak \(antall) (forblir skjult).")
        var igjen = engine.hands[sete]
        var vrak: [Card] = []
        while vrak.count < antall {
            let valg = meny("Vrak kort \(vrak.count + 1) av \(antall)", igjen.map(\.kortSymbol))
            vrak.append(igjen.remove(at: valg))
        }
        return vrak
    }

    private mutating func velgTrumf(sete: Int) -> (Suit, Card?) {
        guard oppsett.aktører[sete].erMenneske else { return aiTrumf(sete: sete) }
        visPrivat(sete: sete)
        let farger = Suit.allCases
        let fargeValg = meny("Velg trumf", farger.map { "\($0.rawValue) \($0.navn)" })
        let trumf = farger[fargeValg]
        let kandidater = engine.kortSomKanØnskes(trumf: trumf)
        if engine.erSolo {
            let valg = meny(
                "Etterlys et kort? (valgfritt ved solo)",
                ["Ingen etterlysning"] + kandidater.map(\.kortSymbol)
            )
            return (trumf, valg == 0 ? nil : kandidater[valg - 1])
        }
        guard !kandidater.isEmpty else {
            // Har alle trumfene selv: prøv en annen farge.
            print("Du har alle tilgjengelige \(trumf.navn.lowercased())-kortene – velg en annen trumf.")
            return velgTrumf(sete: sete)
        }
        let valg = meny("Etterlys et kort (den som har det blir makkeren din)", kandidater.map(\.kortSymbol))
        return (trumf, kandidater[valg])
    }

    private mutating func velgKort(sete: Int) -> Card {
        let lovlige = engine.lovligeKort(for: sete)
        guard oppsett.aktører[sete].erMenneske else { return aiKort(sete: sete, lovlige: lovlige) }
        visPrivat(sete: sete)
        if engine.currentTrick.isEmpty {
            print("Du spiller ut.")
        } else {
            let lagt = engine.currentTrick.map { "\(navn[$0.seat]) \($0.card.kortSymbol)" }.joined(separator: "  ")
            print("På bordet: \(lagt)")
        }
        if lovlige.count == 1, lovlige[0] == engine.ønsketKort {
            print("Makkerplikt: du må legge \(lovlige[0].kortSymbol).")
        }
        let valg = meny("Spill kort, \(navn[sete])", lovlige.map(\.kortSymbol))
        return lovlige[valg]
    }

    // MARK: - AI-valg (samme fallback-mønster som Kampsimulator)

    private func aiBud(sete: Int, lovlige: [BidAction]) -> BidAction {
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

    private func aiVrak(sete: Int, antall: Int) -> [Card] {
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

    private func aiTrumf(sete: Int) -> (Suit, Card?) {
        if let mester = mestere[sete], let valg = mester.velgTrumfOgMakker(engine: engine),
           valg.1 == nil || engine.kortSomKanØnskes(trumf: valg.0).contains(valg.1!) {
            return valg
        }
        if let ai = heuristikere[sete], let valg = ai.velgTrumfOgMakker(engine: engine) {
            return valg
        }
        return (.spar, engine.kortSomKanØnskes(trumf: .spar).first)
    }

    private func aiKort(sete: Int, lovlige: [Card]) -> Card {
        if let mester = mestere[sete], let kort = mester.velgKort(engine: engine), lovlige.contains(kort) {
            return kort
        }
        if let ai = heuristikere[sete], let kort = ai.velgKort(engine: engine), lovlige.contains(kort) {
            return kort
        }
        return lovlige[0]
    }

    // MARK: - Skjerm og inndata

    /// Viser setets private oppsummering. Bytter tastaturet menneske,
    /// tømmes skjermen først så forrige spillers hånd ikke står igjen.
    private mutating func visPrivat(sete: Int) {
        if sisteMenneske != sete {
            if sisteMenneske != nil {
                print("")
                print("🔄 Gi tastaturet til \(navn[sete]) – alle andre ser bort. Trykk Enter.")
                _ = readLine()
            }
            print(String(repeating: "\n", count: 3) + "\u{001B}[2J\u{001B}[H", terminator: "")
            sisteMenneske = sete
        }
        print("")
        print("👤 \(navn[sete])  ·  \(poengLinje())")
        if let trumf = engine.trumf {
            var linje = "Trumf: \(trumf.rawValue) \(trumf.navn)"
            if let ønsket = engine.ønsketKort {
                linje += " · etterlyst: \(ønsket.kortSymbol)\(engine.makkerAvslørt ? " (makker: \(navn[engine.makkerSeat ?? -1]))" : "")"
            }
            if engine.erAmerikaner { linje += " · AMERIKANER" }
            if engine.erSolo { linje += " · SOLO" }
            print(linje)
            print("Stikk så langt: " + engine.stikkTatt.enumerated().map { "\(navn[$0.offset]): \($0.element)" }.joined(separator: " · "))
        }
        print("Din hånd: " + håndTekst(engine.hands[sete]))
    }

    private func håndTekst(_ hånd: [Card]) -> String {
        Suit.allCases.compactMap { farge in
            let kort = hånd.filter { $0.suit == farge }.sorted { $0.rank > $1.rank }
            guard !kort.isEmpty else { return nil }
            return "\(farge.rawValue) " + kort.map(\.rank.symbol).joined(separator: " ")
        }.joined(separator: "   ")
    }

    private func poengLinje() -> String {
        engine.scores.enumerated().map { "\(navn[$0.offset]): \($0.element)" }.joined(separator: " · ")
    }

    private func skrivRundeResultat() {
        guard let runde = engine.sisteRunde else { return }
        let lag = runde.makker.map { "laget (\(navn[runde.budgiver]) + \(navn[$0]))" } ?? navn[runde.budgiver]
        let stikk = [runde.budgiver, runde.makker].compactMap { $0 }
            .reduce(0) { $0 + runde.stikkPerSpiller[$1] }
        print("Resultat: \(lag) tok \(stikk) stikk på \(runde.bud.beskrivelse) → \(runde.klarte ? "KLARTE DET ✓" : "røk ✗")")
        print("Poeng:  " + poengLinje())
    }

    /// Nummerert meny; ugyldig svar spør på nytt, EOF avslutter pent.
    private func meny(_ tittel: String, _ valg: [String]) -> Int {
        print(tittel + ":")
        for (i, tekst) in valg.enumerated() { print("  \(i + 1): \(tekst)") }
        while true {
            print("> ", terminator: "")
            guard let linje = readLine() else {
                print("Ingen inndata – avslutter.")
                exit(0)
            }
            if let tall = Int(linje.trimmingCharacters(in: .whitespaces)), (1...valg.count).contains(tall) {
                return tall - 1
            }
            print("Svar med et tall fra 1 til \(valg.count).")
        }
    }
}
