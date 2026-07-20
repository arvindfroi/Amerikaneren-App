import XCTest
@testable import Amerikaneren

/// Tester spillestilanalysen: budkalibrering målt med MesterAI-payoffene
/// og makkerpar-statistikken. Alt beregnes fra rå MatchRecord-er, så
/// analysen fungerer likt for companion-, offline- og online-partier.
final class SpillestilTests: XCTestCase {

    /// Bygger et parti med gitte runder for fire spillere a/b/c/d.
    private func parti(runder: [RoundRecord]) -> MatchRecord {
        let ider = ["a", "b", "c", "d"]
        return MatchRecord(
            mode: .companion,
            deltakere: ider.map {
                MatchParticipant(id: $0, navn: $0.uppercased(), erMeg: $0 == "a",
                                 opponentId: nil, sluttPoeng: 0, vantPartiet: false)
            },
            runder: runder,
            målPoeng: 100
        )
    }

    /// Én tallbudrunde: budgiver a med makker b, motstanderne c/d får
    /// oppgitte stikk – nøyaktig slik companion fører dem (lagets stikk
    /// står aldri i rådataene, de utledes).
    private func runde(bud: Int, klarte: Bool, motC: Int, motD: Int,
                       budgiver: String = "a", makker: String? = "b") -> RoundRecord {
        var poeng: [String: Int] = ["c": motC, "d": motD]
        let fortegn = klarte ? 1 : -1
        poeng[budgiver] = fortegn * (bud >= 2000 ? 100 : bud >= 1000 ? 50 : bud * 2)
        if let makker { poeng[makker] = fortegn * (bud >= 2000 ? 0 : bud >= 1000 ? 25 : bud) }
        return RoundRecord(
            budgiverId: budgiver, makkerId: makker, bud: bud, trumf: nil,
            klarte: klarte,
            stikk: ["c": motC, "d": motD],
            poengEndring: poeng
        )
    }

    // MARK: - Utledet lagstikk

    func testLagStikkUtledesFraMotstandernesStikk() {
        // Motstanderne tok 2 + 3 av 12 -> laget tok 7.
        let r = runde(bud: 7, klarte: true, motC: 2, motD: 3)
        XCTAssertEqual(r.lagStikk(antallSpillere: 4), 7)
        // 3 spillere: 17 stikk totalt.
        let solo3 = RoundRecord(budgiverId: "a", makkerId: nil, bud: 5, trumf: nil,
                                klarte: true, stikk: ["b": 4], poengEndring: [:])
        XCTAssertEqual(solo3.lagStikk(antallSpillere: 3), 13)
    }

    // MARK: - Budanalyse

    func testForForsiktigBudgiverFårBeskjedOmPoengLagtIgjen() {
        // 10 bud på 5 som alle holder med 3 i margin (laget tar 8).
        let runder = (0..<10).map { _ in runde(bud: 5, klarte: true, motC: 2, motD: 2) }
        let analyse = Budanalyse.beregn(for: "a", fra: [parti(runder: runder)])
        XCTAssertEqual(analyse.budGitt, 10)
        XCTAssertEqual(analyse.klaringsrate, 1.0)
        XCTAssertEqual(analyse.snittMarginVedKlart, 3.0)
        XCTAssertEqual(analyse.dom, .forForsiktig)
        // 3 poeng per margin-stikk (2 budgiver + 1 makker) × 3 × 10 runder.
        XCTAssertEqual(analyse.poengLagtIgjen, 90)
    }

    func testForAggressivBudgiverFårTapssummen() {
        // 4 av 10 bud på 9 holder.
        let runder = (0..<10).map { i in
            runde(bud: 9, klarte: i < 4, motC: i < 4 ? 1 : 4, motD: i < 4 ? 2 : 3)
        }
        let analyse = Budanalyse.beregn(for: "a", fra: [parti(runder: runder)])
        XCTAssertEqual(analyse.dom, .forAggressiv)
        XCTAssertEqual(analyse.poengTaptPåRøk, 6 * 3 * 9, "3×bud per røket tallbud")
    }

    func testBalansertBudgiverLiggerIMesterSonen() {
        // 8 av 9 bud holder med liten margin – som MesterAI (~89 %).
        let runder = (0..<9).map { i in
            runde(bud: 7, klarte: i < 8, motC: i < 8 ? 2 : 4, motD: 3)
        }
        let analyse = Budanalyse.beregn(for: "a", fra: [parti(runder: runder)])
        XCTAssertEqual(analyse.dom, .balansert)
        XCTAssertTrue(Budanalyse.referansesone.contains(analyse.klaringsrate))
    }

    func testForLiteDataFørÅtteBudrunder() {
        let runder = (0..<5).map { _ in runde(bud: 6, klarte: true, motC: 3, motD: 3) }
        XCTAssertEqual(Budanalyse.beregn(for: "a", fra: [parti(runder: runder)]).dom, .forLiteData)
    }

    func testAmerikanerOgSoloTellesForSeg() {
        let runder = [
            runde(bud: 1000, klarte: true, motC: 0, motD: 0),
            runde(bud: 2000, klarte: false, motC: 1, motD: 0, makker: nil),
            runde(bud: 7, klarte: true, motC: 2, motD: 3),
        ]
        let analyse = Budanalyse.beregn(for: "a", fra: [parti(runder: runder)])
        XCTAssertEqual(analyse.amerikanere, 1)
        XCTAssertEqual(analyse.amerikanereKlart, 1)
        XCTAssertEqual(analyse.soloer, 1)
        XCTAssertEqual(analyse.soloerKlart, 0)
        XCTAssertEqual(analyse.tallbud, 1)
        // Meldingene påvirker aldri margin-regnestykket for tallbud.
        XCTAssertEqual(analyse.sumMarginKlart, 0)
    }

    // MARK: - Makkerpar

    func testMakkerparTellesUordnetOgPaTversAvPartier() {
        let parti1 = parti(runder: [
            runde(bud: 7, klarte: true, motC: 2, motD: 3),                       // a+b
            runde(bud: 6, klarte: false, motC: 4, motD: 3, budgiver: "b", makker: "a"), // b+a = samme par
            runde(bud: 8, klarte: true, motC: 1, motD: 1, budgiver: "c", makker: "d"),
        ])
        let parti2 = parti(runder: [
            runde(bud: 5, klarte: true, motC: 0, motD: 2),                       // a+b igjen
        ])
        let par = Makkerpar.beregn(fra: [parti1, parti2])
        XCTAssertEqual(par.count, 2)
        let ab = par.first { $0.id == "a|b" }!
        XCTAssertEqual(ab.runderSammen, 3)
        XCTAssertEqual(ab.klart, 2)
        // Runde 1: +14+7, runde 2 (røk): −12−6, parti 2: +10+5 → sum 18.
        XCTAssertEqual(ab.lagPoengSum, 18)
        XCTAssertEqual(par.first?.id, "a|b", "Sortert på flest runder sammen")
    }

    func testRundeUtenMakkerGirIkkePar() {
        let runder = [runde(bud: 2000, klarte: true, motC: 0, motD: 0, makker: nil)]
        XCTAssertTrue(Makkerpar.beregn(fra: [parti(runder: runder)]).isEmpty)
    }
}
