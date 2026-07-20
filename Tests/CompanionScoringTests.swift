import XCTest
@testable import Amerikaneren

final class CompanionScoringTests: XCTestCase {

    private func parti(_ spillere: [String] = ["Du", "Kari", "Ola", "Petter"], mål: Int = 100) -> CompanionParti {
        CompanionParti(spillere: spillere, målPoeng: mål)
    }

    // MARK: - Navnevalidering

    func testGyldigeSpillereTrimmerOgFiltrerer() {
        let navn = CompanionParti.gyldigeSpillere([" Du ", "", "Kari", "Ola  "])
        XCTAssertEqual(navn, ["Du", "Kari", "Ola"])
    }

    func testGyldigeSpillereAvviserFåOgDubletter() {
        XCTAssertNil(CompanionParti.gyldigeSpillere(["Du", "Kari"]))
        XCTAssertNil(CompanionParti.gyldigeSpillere(["Du", "Kari", "Kari"]))
        XCTAssertNil(CompanionParti.gyldigeSpillere(["1", "2", "3", "4", "5", "6", "7"]))
    }

    func testKortPerSpillerFølgerAntallet() {
        // Husregelen med 4 spillere: 12 kort hver, 4 i byttekort-talongen.
        XCTAssertEqual(parti().kortPerSpiller, 12)
        XCTAssertEqual(parti(["A", "B", "C"]).kortPerSpiller, 17)
        XCTAssertEqual(parti(["A", "B", "C", "D", "E", "F"]).kortPerSpiller, 8)
    }

    // MARK: - Tallbud

    func testTallbudKlartGirDobbeltTilBudgiverEnkeltTilMakker() {
        var p = parti()
        let runde = p.førRunde(
            budgiver: 0, makker: 1, bud: 6,
            erAmerikaner: false, erSolo: false, klarte: true, stikk: [0, 0, 4, 3]
        )
        XCTAssertEqual(runde.poengEndring, [12, 6, 4, 3])
        XCTAssertEqual(p.poeng, [12, 6, 4, 3])
        XCTAssertEqual(runde.bud, 6)
        XCTAssertEqual(runde.makker, 1)
    }

    func testTallbudRøykTrekkerBeggeMenGirStikkTilResten() {
        var p = parti()
        let runde = p.førRunde(
            budgiver: 2, makker: 0, bud: 7,
            erAmerikaner: false, erSolo: false, klarte: false, stikk: [0, 5, 0, 3]
        )
        XCTAssertEqual(runde.poengEndring, [-7, 5, -14, 3])
    }

    func testMakkerLikBudgiverTellerSomAlene() {
        var p = parti()
        let runde = p.førRunde(
            budgiver: 1, makker: 1, bud: 8,
            erAmerikaner: false, erSolo: false, klarte: true, stikk: [2, 0, 2, 1]
        )
        XCTAssertNil(runde.makker)
        XCTAssertEqual(runde.poengEndring, [2, 16, 2, 1])
    }

    func testNegativMakkerIndeksBetyrIngenMakker() {
        var p = parti()
        let runde = p.førRunde(
            budgiver: 0, makker: -1, bud: 5,
            erAmerikaner: false, erSolo: false, klarte: true, stikk: [0, 3, 2, 3]
        )
        XCTAssertNil(runde.makker)
        XCTAssertEqual(runde.poengEndring, [10, 3, 2, 3])
    }

    // MARK: - Amerikaner og solo

    func testAmerikanerGirHalvpartenOgFjerdedel() {
        var p = parti(mål: 100)
        let klarte = p.førRunde(
            budgiver: 0, makker: 2, bud: 0,
            erAmerikaner: true, erSolo: false, klarte: true, stikk: [0, 0, 0, 0]
        )
        XCTAssertEqual(klarte.poengEndring, [50, 0, 25, 0])
        XCTAssertEqual(klarte.bud, 1000)

        var p2 = parti(mål: 100)
        let røk = p2.førRunde(
            budgiver: 0, makker: 2, bud: 0,
            erAmerikaner: true, erSolo: false, klarte: false, stikk: [0, 6, 0, 7]
        )
        XCTAssertEqual(røk.poengEndring, [-50, 6, -25, 7])
    }

    func testSoloAmerikanerGirMålPoengAlene() {
        var p = parti(mål: 100)
        let runde = p.førRunde(
            budgiver: 3, makker: 1, bud: 0,
            erAmerikaner: false, erSolo: true, klarte: true, stikk: [0, 0, 0, 0]
        )
        XCTAssertNil(runde.makker, "Solo har aldri makker – selv om skjemaet peker på en")
        XCTAssertEqual(runde.poengEndring, [0, 0, 0, 100])
        XCTAssertEqual(runde.bud, 2000)
    }

    // MARK: - Partiets gang

    func testFerdigOgVinnerNårNoenNårMålet() {
        var p = parti(mål: 20)
        XCTAssertFalse(p.ferdig)
        XCTAssertNil(p.vinner)
        p.førRunde(
            budgiver: 1, makker: nil, bud: 10,
            erAmerikaner: false, erSolo: false, klarte: true, stikk: [1, 0, 1, 1]
        )
        XCTAssertTrue(p.ferdig)
        XCTAssertEqual(p.vinner, 1)
        XCTAssertEqual(p.sortert.first, 1)
    }

    func testRunderAkkumulererOgBeskrivelsenLeses() {
        var p = parti()
        p.førRunde(
            budgiver: 0, makker: 1, bud: 6,
            erAmerikaner: false, erSolo: false, klarte: true, stikk: [0, 0, 4, 3]
        )
        p.førRunde(
            budgiver: 1, makker: nil, bud: 0,
            erAmerikaner: true, erSolo: false, klarte: false, stikk: [4, 0, 5, 4]
        )
        XCTAssertEqual(p.runder.count, 2)
        XCTAssertEqual(p.runder[0].beskrivelse(spillere: p.spillere), "Du: 6 stikk (m/ Kari)")
        XCTAssertEqual(p.runder[1].beskrivelse(spillere: p.spillere), "Kari: Amerikaner")
    }

    func testTreSpillereFungerer() {
        var p = parti(["A", "B", "C"])
        let runde = p.førRunde(
            budgiver: 0, makker: nil, bud: 9,
            erAmerikaner: false, erSolo: false, klarte: false, stikk: [0, 5, 4]
        )
        XCTAssertEqual(runde.poengEndring, [-18, 5, 4])
    }
}
