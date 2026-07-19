import XCTest
@testable import Amerikaneren

final class GameEngineTests: XCTestCase {

    /// Standardregler: 12 kort per spiller, 4 byttekort, først til 100.
    private func nyEngine() -> GameEngine { GameEngine() }

    /// Driver budrunden til første aktive byr laveste bud og resten passer,
    /// og vraker deretter fire vilkårlige kort for budvinneren.
    @discardableResult
    private func vinnBudrundeOgVrak(_ engine: GameEngine, bud: Int = 5) -> Int {
        let budgiver = engine.aktivBudgiver
        engine.giBud(seat: budgiver, action: .bud(bud))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        if engine.phase == .byttekort {
            let vrak = Array(engine.hands[budgiver].suffix(engine.rules.antallByttekort))
            XCTAssertTrue(engine.kastByttekort(vrak, seat: budgiver))
        }
        return budgiver
    }

    /// Et ønskekort i gitt trumffarge som garantert sitter hos en motspiller.
    private func levendeØnske(_ engine: GameEngine, trumf: Suit, budgiver: Int) -> Card? {
        engine.kortSomKanØnskes(trumf: trumf).first { kort in
            (0..<4).contains { $0 != budgiver && engine.hands[$0].contains(kort) }
        }
    }

    func testUtdelingGir12KortOgTalong() {
        let engine = nyEngine()
        engine.startRunde(seed: 42)
        XCTAssertEqual(engine.hands.count, 4)
        for hånd in engine.hands { XCTAssertEqual(hånd.count, 12) }
        XCTAssertEqual(engine.talon.count, 4)
        let alleKort = engine.hands.flatMap { $0 } + engine.talon
        XCTAssertEqual(Set(alleKort).count, 52)
    }

    func testKlassiskeReglerUtenByttekort() {
        var regler = GameRules()
        regler.medByttekort = false
        let engine = GameEngine(rules: regler)
        engine.startRunde(seed: 42)
        for hånd in engine.hands { XCTAssertEqual(hånd.count, 13) }
        XCTAssertTrue(engine.talon.isEmpty)
        let budgiver = engine.aktivBudgiver
        engine.giBud(seat: budgiver, action: .bud(5))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        // Uten byttekort går budvinneren rett til trumfvalget.
        XCTAssertEqual(engine.phase, .velgTrumf)
    }

    func testBudrundeMinsteBudOgOverbud() {
        let engine = nyEngine()
        engine.startRunde(seed: 1)
        let første = engine.aktivBudgiver
        let lovlige = engine.lovligeBud(for: første)
        XCTAssertTrue(lovlige.contains(.pass))
        XCTAssertTrue(lovlige.contains(.bud(5)))
        XCTAssertFalse(lovlige.contains(.bud(4)))
        XCTAssertTrue(lovlige.contains(.bud(12)))
        XCTAssertFalse(lovlige.contains(.bud(13)))   // bare 12 stikk med byttekort

        XCTAssertTrue(engine.giBud(seat: første, action: .bud(6)))
        let neste = engine.aktivBudgiver
        XCTAssertFalse(engine.lovligeBud(for: neste).contains(.bud(6)))
        XCTAssertTrue(engine.lovligeBud(for: neste).contains(.bud(7)))
    }

    func testByttekortKreverBudvinnerOgRiktigAntall() {
        let engine = nyEngine()
        engine.startRunde(seed: 12)
        let budgiver = engine.aktivBudgiver
        engine.giBud(seat: budgiver, action: .bud(5))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        XCTAssertEqual(engine.phase, .byttekort)
        // Talongen er tatt opp: budvinneren har 16 kort.
        XCTAssertEqual(engine.hands[budgiver].count, 16)

        let annet = (budgiver + 1) % 4
        XCTAssertFalse(engine.kastByttekort(Array(engine.hands[annet].prefix(4)), seat: annet))
        XCTAssertFalse(engine.kastByttekort(Array(engine.hands[budgiver].prefix(3)), seat: budgiver))
        XCTAssertFalse(engine.kastByttekort([], seat: budgiver))

        let vrak = Array(engine.hands[budgiver].prefix(4))
        XCTAssertTrue(engine.kastByttekort(vrak, seat: budgiver))
        XCTAssertEqual(engine.hands[budgiver].count, 12)
        XCTAssertEqual(engine.kastet, vrak)
        XCTAssertEqual(engine.phase, .velgTrumf)
        // Vrakede kort kan ikke spilles senere.
        for kort in vrak { XCTAssertFalse(engine.hands.flatMap { $0 }.contains(kort)) }
    }

    func testAmerikanerAvslutterBudrundenUtenTrumf() {
        let engine = nyEngine()
        engine.startRunde(seed: 7)
        let første = engine.aktivBudgiver
        XCTAssertTrue(engine.giBud(seat: første, action: .amerikaner))
        // Også Amerikaner-melderen bytter kort først.
        XCTAssertEqual(engine.phase, .byttekort)
        XCTAssertTrue(engine.erAmerikaner)
        let vrak = Array(engine.hands[første].prefix(4))
        XCTAssertTrue(engine.kastByttekort(vrak, seat: første))
        XCTAssertEqual(engine.phase, .spill)
        XCTAssertNil(engine.trumf)
        XCTAssertEqual(engine.aktivSpiller, første)
    }

    func testTrumfvalgFinnerMakker() {
        let engine = nyEngine()
        engine.startRunde(seed: 3)
        let budgiver = vinnBudrundeOgVrak(engine)
        XCTAssertEqual(engine.phase, .velgTrumf)
        guard let ønsket = levendeØnske(engine, trumf: .spar, budgiver: budgiver) else {
            return XCTFail("Fant ikke levende ønskekort")
        }
        XCTAssertTrue(engine.velgTrumf(suit: .spar, ønsket: ønsket))
        XCTAssertNotNil(engine.makkerSeat)
        XCTAssertNotEqual(engine.makkerSeat, budgiver)
        XCTAssertEqual(engine.phase, .spill)
    }

    func testØnsketKortIVrakGirSpillAlene() {
        let engine = nyEngine()
        engine.startRunde(seed: 3)
        let budgiver = vinnBudrundeOgVrak(engine)
        // Be om et vraket kort: ingen makker, budgiveren spiller alene.
        guard let dødt = engine.kastet.first(where: { kort in
            engine.kortSomKanØnskes(trumf: kort.suit).contains(kort)
        }) else { return }   // vraket kan mangle ønskbare kort for enkelte frø
        XCTAssertTrue(engine.velgTrumf(suit: dødt.suit, ønsket: dødt))
        XCTAssertNil(engine.makkerSeat)
        XCTAssertEqual(engine.phase, .spill)
    }

    func testStikkVinnerHøyesteIFargenOgTrumf() {
        let stikk = [
            TrickPlay(seat: 0, card: Card(suit: .kløver, rank: .king)),
            TrickPlay(seat: 1, card: Card(suit: .kløver, rank: .ace)),
            TrickPlay(seat: 2, card: Card(suit: .hjerter, rank: .two)),
            TrickPlay(seat: 3, card: Card(suit: .ruter, rank: .ace)),
        ]
        // Med hjerter som trumf vinner hjerter 2.
        XCTAssertEqual(GameEngine.vinnerAvStikk(stikk, trumf: .hjerter), 2)
        // Uten trumf vinner kløver ess.
        XCTAssertEqual(GameEngine.vinnerAvStikk(stikk, trumf: nil), 1)
        // Med annen trumf (ingen trumf lagt) vinner fortsatt kløver ess.
        XCTAssertEqual(GameEngine.vinnerAvStikk(stikk, trumf: .spar), 1)
    }

    func testFullRundeGirPoeng() {
        let engine = nyEngine()
        engine.startRunde(seed: 99)
        let budgiver = vinnBudrundeOgVrak(engine)
        guard let ønsket = levendeØnske(engine, trumf: .hjerter, budgiver: budgiver) else {
            return XCTFail("Fant ikke levende ønskekort")
        }
        engine.velgTrumf(suit: .hjerter, ønsket: ønsket)

        // Spill runden ferdig med første lovlige kort hver gang.
        var vakt = 0
        while engine.phase == .spill, vakt < 200 {
            let seat = engine.aktivSpiller
            guard let kort = engine.lovligeKort(for: seat).first else { break }
            engine.spill(kort: kort, seat: seat)
            vakt += 1
        }
        XCTAssertTrue(engine.phase == .rundeFerdig || engine.phase == .spillFerdig)
        XCTAssertEqual(engine.stikkTatt.reduce(0, +), engine.rules.kortPerSpiller)
        let resultat = engine.sisteRunde
        XCTAssertNotNil(resultat)
        // Poengendring skal stemme med regelverket.
        if let resultat {
            let lag = [resultat.budgiver, resultat.makker].compactMap { $0 }
            let lagStikk = lag.reduce(0) { $0 + resultat.stikkPerSpiller[$1] }
            XCTAssertEqual(resultat.klarte, lagStikk >= 5)
            for s in 0..<4 where !lag.contains(s) {
                XCTAssertEqual(resultat.poengEndring[s], resultat.stikkPerSpiller[s])
            }
            for s in lag {
                XCTAssertEqual(resultat.poengEndring[s], resultat.klarte ? 5 : -5)
            }
        }
    }

    func testMakkerMåLeggeØnsketKortIFørsteStikk() {
        let engine = nyEngine()
        engine.startRunde(seed: 5)
        let budgiver = vinnBudrundeOgVrak(engine)
        guard let ønsket = levendeØnske(engine, trumf: .spar, budgiver: budgiver) else {
            return XCTFail("Fant ikke levende ønskekort")
        }
        engine.velgTrumf(suit: .spar, ønsket: ønsket)
        guard let makker = engine.makkerSeat else { return XCTFail("Ingen makker") }

        // Budgiver spiller ut trumf; når det blir makkerens tur og ønsket
        // kort er lovlig, skal det være eneste lovlige kort.
        let utspill = engine.hands[budgiver].first { $0.suit == .spar } ?? engine.hands[budgiver][0]
        engine.spill(kort: utspill, seat: budgiver)
        while engine.aktivSpiller != makker, !engine.currentTrick.isEmpty {
            let seat = engine.aktivSpiller
            engine.spill(kort: engine.lovligeKort(for: seat).first!, seat: seat)
        }
        if engine.currentTrick.isEmpty { return } // stikket ble ferdig uten makker (usannsynlig)
        let lovlige = engine.lovligeKort(for: makker)
        if utspill.suit == ønsket.suit {
            XCTAssertEqual(lovlige, [ønsket])
        }
    }

    func testFørstTilMålPoengVinnerSpillet() {
        let engine = nyEngine()
        var vakt = 0
        engine.startRunde(seed: 11)
        while engine.phase != .spillFerdig, vakt < 20000 {
            vakt += 1
            switch engine.phase {
            case .budrunde:
                let seat = engine.aktivBudgiver
                let lovlige = engine.lovligeBud(for: seat)
                // Første aktive byr lavest mulig tallbud, resten passer.
                if engine.høyesteBud == nil, case .bud(let n)? = lovlige.dropFirst().first {
                    engine.giBud(seat: seat, action: .bud(n))
                } else {
                    engine.giBud(seat: seat, action: .pass)
                }
            case .byttekort:
                let seat = engine.budgiverSeat!
                engine.kastByttekort(Array(engine.hands[seat].prefix(4)), seat: seat)
            case .velgTrumf:
                let ønsket = engine.kortSomKanØnskes(trumf: .hjerter)[0]
                engine.velgTrumf(suit: .hjerter, ønsket: ønsket)
            case .spill:
                let seat = engine.aktivSpiller
                engine.spill(kort: engine.lovligeKort(for: seat).first!, seat: seat)
            case .rundeFerdig:
                engine.nesteRunde()
            default:
                break
            }
        }
        XCTAssertEqual(engine.phase, .spillFerdig)
        XCTAssertNotNil(engine.vinnerSeat)
        XCTAssertGreaterThanOrEqual(engine.scores.max() ?? 0, engine.rules.målPoeng)
        XCTAssertEqual(engine.rules.målPoeng, 100)
    }

    func testAIByrLovlig() {
        let engine = nyEngine()
        engine.startRunde(seed: 21)
        let ai = AIPlayer(seat: engine.aktivBudgiver, difficulty: .vanskelig, personality: .balansert)
        let bud = ai.velgBud(engine: engine)
        XCTAssertTrue(engine.lovligeBud(for: engine.aktivBudgiver).contains(bud))
    }

    func testAIVrakerLovlig() {
        let engine = nyEngine()
        engine.startRunde(seed: 27)
        let budgiver = engine.aktivBudgiver
        engine.giBud(seat: budgiver, action: .bud(5))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        XCTAssertEqual(engine.phase, .byttekort)
        let ai = AIPlayer(seat: budgiver, difficulty: .vanskelig, personality: .balansert)
        let vrak = ai.velgByttekort(engine: engine)
        XCTAssertEqual(vrak.count, 4)
        XCTAssertTrue(engine.kastByttekort(vrak, seat: budgiver))
    }

    func testAISpillerLovligKort() {
        let engine = nyEngine()
        engine.startRunde(seed: 33)
        let budgiver = engine.aktivBudgiver
        engine.giBud(seat: budgiver, action: .bud(5))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        let vraker = AIPlayer(seat: budgiver, difficulty: .president, personality: .balansert)
        XCTAssertTrue(engine.kastByttekort(vraker.velgByttekort(engine: engine), seat: budgiver))
        guard let ønsket = levendeØnske(engine, trumf: .kløver, budgiver: budgiver) else {
            return XCTFail("Fant ikke levende ønskekort")
        }
        engine.velgTrumf(suit: .kløver, ønsket: ønsket)
        var vakt = 0
        while engine.phase == .spill, vakt < 60 {
            let seat = engine.aktivSpiller
            let ai = AIPlayer(seat: seat, difficulty: .president, personality: .balansert)
            guard let kort = ai.velgKort(engine: engine) else { return XCTFail("AI fant ikke kort") }
            XCTAssertTrue(engine.lovligeKort(for: seat).contains(kort))
            engine.spill(kort: kort, seat: seat)
            vakt += 1
        }
    }
}
