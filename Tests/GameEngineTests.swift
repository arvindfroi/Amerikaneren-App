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

    func testAmerikanerKanOverbysAvSoloOgHarTrumfOgMakker() {
        let engine = nyEngine()
        engine.startRunde(seed: 7)
        let første = engine.aktivBudgiver
        XCTAssertTrue(engine.giBud(seat: første, action: .amerikaner))
        // Amerikaner slår tallbud, men kan fortsatt overbys av solo.
        XCTAssertEqual(engine.phase, .budrunde)
        let neste = engine.aktivBudgiver
        XCTAssertFalse(engine.lovligeBud(for: neste).contains(.bud(12)))
        XCTAssertTrue(engine.lovligeBud(for: neste).contains(.soloAmerikaner))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        // Også Amerikaner-melderen bytter kort – og velger så trumf og makker.
        XCTAssertEqual(engine.phase, .byttekort)
        XCTAssertTrue(engine.erAmerikaner)
        let vrak = Array(engine.hands[første].prefix(4))
        XCTAssertTrue(engine.kastByttekort(vrak, seat: første))
        XCTAssertEqual(engine.phase, .velgTrumf)
        // Amerikaner krever etterlysning (makker) – nil avvises.
        XCTAssertFalse(engine.velgTrumf(suit: .spar, ønsket: nil))
        guard let ønsket = engine.kortSomKanØnskes(trumf: .spar).first else {
            return XCTFail("Ingen ønskbare kort")
        }
        XCTAssertTrue(engine.velgTrumf(suit: .spar, ønsket: ønsket))
        XCTAssertNotNil(engine.trumf)
        XCTAssertNotNil(engine.makkerSeat)
        XCTAssertEqual(engine.aktivSpiller, første)
        XCTAssertEqual(engine.phase, .spill)
    }

    func testSoloAmerikanerSpillerAleneMedTrumf() {
        let engine = nyEngine()
        engine.startRunde(seed: 19)
        let første = engine.aktivBudgiver
        XCTAssertTrue(engine.giBud(seat: første, action: .soloAmerikaner))
        // Solo kan ikke overbys – budrunden er over med en gang.
        XCTAssertEqual(engine.phase, .byttekort)
        XCTAssertTrue(engine.erSolo)
        let vrak = Array(engine.hands[første].prefix(4))
        XCTAssertTrue(engine.kastByttekort(vrak, seat: første))
        // Etterlysning er valgfri ved solo.
        XCTAssertTrue(engine.velgTrumf(suit: .hjerter, ønsket: nil))
        XCTAssertEqual(engine.trumf, .hjerter)
        XCTAssertNil(engine.makkerSeat)
        XCTAssertEqual(engine.phase, .spill)

        // Spill runden ut: solisten tar neppe alt, og skal da tape målPoeng.
        var vakt = 0
        while engine.phase == .spill, vakt < 200 {
            let seat = engine.aktivSpiller
            engine.spill(kort: engine.lovligeKort(for: seat).first!, seat: seat)
            vakt += 1
        }
        guard let runde = engine.sisteRunde else { return XCTFail("Ingen runde") }
        let klarte = runde.stikkPerSpiller[første] == engine.rules.kortPerSpiller
        XCTAssertEqual(runde.klarte, klarte)
        XCTAssertEqual(runde.poengEndring[første],
                       klarte ? engine.rules.målPoeng : -engine.rules.målPoeng)
        for s in 0..<4 where s != første {
            XCTAssertEqual(runde.poengEndring[s], runde.stikkPerSpiller[s])
        }
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

    func testVraketKortKanIkkeØnskes() {
        let engine = nyEngine()
        engine.startRunde(seed: 3)
        _ = vinnBudrundeOgVrak(engine)
        // Det er forbudt å etterlyse et vraket kort – de er verken med i
        // ønskelisten eller godtas av motoren.
        for kort in engine.kastet {
            XCTAssertFalse(engine.kortSomKanØnskes(trumf: kort.suit).contains(kort))
            XCTAssertFalse(engine.velgTrumf(suit: kort.suit, ønsket: kort))
        }
        XCTAssertEqual(engine.phase, .velgTrumf)
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
            // Budvinneren vinner/taper det dobbelte av budet, makkeren budet.
            for s in lag {
                let sats = s == resultat.budgiver ? 10 : 5
                XCTAssertEqual(resultat.poengEndring[s], resultat.klarte ? sats : -sats)
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
                for suit in Suit.allCases {
                    if let ønsket = engine.kortSomKanØnskes(trumf: suit).first,
                       engine.velgTrumf(suit: suit, ønsket: ønsket) { break }
                }
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

    /// Egenskapsbasert motortest: spill mange runder med tilfeldige LOVLIGE
    /// handlinger og verifiser poengreglene uavhengig av motorens egen
    /// utregning – budvinner 2×, makker 1×, Amerikaner ±mål/2 og ±mål/4,
    /// solo ±mål, øvrige +1 per stikk.
    func testMotorInvarianterUnderTilfeldigSpill() {
        var rng = SeededGenerator(seed: 424242)
        for runde in 0..<300 {
            var regler = GameRules()
            regler.medByttekort = runde % 5 != 4   // også klassiske regler
            let engine = GameEngine(rules: regler)
            engine.startRunde(seed: UInt64(runde) &* 7919 &+ 3)

            var vakt = 0
            løkke: while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
                vakt += 1
                if vakt > 600 { return XCTFail("Runde \(runde) henger") }
                switch engine.phase {
                case .budrunde:
                    let sete = engine.aktivBudgiver
                    let lovlige = engine.lovligeBud(for: sete)
                    let valg = Int.random(in: 0..<100, using: &rng) < 55 || lovlige.count == 1
                        ? BidAction.pass
                        : lovlige.filter { $0 != .pass }.randomElement(using: &rng)!
                    XCTAssertTrue(engine.giBud(seat: sete, action: valg))
                case .byttekort:
                    let sete = engine.budgiverSeat!
                    let vrak = Array(engine.hands[sete].shuffled(using: &rng).prefix(regler.antallByttekort))
                    XCTAssertTrue(engine.kastByttekort(vrak, seat: sete))
                case .velgTrumf:
                    let sete = engine.budgiverSeat!
                    // Egne og vrakede kort kan aldri ønskes.
                    for kort in engine.hands[sete] + engine.kastet {
                        XCTAssertFalse(engine.kortSomKanØnskes(trumf: kort.suit).contains(kort))
                    }
                    if engine.erSolo, Bool.random(using: &rng) {
                        XCTAssertTrue(engine.velgTrumf(suit: .spar, ønsket: nil))
                    } else {
                        var valgt = false
                        for suit in Suit.allCases.shuffled(using: &rng) {
                            if let ø = engine.kortSomKanØnskes(trumf: suit).randomElement(using: &rng),
                               engine.velgTrumf(suit: suit, ønsket: ø) { valgt = true; break }
                        }
                        if !valgt { XCTAssertTrue(engine.velgTrumf(suit: .spar, ønsket: nil)) }
                    }
                    if engine.erSolo { XCTAssertNil(engine.makkerSeat) }
                case .spill:
                    let sete = engine.aktivSpiller
                    let lovlige = engine.lovligeKort(for: sete)
                    guard let kort = lovlige.randomElement(using: &rng) else {
                        return XCTFail("Ingen lovlige kort")
                    }
                    // Følg farge-regelen re-verifisert.
                    if let ledet = engine.currentTrick.first?.card.suit,
                       engine.hands[sete].contains(where: { $0.suit == ledet }) {
                        XCTAssertTrue(lovlige.allSatisfy { $0.suit == ledet })
                    }
                    XCTAssertTrue(engine.spill(kort: kort, seat: sete))
                default:
                    break løkke
                }
            }

            guard let resultat = engine.sisteRunde else { return XCTFail("Mangler resultat") }
            XCTAssertEqual(resultat.stikkPerSpiller.reduce(0, +), regler.kortPerSpiller)
            XCTAssertTrue(engine.hands.allSatisfy(\.isEmpty))

            let lag = [resultat.budgiver, resultat.makker].compactMap { $0 }
            let lagStikk = lag.reduce(0) { $0 + resultat.stikkPerSpiller[$1] }
            let klarte: Bool
            let budgiverPoeng: Int
            let makkerPoeng: Int
            switch resultat.bud {
            case .soloAmerikaner:
                klarte = resultat.stikkPerSpiller[resultat.budgiver] == regler.kortPerSpiller
                budgiverPoeng = regler.målPoeng; makkerPoeng = 0
                XCTAssertNil(resultat.makker)
            case .amerikaner:
                klarte = lagStikk == regler.kortPerSpiller
                budgiverPoeng = regler.målPoeng / 2; makkerPoeng = regler.målPoeng / 4
            case .bud(let n):
                klarte = lagStikk >= n
                budgiverPoeng = 2 * n; makkerPoeng = n
            case .pass:
                return XCTFail("Runde uten vinnerbud")
            }
            XCTAssertEqual(resultat.klarte, klarte)
            for s in 0..<4 {
                let forventet = s == resultat.budgiver ? (klarte ? budgiverPoeng : -budgiverPoeng)
                    : lag.contains(s) ? (klarte ? makkerPoeng : -makkerPoeng)
                    : resultat.stikkPerSpiller[s]
                XCTAssertEqual(resultat.poengEndring[s], forventet, "Sete \(s) i runde \(runde)")
            }
            if engine.phase == .spillFerdig, let vinner = engine.vinnerSeat {
                XCTAssertGreaterThanOrEqual(engine.scores[vinner], regler.målPoeng)
            }
        }
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
