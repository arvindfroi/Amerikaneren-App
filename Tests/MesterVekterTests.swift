import XCTest
@testable import Amerikaneren

final class MesterVekterTests: XCTestCase {

    /// Standardvektene skal kode/dekode tapsfritt og være like seg selv.
    func testKodekOgLikhet() throws {
        let standard = MesterVekter()
        let data = try JSONEncoder().encode(standard)
        let tilbake = try JSONDecoder().decode(MesterVekter.self, from: data)
        XCTAssertEqual(standard, tilbake)
    }

    /// Mutasjon med rate 0 er identitet; med rate 1 og sigma > 0 skal
    /// minst ett gen ha flyttet seg. Nevneren holdes alltid unna null.
    func testMutasjon() {
        var rng = SeededGenerator(seed: 7)
        let standard = MesterVekter()
        XCTAssertEqual(standard.mutert(sigma: 0.2, rate: 0, rng: &rng), standard)
        let barn = standard.mutert(sigma: 0.2, rate: 1, rng: &rng)
        XCTAssertNotEqual(barn, standard)
        XCTAssertGreaterThanOrEqual(barn.motstanderNevner, 0.5)
    }

    /// Krysning henter hvert gen fra én av foreldrene.
    func testKrysning() {
        var rng = SeededGenerator(seed: 11)
        let a = MesterVekter()
        var b = a
        for gen in MesterVekter.gener { b[keyPath: gen.sti] += gen.skala }
        let barn = MesterVekter.krysning(a, b, rng: &rng)
        for gen in MesterVekter.gener {
            let verdi = barn[keyPath: gen.sti]
            XCTAssertTrue(verdi == a[keyPath: gen.sti] || verdi == b[keyPath: gen.sti],
                          "genet \(gen.navn) kom ikke fra noen av foreldrene")
        }
    }

    /// settPoengstilling setter stillingen mellom runder og bevares av
    /// neste rundestart (poeng akkumuleres oppå den).
    func testSettPoengstilling() {
        let engine = GameEngine()
        engine.settPoengstilling([50, 20, 30, 10])
        XCTAssertEqual(engine.scores, [50, 20, 30, 10])
        engine.startRunde(seed: 42)
        XCTAssertEqual(engine.scores, [50, 20, 30, 10])
        XCTAssertEqual(engine.phase, .budrunde)
    }
}
