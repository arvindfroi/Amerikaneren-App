import XCTest
@testable import Amerikaneren

/// Parallelliseringen av verdensevalueringen skal være ren gjennomstrømning:
/// den skal ikke endre HVA MesterAI velger, bare hvor mange verdener den
/// rekker. Testene her fastholder det ved å kjøre hele runder med fast
/// verdenstall (tidsbudsjettet binder aldri) og kreve at handlingsloggen er
/// identisk uansett hvor mange arbeidere som deler jobben.
final class MesterParallellTests: XCTestCase {

    /// Fast verdenstall og romslig tidsbudsjett: da er resultatet en ren
    /// funksjon av frøene, og trådplanleggingen kan ikke smitte over i
    /// beslutningene.
    private func fastKonfig(tråder: Int) -> MesterKonfig {
        var k = MesterKonfig()
        k.maksTråder = tråder
        k.tidsbudsjett = 3600          // binder aldri
        k.maksVerdener = 12
        k.maksVerdenerSluttspill = 40
        k.minVerdener = 12
        k.eksaktStikkGrense = 5
        k.verdenerVedBud = 12
        k.verdenerVedBytte = 6
        return k
    }

    /// Spiller én runde med fire MesterAI-er og returnerer hele
    /// handlingsloggen (bud, vrak, trumf/etterlysning og hvert kort).
    private func rundelogg(seed: UInt64, tråder: Int) -> [String] {
        let engine = GameEngine()
        engine.startRunde(seed: seed)
        let konfig = fastKonfig(tråder: tråder)
        let mestere = (0..<4).map {
            MesterAI(sete: $0, konfig: konfig, seed: seed &+ UInt64($0) &* 7919)
        }
        var logg: [String] = []
        var vakt = 0
        while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
            vakt += 1
            guard vakt <= 400 else { return ["HENGER"] }
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                let bud = mestere[sete].velgBud(engine: engine)
                logg.append("bud \(sete) \(bud)")
                guard engine.giBud(seat: sete, action: bud) else { return ["ULOVLIG BUD"] }
            case .byttekort:
                let sete = engine.budgiverSeat!
                let vrak = mestere[sete].velgByttekort(engine: engine)
                logg.append("vrak \(sete) " + vrak.map(\.kortSymbol).joined(separator: ","))
                guard engine.kastByttekort(vrak, seat: sete) else { return ["ULOVLIG VRAK"] }
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                guard let (suit, ønsket) = mestere[sete].velgTrumfOgMakker(engine: engine) else {
                    return ["INGEN TRUMF"]
                }
                logg.append("trumf \(sete) \(suit) \(ønsket?.kortSymbol ?? "-")")
                guard engine.velgTrumf(suit: suit, ønsket: ønsket) else { return ["ULOVLIG TRUMF"] }
            case .spill:
                let sete = engine.aktivSpiller
                guard let kort = mestere[sete].velgKort(engine: engine) else { return ["INTET KORT"] }
                logg.append("kort \(sete) \(kort.kortSymbol)")
                guard engine.spill(kort: kort, seat: sete) else { return ["ULOVLIG KORT"] }
            default:
                return ["UVENTET FASE"]
            }
        }
        logg.append("poeng " + engine.sisteRunde!.poengEndring.map(String.init).joined(separator: ","))
        return logg
    }

    /// Samme frø, ulikt antall arbeidere → nøyaktig samme runde. Dette er
    /// hele poenget med avledede frø per verden: resultatet henger ikke på
    /// hvilken tråd som rakk hvilken verden først.
    func testParallellGirSammeRundeSomFærreTråder() {
        for seed: UInt64 in [11, 4242, 90210] {
            let fasit = rundelogg(seed: seed, tråder: 2)
            XCTAssertFalse(fasit.isEmpty)
            XCTAssertGreaterThan(fasit.count, 10, "runden ble ikke spilt ferdig (frø \(seed))")
            for tråder in [3, 4, 8] {
                XCTAssertEqual(rundelogg(seed: seed, tråder: tråder), fasit,
                               "trådtall \(tråder) endret spillet (frø \(seed))")
            }
        }
    }

    /// Gjentatte kjøringer med samme trådtall skal også være like – fanger
    /// kappløp som bare slår ut av og til.
    func testGjentatteParallellkjøringerErLike() {
        let fasit = rundelogg(seed: 777, tråder: 8)
        for _ in 0..<4 {
            XCTAssertEqual(rundelogg(seed: 777, tråder: 8), fasit)
        }
    }

    /// Tidsbudsjettet skal fortsatt holdes i parallellmodus, og minst
    /// `minVerdener` skal alltid rekkes selv med et absurd kort budsjett.
    func testTidsbudsjettOgMinVerdenerHoldesParallelt() {
        let engine = GameEngine()
        engine.startRunde(seed: 20260722)
        var konfig = MesterKonfig.automatisk()
        konfig.tidsbudsjett = 0.05
        konfig.minVerdener = 8
        let mestere = (0..<4).map { MesterAI(sete: $0, konfig: konfig, seed: UInt64($0) &+ 1) }
        var vakt = 0
        var målteTrekk = 0
        while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
            vakt += 1
            guard vakt <= 400 else { break }
            switch engine.phase {
            case .budrunde:
                let s = engine.aktivBudgiver
                _ = engine.giBud(seat: s, action: mestere[s].velgBud(engine: engine))
            case .byttekort:
                let s = engine.budgiverSeat!
                _ = engine.kastByttekort(mestere[s].velgByttekort(engine: engine), seat: s)
            case .velgTrumf:
                let s = engine.budgiverSeat!
                guard let (suit, ønsket) = mestere[s].velgTrumfOgMakker(engine: engine) else { return }
                _ = engine.velgTrumf(suit: suit, ønsket: ønsket)
            case .spill:
                let s = engine.aktivSpiller
                let start = Date()
                guard let kort = mestere[s].velgKort(engine: engine) else { return }
                let brukt = Date().timeIntervalSince(start)
                if mestere[s].sisteVerdenstall > 0 {
                    målteTrekk += 1
                    XCTAssertGreaterThanOrEqual(mestere[s].sisteVerdenstall, konfig.minVerdener,
                                                "minVerdener ble ikke respektert")
                    // Rikelig slingringsmonn for maskinlast; poenget er at
                    // fristen faktisk stopper søket i stedet for å la det
                    // løpe til taket (som nå er trådtall × 1200).
                    XCTAssertLessThan(brukt, 3.0, "trekket sprengte tidsbudsjettet grovt")
                }
                _ = engine.spill(kort: kort, seat: s)
            default:
                return
            }
        }
        XCTAssertGreaterThan(målteTrekk, 0, "ingen søkende trekk ble målt")
    }

    /// `automatisk()` skal faktisk slå på parallellitet på flerkjernemaskiner,
    /// og takene skal følge med opp slik at tiden – ikke taket – binder.
    func testAutomatiskKonfigSkalererMedKjerner() {
        let kjerner = ProcessInfo.processInfo.activeProcessorCount
        let k = MesterKonfig.automatisk()
        XCTAssertEqual(k.maksTråder, max(1, kjerner - 1))
        XCTAssertEqual(k.trådtall, min(max(1, kjerner - 1), kjerner))
        let basis = MesterKonfig()
        let grunn = kjerner >= 6 ? 36 : basis.maksVerdener
        XCTAssertEqual(k.maksVerdener, grunn * k.maksTråder)
        XCTAssertEqual(k.maksVerdenerSluttspill, basis.maksVerdenerSluttspill * k.maksTråder)
        // Standardkonfigurasjonen (uten automatikk) må forbli entrådet, ellers
        // slutter A/B-basislinjen å være dagens MesterAI.
        XCTAssertEqual(basis.maksTråder, 1)
    }
}
