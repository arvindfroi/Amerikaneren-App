import XCTest
@testable import Amerikaneren

final class MesterAITests: XCTestCase {

    /// Liten konfigurasjon så testene går raskt, med fast frø for
    /// deterministiske resultater.
    private func raskMester(sete: Int, seed: UInt64) -> MesterAI {
        var konfig = MesterKonfig()
        konfig.maksVerdener = 10
        konfig.minVerdener = 4
        konfig.verdenerVedBud = 16
        konfig.tidsbudsjett = 0.2
        return MesterAI(sete: sete, konfig: konfig, seed: seed)
    }

    // MARK: - Dobbeltdummy

    /// Naiv minimax uten transposisjonstabell og sekvensreduksjon, som fasit.
    private func bruteForce(_ t: Spilltilstand) -> Int {
        let union = t.hender[0] | t.hender[1] | t.hender[2] | t.hender[3]
        if union == 0 { return 0 }
        let sete = Spillregler.aktivtSete(t)
        let erMaks = t.lagMaske & (1 << UInt8(sete)) != 0
        var beste = erMaks ? Int.min : Int.max
        for indeks in Kortmaske.indekser(Spillregler.lovligMaske(t)) {
            var barn = t
            var verdi = 0
            if let vinner = Spillregler.utfør(&barn, indeks: indeks) {
                verdi += t.lagMaske & (1 << UInt8(vinner)) != 0 ? 1 : 0
            }
            verdi += bruteForce(barn)
            beste = erMaks ? max(beste, verdi) : min(beste, verdi)
        }
        return beste
    }

    private func tilfeldigTilstand(stikk: Int, rng: inout SeededGenerator) -> Spilltilstand {
        var kort = Array(0..<52)
        kort.shuffle(using: &rng)
        var hender = SIMD4<UInt64>(repeating: 0)
        for s in 0..<4 {
            for i in 0..<stikk { hender[s] |= 1 << UInt64(kort[s * stikk + i]) }
        }
        let trumf = Int.random(in: 0..<5, using: &rng)
        let budgiver = Int.random(in: 0..<4, using: &rng)
        var lag: UInt8 = 1 << UInt8(budgiver)
        lag |= 1 << UInt8((budgiver + 1 + Int.random(in: 0..<3, using: &rng)) % 4)
        return Spilltilstand(
            hender: hender, leder: budgiver, pågående: [],
            trumfFarge: trumf == 4 ? nil : trumf, lagMaske: lag,
            budgiver: budgiver, pliktkort: nil, førsteStikk: false
        )
    }

    func testDobbeltdummyMatcherBruteForce() {
        var rng = SeededGenerator(seed: 99)
        for runde in 0..<60 {
            let t = tilfeldigTilstand(stikk: 1 + runde % 4, rng: &rng)
            XCTAssertEqual(Dobbeltdummy().løs(t), bruteForce(t), "Avvik i stilling \(runde)")
        }
    }

    func testDobbeltdummyTarAlleStikkMedToppkortene() {
        // Sete 0 har de seks høyeste sparene (trumf); resten er fordelt lavt.
        var hender = SIMD4<UInt64>(repeating: 0)
        for valør in 7...12 { hender[0] |= 1 << UInt64(valør) }        // spar 9…A
        for valør in 0..<6 { hender[1] |= 1 << UInt64(valør) }         // spar 2…7
        for valør in 0..<6 { hender[2] |= 1 << UInt64(13 + valør) }    // hjerter 2…7
        for valør in 0..<6 { hender[3] |= 1 << UInt64(26 + valør) }    // ruter 2…7
        let t = Spilltilstand(
            hender: hender, leder: 0, pågående: [], trumfFarge: 0,
            lagMaske: 0b0001, budgiver: 0, pliktkort: nil, førsteStikk: false
        )
        XCTAssertEqual(Dobbeltdummy().løs(t), 6)
    }

    func testDobbeltdummyRespektererMakkerplikt() {
        // Sete 0 (budgiver, alene): spar K og 2. Sete 1: spar A og 5.
        // Uten makkerplikt kan sete 1 alltid vinne begge stikkene (dukke
        // billig og beholde esset). Med plikt tvinges esset ut i første
        // stikk, og sete 0 kan spille spar 2 først og vinne det andre
        // stikket med kongen.
        var hender = SIMD4<UInt64>(repeating: 0)
        hender[0] = (1 << 11) | (1 << 0)           // spar K, spar 2
        hender[1] = (1 << 12) | (1 << 3)           // spar A, spar 5
        hender[2] = (1 << 13) | (1 << 14)          // hjerter 2, 3
        hender[3] = (1 << 26) | (1 << 27)          // ruter 2, 3
        let utenPlikt = Spilltilstand(
            hender: hender, leder: 0, pågående: [], trumfFarge: nil,
            lagMaske: 0b0001, budgiver: 0, pliktkort: nil, førsteStikk: true
        )
        var medPlikt = utenPlikt
        medPlikt.pliktkort = 12
        XCTAssertEqual(Dobbeltdummy().løs(utenPlikt), 0)
        XCTAssertEqual(Dobbeltdummy().løs(medPlikt), 1)
    }

    // MARK: - Sampling

    func testSamplingRespektererKjentInformasjon() throws {
        let engine = GameEngine()
        engine.startRunde(seed: 17)
        let budgiver = engine.aktivBudgiver
        engine.giBud(seat: budgiver, action: .bud(5))
        while engine.phase == .budrunde {
            engine.giBud(seat: engine.aktivBudgiver, action: .pass)
        }
        let vrak = Array(engine.hands[budgiver].suffix(engine.rules.antallByttekort))
        XCTAssertTrue(engine.kastByttekort(vrak, seat: budgiver))
        guard let ønsket = engine.kortSomKanØnskes(trumf: .spar)
            .first(where: { kort in (0..<4).contains { $0 != budgiver && engine.hands[$0].contains(kort) } })
        else { return XCTFail("Fant ikke levende ønskekort") }
        engine.velgTrumf(suit: .spar, ønsket: ønsket)

        // Spill noen stikk med første lovlige kort så renonser oppstår.
        for _ in 0..<20 where engine.phase == .spill {
            let sete = engine.aktivSpiller
            engine.spill(kort: engine.lovligeKort(for: sete).first!, seat: sete)
        }
        guard engine.phase == .spill else { return }

        // Sjekk innsikten både for budgiveren (kjenner vraket) og en annen.
        for sete in [budgiver, (budgiver + 1) % 4] {
            let innsikt = try XCTUnwrap(Spillinnsikt(engine: engine, sete: sete))
            // Budgiveren vet hvor vraket er; andre må regne det som ukjent.
            XCTAssertEqual(innsikt.antallDødeUkjente, sete == budgiver ? 0 : 4)
            var rng = SeededGenerator(seed: 3)
            for _ in 0..<50 {
                let verden = try XCTUnwrap(innsikt.sampleVerden(rng: &rng))
                // Egen hånd er urørt, og alle seter har riktig antall kort.
                XCTAssertEqual(verden.hender[sete], innsikt.minHånd)
                for s in 0..<4 {
                    XCTAssertEqual(verden.hender[s].nonzeroBitCount, engine.hands[s].count)
                    // Ingen kort på seter som beviselig ikke kan ha dem.
                    XCTAssertEqual(verden.hender[s] & innsikt.forbudt[s], 0)
                }
                // Ingen spilte kort er delt ut, og ingenting deles ut dobbelt.
                let spilte = Kortmaske.maske(engine.spilteKort)
                var sett: UInt64 = 0
                for s in 0..<4 {
                    XCTAssertEqual(verden.hender[s] & spilte, 0)
                    XCTAssertEqual(verden.hender[s] & sett, 0)
                    sett |= verden.hender[s]
                }
                // Det som ikke ble delt ut er nøyaktig vrakhaugen.
                let ikkeDelt = (innsikt.ukjente | innsikt.minHånd) & ~sett
                XCTAssertEqual(ikkeDelt.nonzeroBitCount, innsikt.antallDødeUkjente)
            }
        }
    }

    // MARK: - Hele runder

    func testMesterSpillerLovligGjennomHelRunde() {
        let engine = GameEngine()
        engine.startRunde(seed: 41)
        var vakt = 0
        while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
            vakt += 1
            XCTAssertLessThan(vakt, 300, "Runden kom aldri i mål")
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                let bud = raskMester(sete: sete, seed: UInt64(vakt)).velgBud(engine: engine)
                XCTAssertTrue(engine.lovligeBud(for: sete).contains(bud))
                XCTAssertTrue(engine.giBud(seat: sete, action: bud))
            case .byttekort:
                let sete = engine.budgiverSeat!
                let vrak = raskMester(sete: sete, seed: UInt64(vakt)).velgByttekort(engine: engine)
                XCTAssertEqual(vrak.count, engine.rules.antallByttekort)
                XCTAssertTrue(engine.kastByttekort(vrak, seat: sete))
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                let valg = raskMester(sete: sete, seed: UInt64(vakt)).velgTrumfOgMakker(engine: engine)
                let (suit, ønsket) = valg ?? (.spar, engine.kortSomKanØnskes(trumf: .spar).first)
                XCTAssertTrue(engine.velgTrumf(suit: suit, ønsket: ønsket))
            case .spill:
                let sete = engine.aktivSpiller
                let mester = raskMester(sete: sete, seed: UInt64(vakt))
                let kort = mester.velgKort(engine: engine) ?? engine.lovligeKort(for: sete).first!
                XCTAssertTrue(engine.lovligeKort(for: sete).contains(kort))
                XCTAssertTrue(engine.spill(kort: kort, seat: sete))
            default:
                return
            }
        }
        XCTAssertEqual(engine.stikkTatt.reduce(0, +), engine.rules.kortPerSpiller)
    }

    func testPresidentAIPlayerErFortsattLovligOgKomplett() {
        // Integrasjonen via AIPlayer (slik GameViewModel bruker den).
        let engine = GameEngine()
        engine.startRunde(seed: 8)
        var vakt = 0
        while engine.phase != .rundeFerdig && engine.phase != .spillFerdig, vakt < 300 {
            vakt += 1
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                let ai = AIPlayer(seat: sete, difficulty: .president, personality: .balansert)
                XCTAssertTrue(engine.giBud(seat: sete, action: ai.velgBud(engine: engine)))
            case .byttekort:
                let sete = engine.budgiverSeat!
                let ai = AIPlayer(seat: sete, difficulty: .president, personality: .balansert)
                XCTAssertTrue(engine.kastByttekort(ai.velgByttekort(engine: engine), seat: sete))
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                let ai = AIPlayer(seat: sete, difficulty: .president, personality: .balansert)
                guard let (suit, ønsket) = ai.velgTrumfOgMakker(engine: engine) else {
                    return XCTFail("Fant ikke trumfvalg")
                }
                XCTAssertTrue(engine.velgTrumf(suit: suit, ønsket: ønsket))
            case .spill:
                let sete = engine.aktivSpiller
                let ai = AIPlayer(seat: sete, difficulty: .president, personality: .balansert)
                guard let kort = ai.velgKort(engine: engine) else {
                    return XCTFail("Fant ikke kort")
                }
                XCTAssertTrue(engine.spill(kort: kort, seat: sete))
            default:
                break
            }
        }
        XCTAssertEqual(engine.stikkTatt.reduce(0, +), engine.rules.kortPerSpiller)
    }
}
