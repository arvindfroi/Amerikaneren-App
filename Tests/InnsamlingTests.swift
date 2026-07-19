import XCTest
@testable import Amerikaneren

/// Tester for treningsdata-innsamlingen: opptak av runder, verifisert
/// avspilling og den lokale sendekøen.
final class InnsamlingTests: XCTestCase {

    /// Spiller en hel runde med heuristiske AI-er og returnerer motoren
    /// stående i rundeFerdig/spillFerdig.
    private func spillHelRunde(seed: UInt64) -> GameEngine {
        let engine = GameEngine()
        let ai = (0..<4).map { AIPlayer(seat: $0, difficulty: .vanskelig, personality: .balansert) }
        engine.startRunde(seed: seed)
        var vakt = 0
        while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
            vakt += 1
            XCTAssertLessThan(vakt, 500, "runden terminerte ikke")
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                engine.giBud(seat: sete, action: ai[sete].velgBud(engine: engine))
            case .byttekort:
                let sete = engine.budgiverSeat!
                if !engine.kastByttekort(ai[sete].velgByttekort(engine: engine), seat: sete) {
                    engine.kastByttekort(Array(engine.hands[sete].suffix(4)), seat: sete)
                }
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                if let (suit, ønsket) = ai[sete].velgTrumfOgMakker(engine: engine),
                   engine.velgTrumf(suit: suit, ønsket: ønsket) { break }
                for suit in Suit.allCases {
                    if let ønsket = engine.kortSomKanØnskes(trumf: suit).first,
                       engine.velgTrumf(suit: suit, ønsket: ønsket) { break }
                    if engine.erSolo, engine.velgTrumf(suit: suit, ønsket: nil) { break }
                }
            case .spill:
                let sete = engine.aktivSpiller
                let kort = ai[sete].velgKort(engine: engine) ?? engine.lovligeKort(for: sete).first!
                XCTAssertTrue(engine.spill(kort: kort, seat: sete))
            default:
                XCTFail("uventet fase \(engine.phase)")
                return engine
            }
        }
        return engine
    }

    private func lagParti(seeds: [UInt64]) -> Partiopptak {
        var runder: [Rundeopptak] = []
        var regler = GameRules()
        var sluttPoeng = [0, 0, 0, 0]
        for seed in seeds {
            let engine = spillHelRunde(seed: seed)
            regler = engine.rules
            guard let opptak = Rundeopptak(fra: engine) else {
                XCTFail("klarte ikke fange runden")
                continue
            }
            runder.append(opptak)
            for s in 0..<4 { sluttPoeng[s] += opptak.resultat.poengEndring[s] }
        }
        return Partiopptak(
            regler: regler, modus: "test",
            seter: (0..<4).map { Seteinfo(menneske: $0 == 0, cpuNivå: $0 == 0 ? nil : "Vanskelig") },
            runder: runder, sluttPoeng: sluttPoeng, vinner: nil
        )
    }

    // MARK: - Opptak og avspilling

    func testRundeopptakSpillesAvIdentisk() throws {
        for seed in [11_001, 11_002, 11_003, 11_004, 11_005] as [UInt64] {
            let engine = spillHelRunde(seed: seed)
            let opptak = try XCTUnwrap(Rundeopptak(fra: engine))

            var budValg = 0, vrakValg = 0, trumfValg = 0, spillValg = 0
            let avspilt = try opptak.spillAv(regler: engine.rules) { motor, valg in
                switch valg {
                case .bud(let sete, _):
                    XCTAssertEqual(motor.aktivBudgiver, sete)
                    budValg += 1
                case .vrak(let sete, let kort):
                    // Beslutningen tas med talongen på hånden.
                    XCTAssertEqual(motor.hands[sete].count, motor.rules.kortPerSpiller + 4)
                    XCTAssertEqual(kort.count, 4)
                    vrakValg += 1
                case .trumfvalg:
                    trumfValg += 1
                case .spill(let sete, let kort):
                    // Fasitkortet er alltid lovlig i situasjonen.
                    XCTAssertTrue(motor.lovligeKort(for: sete).contains(kort))
                    spillValg += 1
                }
            }
            XCTAssertEqual(avspilt.sisteRunde, opptak.resultat)
            XCTAssertEqual(budValg, opptak.bud.count)
            XCTAssertEqual(vrakValg, 1)
            XCTAssertEqual(trumfValg, 1)
            XCTAssertEqual(spillValg, 48)
        }
    }

    func testTukletOpptakAvvises() throws {
        let engine = spillHelRunde(seed: 12_001)
        let original = try XCTUnwrap(Rundeopptak(fra: engine))

        // Bytt om to spilte kort fra ulike stikk: rekkefølgen blir ulovlig
        // eller gir et annet resultat – begge deler skal avvises.
        var tuklet = original
        tuklet.spilte.swapAt(0, 47)
        XCTAssertThrowsError(try tuklet.spillAv(regler: engine.rules))

        // Fjern et kort fra en hånd: ikke lenger en gyldig kortstokk.
        var manglerKort = original
        manglerKort.hender[0].removeFirst()
        XCTAssertThrowsError(try manglerKort.spillAv(regler: engine.rules))

        // Forfalsket resultat skal også avsløres.
        var feilResultat = original
        feilResultat.resultat.klarte.toggle()
        XCTAssertThrowsError(try feilResultat.spillAv(regler: engine.rules))
    }

    func testPartiopptakOverleverJSONRundtur() throws {
        let parti = lagParti(seeds: [13_001, 13_002])
        let data = try JSONEncoder().encode(parti)
        let dekodet = try JSONDecoder().decode(Partiopptak.self, from: data)
        XCTAssertEqual(dekodet, parti)
        try dekodet.verifiser()
    }

    // MARK: - Sendekøen

    private func nyKøMappe() -> URL {
        let mappe = FileManager.default.temporaryDirectory
            .appendingPathComponent("innsamling-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: mappe, withIntermediateDirectories: true)
        return mappe
    }

    func testKøLagrerVerifisererOgBeskjærer() {
        let mappe = nyKøMappe()
        defer { try? FileManager.default.removeItem(at: mappe) }
        // Uten endepunkt blir ingenting lastet opp – bare kølagt.
        let innsamler = Innsamler(
            konfig: InnsamlingKonfig(endepunkt: nil, appNøkkel: "test", maksIKø: 2),
            mappe: mappe
        )

        let parti = lagParti(seeds: [14_001])
        innsamler.leverParti(parti, krevSamtykke: false)
        XCTAssertEqual(innsamler.antallIKø, 1)

        // Et tuklet parti består ikke verifiseringen og skal aldri i kø.
        var tuklet = parti
        tuklet.runder[0].spilte.swapAt(0, 47)
        innsamler.leverParti(tuklet, krevSamtykke: false)
        XCTAssertEqual(innsamler.antallIKø, 1)

        // Køen er avgrenset til maksIKø.
        innsamler.leverParti(lagParti(seeds: [14_002]), krevSamtykke: false)
        innsamler.leverParti(lagParti(seeds: [14_003]), krevSamtykke: false)
        XCTAssertEqual(innsamler.antallIKø, 2)

        innsamler.tømKø()
        XCTAssertEqual(innsamler.antallIKø, 0)
    }
}
