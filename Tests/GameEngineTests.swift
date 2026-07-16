import XCTest
@testable import Amerikaneren

final class GameEngineTests: XCTestCase {

    func testUtdelingGirAlle13Kort() {
        let engine = GameEngine()
        engine.startRunde(seed: 42)
        XCTAssertEqual(engine.hands.count, 4)
        for hånd in engine.hands { XCTAssertEqual(hånd.count, 13) }
        let alleKort = engine.hands.flatMap { $0 }
        XCTAssertEqual(Set(alleKort).count, 52)
    }

    func testBudrundeMinsteBudOgOverbud() {
        let engine = GameEngine()
        engine.startRunde(seed: 1)
        let første = engine.aktivBudgiver
        let lovlige = engine.lovligeBud(for: første)
        XCTAssertTrue(lovlige.contains(.pass))
        XCTAssertTrue(lovlige.contains(.bud(5)))
        XCTAssertFalse(lovlige.contains(.bud(4)))

        XCTAssertTrue(engine.giBud(seat: første, action: .bud(6)))
        let neste = engine.aktivBudgiver
        XCTAssertFalse(engine.lovligeBud(for: neste).contains(.bud(6)))
        XCTAssertTrue(engine.lovligeBud(for: neste).contains(.bud(7)))
    }

    func testAmerikanerAvslutterBudrundenUtenTrumf() {
        let engine = GameEngine()
        engine.startRunde(seed: 7)
        let første = engine.aktivBudgiver
        XCTAssertTrue(engine.giBud(seat: første, action: .amerikaner))
        XCTAssertEqual(engine.phase, .spill)
        XCTAssertTrue(engine.erAmerikaner)
        XCTAssertNil(engine.trumf)
        XCTAssertEqual(engine.aktivSpiller, første)
    }

    func testTrumfvalgFinnerMakker() {
        let engine = GameEngine()
        engine.startRunde(seed: 3)
        // La første by 5 og resten passe.
        let budgiver = engine.aktivBudgiver
        engine.giBud(seat: budgiver, action: .bud(5))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        XCTAssertEqual(engine.phase, .velgTrumf)
        let ønskbare = engine.kortSomKanØnskes(trumf: .spar)
        XCTAssertFalse(ønskbare.isEmpty)
        let ønsket = ønskbare[0]
        XCTAssertTrue(engine.velgTrumf(suit: .spar, ønsket: ønsket))
        XCTAssertNotNil(engine.makkerSeat)
        XCTAssertNotEqual(engine.makkerSeat, budgiver)
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
        let engine = GameEngine()
        engine.startRunde(seed: 99)
        let budgiver = engine.aktivBudgiver
        engine.giBud(seat: budgiver, action: .bud(5))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        let ønsket = engine.kortSomKanØnskes(trumf: .hjerter)[0]
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
        XCTAssertEqual(engine.stikkTatt.reduce(0, +), 13)
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
        let engine = GameEngine()
        engine.startRunde(seed: 5)
        let budgiver = engine.aktivBudgiver
        engine.giBud(seat: budgiver, action: .bud(5))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        let ønsket = engine.kortSomKanØnskes(trumf: .spar)[0]
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

    func testFørstTil52VinnerSpillet() {
        let engine = GameEngine()
        var vakt = 0
        engine.startRunde(seed: 11)
        while engine.phase != .spillFerdig, vakt < 5000 {
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
        XCTAssertGreaterThanOrEqual(engine.scores.max() ?? 0, 52)
    }

    func testAIByrLovlig() {
        let engine = GameEngine()
        engine.startRunde(seed: 21)
        let ai = AIPlayer(seat: engine.aktivBudgiver, difficulty: .vanskelig, personality: .balansert)
        let bud = ai.velgBud(engine: engine)
        XCTAssertTrue(engine.lovligeBud(for: engine.aktivBudgiver).contains(bud))
    }

    func testAISpillerLovligKort() {
        let engine = GameEngine()
        engine.startRunde(seed: 33)
        engine.giBud(seat: engine.aktivBudgiver, action: .bud(5))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        let ønsket = engine.kortSomKanØnskes(trumf: .kløver)[0]
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
