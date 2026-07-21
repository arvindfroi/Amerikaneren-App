import Foundation

/// Eksporterer komplette runder som JSONL for paritetsvalidering mot
/// OpenSpiel-porten av Amerikaneren. Hver linje er én runde spilt med
/// tilfeldige LOVLIGE trekk (seedet), med alle beslutningspunkter og
/// tilhørende lovlige handlinger, slik at en replay i OpenSpiel kan
/// verifisere at regelimplementasjonene er identiske.
///
/// Handlings-ID-mapping (må speiles nøyaktig i OpenSpiel-porten):
///   0..51   kort: id = fargeIndeks*13 + (rang-2),
///           fargeIndeks etter Suit.allCases: spar=0, hjerter=1, ruter=2, kløver=3.
///           Brukes både for å spille kort og for å vrake kort.
///   52      pass
///   53..60  tallbud 5..12 (id = 48 + bud)
///   61      amerikaner
///   62      solo-amerikaner
///   63..114 velg trumf og etterlys kort: id = 63 + kortId(ønsket).
///           Trumffargen er gitt av ønskekortets farge.
///   115..118 solo-amerikaner: velg trumf UTEN etterlysning, id = 115 + fargeIndeks.
///
/// Vrak er ÉN atomisk beslutning i Swift-motoren (4 kort på én gang), men
/// modelleres som 4 sekvensielle enkeltkort-valg i OpenSpiel. Eksporten
/// skriver derfor hele hånden (16 kort) ved vrakpunktet pluss de 4 valgte
/// kortene i rekkefølge; replayen verifiserer at lovlige handlinger ved
/// hvert delsteg er hånden minus allerede vrakede kort.
enum EksporterRunder {

    static func kortId(_ c: Card) -> Int {
        let s = Suit.allCases.firstIndex(of: c.suit)!
        return s * 13 + (c.rank.rawValue - 2)
    }

    static func budId(_ b: BidAction) -> Int {
        switch b {
        case .pass: return 52
        case .bud(let n): return 48 + n
        case .amerikaner: return 61
        case .soloAmerikaner: return 62
        }
    }

    static func budFraId(_ id: Int) -> BidAction {
        switch id {
        case 52: return .pass
        case 53...60: return .bud(id - 48)
        case 61: return .amerikaner
        default: return .soloAmerikaner
        }
    }

    private static func liste(_ xs: [Int]) -> String {
        "[" + xs.map(String.init).joined(separator: ",") + "]"
    }

    private static func utdelingJSON(_ engine: GameEngine) -> String {
        let hender = engine.utdelteHender.map { h in liste(h.map(kortId)) }
        return "{\"hender\":[\(hender.joined(separator: ","))]," +
               "\"talon\":\(liste(engine.utdeltTalon.map(kortId)))," +
               "\"foersteBudgiver\":\(engine.førsteBudgiverIRunden)}"
    }

    /// Spiller én komplett runde med tilfeldige lovlige trekk og returnerer
    /// JSON-linjen, eller nil ved intern feil (skal aldri skje).
    static func spillRunde(rundeNr: Int, utdelingsfrø: UInt64, rng: inout SeededGenerator) -> String? {
        let engine = GameEngine()
        engine.startRunde(seed: utdelingsfrø)

        var utdelinger = [utdelingJSON(engine)]
        var hendelser: [String] = []
        var vakt = 0

        while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
            vakt += 1
            if vakt > 2000 { FileHandle.standardError.write("FEIL: runde \(rundeNr) henger\n".data(using: .utf8)!); return nil }

            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                let lovlige = engine.lovligeBud(for: sete).map(budId).sorted()
                // Vekt mot pass slik at budrunden ender i rimelig tid, men
                // alle handlinger (også amerikaner/solo) prøves jevnlig.
                let valg: Int
                if Int.random(in: 0..<100, using: &rng) < 55 || lovlige.count == 1 {
                    valg = 52
                } else {
                    valg = lovlige.filter { $0 != 52 }.randomElement(using: &rng)!
                }
                let antallBudFør = engine.bids.count
                guard engine.giBud(seat: sete, action: budFraId(valg)) else { return nil }
                hendelser.append("{\"t\":\"bud\",\"s\":\(sete),\"lov\":\(liste(lovlige)),\"v\":\(valg)}")
                // Alle passet → motoren har delt ut på nytt (bids nullstilt).
                if engine.phase == .budrunde && engine.bids.isEmpty && antallBudFør > 0 {
                    hendelser.append("{\"t\":\"omdeling\"}")
                    utdelinger.append(utdelingJSON(engine))
                }

            case .byttekort:
                let sete = engine.budgiverSeat!
                let hånd = engine.hands[sete].map(kortId).sorted()
                let vrak = Array(engine.hands[sete].shuffled(using: &rng).prefix(engine.rules.antallByttekort))
                guard engine.kastByttekort(vrak, seat: sete) else { return nil }
                hendelser.append("{\"t\":\"vrak\",\"s\":\(sete),\"haand\":\(liste(hånd)),\"v\":\(liste(vrak.map(kortId)))}")

            case .velgTrumf:
                let sete = engine.budgiverSeat!
                var lovlige: [Int] = []
                for suit in Suit.allCases {
                    lovlige += engine.kortSomKanØnskes(trumf: suit).map { 63 + kortId($0) }
                }
                if engine.erSolo {
                    lovlige += (0..<4).map { 115 + $0 }
                }
                lovlige.sort()
                let valg = lovlige.randomElement(using: &rng)!
                if valg >= 115 {
                    guard engine.velgTrumf(suit: Suit.allCases[valg - 115], ønsket: nil) else { return nil }
                } else {
                    let kid = valg - 63
                    let kort = Card(suit: Suit.allCases[kid / 13], rank: Rank(rawValue: kid % 13 + 2)!)
                    guard engine.velgTrumf(suit: kort.suit, ønsket: kort) else { return nil }
                }
                hendelser.append("{\"t\":\"trumf\",\"s\":\(sete),\"lov\":\(liste(lovlige)),\"v\":\(valg)}")

            case .spill:
                let sete = engine.aktivSpiller
                let lovlige = engine.lovligeKort(for: sete).map(kortId).sorted()
                let valg = lovlige.randomElement(using: &rng)!
                let kort = Card(suit: Suit.allCases[valg / 13], rank: Rank(rawValue: valg % 13 + 2)!)
                guard engine.spill(kort: kort, seat: sete) else { return nil }
                hendelser.append("{\"t\":\"spill\",\"s\":\(sete),\"lov\":\(liste(lovlige)),\"v\":\(valg)}")

            default:
                return nil
            }
        }

        guard let resultat = engine.sisteRunde else { return nil }
        let makker = resultat.makker.map(String.init) ?? "null"
        return "{\"runde\":\(rundeNr)," +
               "\"utdelinger\":[\(utdelinger.joined(separator: ","))]," +
               "\"hendelser\":[\(hendelser.joined(separator: ","))]," +
               "\"poeng\":\(liste(resultat.poengEndring))," +
               "\"stikk\":\(liste(resultat.stikkPerSpiller))," +
               "\"budgiver\":\(resultat.budgiver)," +
               "\"makker\":\(makker)," +
               "\"budRang\":\(resultat.bud.rang)," +
               "\"klarte\":\(resultat.klarte)}"
    }

    static func kjør(argv: [String]) {
        let antall = argv.count > 1 ? Int(argv[1]) ?? 100 : 100
        let frø = argv.count > 2 ? UInt64(argv[2]) ?? 1 : 1
        var rng = SeededGenerator(seed: frø)
        var skrevet = 0
        for i in 0..<antall {
            let utdelingsfrø = frø &+ UInt64(i) &* 0x9E3779B97F4A7C15
            if let linje = spillRunde(rundeNr: i, utdelingsfrø: utdelingsfrø == 0 ? 1 : utdelingsfrø, rng: &rng) {
                print(linje)
                skrevet += 1
            }
            if (i + 1) % 500 == 0 {
                FileHandle.standardError.write("… \(i + 1)/\(antall) runder\n".data(using: .utf8)!)
            }
        }
        FileHandle.standardError.write("Ferdig: \(skrevet)/\(antall) runder eksportert.\n".data(using: .utf8)!)
    }
}
