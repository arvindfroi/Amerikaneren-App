import XCTest
@testable import Amerikaneren

/// Tester for informasjonssett-søket (SO-ISMCTS).
final class MesterISMCTSTests: XCTestCase {

    private func lite(iterasjoner: Int = 300) -> ISMCTSKonfig {
        var k = ISMCTSKonfig()
        k.tidsbudsjett = 0            // ingen klokke – iterasjonstaket styrer
        k.maksIterasjoner = iterasjoner
        return k
    }

    /// Kjører en runde fram til stikkspillet uten å bruke søket: FØRSTE
    /// budgiver melder laveste tallbud, resten passer. (Lar alle passe, og
    /// motoren deler ut på nytt – da blir en naiv budløkke uendelig.)
    @discardableResult
    private func framTilSpill(_ engine: GameEngine) -> Bool {
        var vakt = 0
        while engine.phase == .budrunde, vakt < 40 {
            vakt += 1
            let s = engine.aktivBudgiver
            let lovlige = engine.lovligeBud(for: s)
            let tallbud = lovlige.first { if case .bud = $0 { return true }; return false }
            let handling: BidAction = (engine.høyesteBud == nil && tallbud != nil) ? tallbud! : .pass
            guard engine.giBud(seat: s, action: handling) else { return false }
        }
        if engine.phase == .byttekort {
            guard let s = engine.budgiverSeat else { return false }
            let vrak = Array(engine.hands[s].prefix(engine.rules.antallByttekort))
            guard engine.kastByttekort(vrak, seat: s) else { return false }
        }
        if engine.phase == .velgTrumf {
            for suit in Suit.allCases {
                if let ø = engine.kortSomKanØnskes(trumf: suit).first,
                   engine.velgTrumf(suit: suit, ønsket: ø) { break }
            }
        }
        return engine.phase == .spill
    }

    /// Som `framTilSpill`, men spiller videre til et sete faktisk har et
    /// VALG. Er det bare ett lovlig kort, går `velgKort` rett ut uten søk.
    private func framTilValg(_ engine: GameEngine) -> Bool {
        guard framTilSpill(engine) else { return false }
        var vakt = 0
        while engine.phase == .spill, vakt < 48 {
            let s = engine.aktivSpiller
            let lovlige = engine.lovligeKort(for: s)
            if lovlige.count > 1 { return true }
            guard let kort = lovlige.first, engine.spill(kort: kort, seat: s) else { return false }
            vakt += 1
        }
        return false
    }

    /// Spiller hele runder med ISMCTS i alle fire seter og krever at hvert
    /// eneste kort er blant motorens egne `lovligeKort`.
    func testSpillerBareLovligeTrekk() {
        var runder = 0
        for r in 1...12 {
            let seed = UInt64(r) &* 7919 &+ 101
            let engine = GameEngine()
            engine.startRunde(seed: seed)
            let mestere = (0..<4).map { MesterAI(sete: $0, seed: seed &+ UInt64($0)) }
            let søk = (0..<4).map {
                MesterISMCTS(sete: $0, konfig: lite(), seed: seed &+ UInt64($0) &* 31)
            }
            var vakt = 0
            while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
                vakt += 1
                XCTAssertLessThan(vakt, 400, "Runden henger")
                if vakt >= 400 { break }
                switch engine.phase {
                case .budrunde:
                    let s = engine.aktivBudgiver
                    let bud = mestere[s].velgBud(engine: engine)
                    let lovlige = engine.lovligeBud(for: s)
                    XCTAssertTrue(engine.giBud(seat: s, action: lovlige.contains(bud) ? bud : .pass))
                case .byttekort:
                    let s = engine.budgiverSeat!
                    var vrak = mestere[s].velgByttekort(engine: engine)
                    if vrak.count != engine.rules.antallByttekort {
                        vrak = Array(engine.hands[s].prefix(engine.rules.antallByttekort))
                    }
                    XCTAssertTrue(engine.kastByttekort(vrak, seat: s))
                case .velgTrumf:
                    let s = engine.budgiverSeat!
                    if let (suit, ønsket) = mestere[s].velgTrumfOgMakker(engine: engine) {
                        XCTAssertTrue(engine.velgTrumf(suit: suit, ønsket: ønsket))
                    } else {
                        XCTAssertTrue(engine.velgTrumf(suit: .spar, ønsket: nil))
                    }
                case .spill:
                    let s = engine.aktivSpiller
                    let lovlige = engine.lovligeKort(for: s)
                    guard let kort = søk[s].velgKort(engine: engine) else {
                        return XCTFail("ISMCTS ga ingen kort")
                    }
                    XCTAssertTrue(lovlige.contains(kort),
                                  "Ulovlig kort \(kort.kortSymbol) fra sete \(s)")
                    XCTAssertTrue(engine.spill(kort: kort, seat: s))
                default:
                    return XCTFail("Uventet fase")
                }
            }
            runder += 1
        }
        XCTAssertEqual(runder, 12)
    }

    /// Samme frø gir samme trekk – en forutsetning for parrede A/B-målinger.
    func testReproduserbartMedSammeFrø() {
        let engine = GameEngine()
        engine.startRunde(seed: 4242)
        guard framTilValg(engine) else { return XCTFail("Kom ikke til stikkspillet") }
        let sete = engine.aktivSpiller
        let a = MesterISMCTS(sete: sete, konfig: lite(iterasjoner: 800), seed: 9)
        let b = MesterISMCTS(sete: sete, konfig: lite(iterasjoner: 800), seed: 9)
        XCTAssertEqual(a.velgKort(engine: engine), b.velgKort(engine: engine))
        XCTAssertEqual(a.sisteIterasjoner, 800)
    }

    /// Tilgjengelighetstellingen er kjernen i ISMCTS: for hver rotkandidat
    /// skal besøkene summere seg til antall iterasjoner, siden alle
    /// rotkandidatene er lovlige i enhver determinisering.
    func testRotbesøkSummererTilIterasjoner() {
        let engine = GameEngine()
        engine.startRunde(seed: 777)
        guard framTilValg(engine) else { return XCTFail("Kom ikke til stikkspillet") }
        let søk = MesterISMCTS(sete: engine.aktivSpiller, konfig: lite(iterasjoner: 1500), seed: 5)
        _ = søk.velgKort(engine: engine)
        let sum = søk.sisteRotfordeling.reduce(0) { $0 + $1.besøk }
        XCTAssertEqual(sum, søk.sisteIterasjoner)
        XCTAssertGreaterThan(søk.sisteRotfordeling.count, 1)
    }

    /// Målfunksjonen er delt med `MesterAI.vurder`. Her sjekkes at den gir
    /// budgiveren pluss når kontrakten holder og minus når den ryker, og at
    /// forsvarerne får sine egne stikk som poeng.
    func testMåltallFølgerPoengsatsene() {
        let engine = GameEngine()
        engine.startRunde(seed: 2024)
        guard framTilSpill(engine),
              let innsikt = Spillinnsikt(engine: engine, sete: engine.aktivSpiller),
              case .bud(let mål) = innsikt.bud else {
            return XCTFail("Fikk ikke en tallbud-runde")
        }
        let lag: UInt8 = 1 << UInt8(innsikt.budgiver)
        // Kontrakten går akkurat inn.
        var perSete = [0, 0, 0, 0]
        perSete[innsikt.budgiver] = mål
        let inn = innsikt.måltall(lagMaske: lag, perSete: perSete, restLagStikk: 0)
        // Kontrakten ryker fullstendig.
        var tapt = [0, 0, 0, 0]
        tapt[(innsikt.budgiver + 1) % 4] = innsikt.stikkTotalt
        let ut = innsikt.måltall(lagMaske: lag, perSete: tapt, restLagStikk: 0)
        XCTAssertGreaterThan(inn[innsikt.budgiver], ut[innsikt.budgiver],
                             "Budgiveren må foretrekke å berge kontrakten")
        let forsvarer = (innsikt.budgiver + 1) % 4
        XCTAssertGreaterThan(ut[forsvarer], inn[forsvarer],
                             "Forsvareren må foretrekke å velte kontrakten")
    }
}
