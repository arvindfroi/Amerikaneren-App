import XCTest
@testable import Amerikaneren

/// Tester poengføringen i companion-modus. ViewModellen kjøres uten
/// persistens (lagringURL: nil) så testene ikke rører Documents-mappen.
///
/// Husreglene: budgiveren får alltid dobbelt av makkeren (±2×bud mot
/// ±bud), Amerikaner gir ±50/±25, solo-amerikaner ±100, og alle utenfor
/// budgiverlaget får ett poeng per eget stikk. Med 4 spillere er det
/// 4 byttekort og 12 stikk per runde.
@MainActor
final class CompanionTests: XCTestCase {

    private func nyttParti(spillere: [String] = ["Du", "Ola", "Kari", "Per"],
                           harMål: Bool = true, mål: Int = 52) -> CompanionViewModel {
        let vm = CompanionViewModel(lagringURL: nil)
        vm.oppføringer = spillere.map { CompanionViewModel.Oppføring(navn: $0) }
        vm.harMål = harMål
        vm.målPoeng = mål
        vm.startParti()
        return vm
    }

    // MARK: - Utledet utfall

    func testKlarteUtledesAvMotstandernesStikk() {
        let vm = nyttParti()
        vm.budgiver = 0
        vm.makker = 1
        vm.bud = 7
        // Motstanderne (2 og 3) får 2 + 3 = 5 stikk -> laget fikk 7 = budet.
        vm.motstanderStikk[2] = 2
        vm.motstanderStikk[3] = 3
        XCTAssertEqual(vm.lagetsStikk, 7)
        XCTAssertTrue(vm.klarte)

        // Ett stikk til motstanderne -> laget fikk bare 6 og ryker.
        vm.motstanderStikk[3] = 4
        XCTAssertEqual(vm.lagetsStikk, 6)
        XCTAssertFalse(vm.klarte)
    }

    func testStikkKanIkkeOverstigeRundensTotal() {
        let vm = nyttParti()
        vm.budgiver = 0
        vm.makker = 1
        vm.motstanderStikk[2] = 7
        vm.motstanderStikk[3] = 7
        XCTAssertFalse(vm.stikkGyldige)

        let poengFør = vm.poeng
        vm.førRunde()
        XCTAssertEqual(vm.poeng, poengFør, "Ugyldige stikk skal ikke kunne føres")
        XCTAssertTrue(vm.runder.isEmpty)
    }

    func testRundeKanIkkeFøresUtenMakker() {
        let vm = nyttParti()
        vm.budgiver = 0
        vm.makker = -1
        vm.bud = 6
        XCTAssertFalse(vm.kanFøreRunde, "Vanlige bud spilles aldri alene")
        vm.førRunde()
        XCTAssertTrue(vm.runder.isEmpty)

        vm.budtype = .solo
        XCTAssertTrue(vm.kanFøreRunde, "Solo-amerikaneren er eneste alenespill")
    }

    // MARK: - Poengregler

    func testBudgiverFårDobbeltAvMakkeren() {
        let vm = nyttParti()
        vm.budgiver = 0
        vm.makker = 1
        vm.bud = 8
        vm.motstanderStikk[2] = 2
        vm.motstanderStikk[3] = 2
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [16, 8, 2, 2])
    }

    func testLagSomFeilerTaperDobbeltOgEnkelt() {
        let vm = nyttParti()
        vm.budgiver = 0
        vm.makker = 1
        vm.bud = 10
        vm.motstanderStikk[2] = 4
        vm.motstanderStikk[3] = 2
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [-20, -10, 4, 2])
    }

    func testAmerikanerGir50Og25() {
        let vm = nyttParti()
        vm.budgiver = 1
        vm.makker = 2
        vm.budtype = .amerikaner
        XCTAssertTrue(vm.klarte, "Ingen stikk til motstanderne = Amerikaneren holdt")
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [0, 50, 25, 0])
        XCTAssertEqual(vm.runder[0].bud, 1000)
    }

    func testAmerikanerFeiletGirMinus50Og25() {
        let vm = nyttParti()
        vm.budgiver = 1
        vm.makker = 2
        vm.budtype = .amerikaner
        vm.motstanderStikk[0] = 1
        XCTAssertFalse(vm.klarte)
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [1, -50, -25, 0])
    }

    func testSoloAmerikanerGir100() {
        let vm = nyttParti()
        vm.budgiver = 1
        vm.budtype = .solo
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [0, 100, 0, 0])
        XCTAssertEqual(vm.runder[0].bud, 2000)
        XCTAssertNil(vm.runder[0].makker)
        XCTAssertEqual(vm.runder[0].stikk[1], 12, "Solisten tok alle stikkene")
    }

    func testSoloAmerikanerFeiletGirMinus100() {
        let vm = nyttParti()
        vm.budgiver = 1
        vm.budtype = .solo
        vm.motstanderStikk[3] = 2
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [0, -100, 0, 2])
    }

    func testAndreSpillertallFårRestenSomByttekort() {
        // 3 spillere: 17 kort hver, 1 byttekort. 4 spillere: 12 og 4.
        XCTAssertEqual(nyttParti(spillere: ["Du", "Ola", "Kari"]).totalStikk, 17)
        XCTAssertEqual(nyttParti().totalStikk, 12)
    }

    // MARK: - Mål og vinner

    func testFerdigNårNoenNårMålet() {
        let vm = nyttParti(mål: 20)
        vm.budgiver = 0
        vm.makker = 1
        vm.bud = 8
        vm.motstanderStikk[2] = 1
        vm.motstanderStikk[3] = 1
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [16, 8, 1, 1])
        XCTAssertFalse(vm.ferdig)
        vm.budgiver = 0
        vm.makker = 1
        vm.bud = 8
        vm.motstanderStikk[2] = 1
        vm.motstanderStikk[3] = 1
        vm.førRunde()
        XCTAssertTrue(vm.ferdig)
        XCTAssertEqual(vm.vinnerIndex, 0)
    }

    func testÅpentPartiBlirAldriFerdigAvSegSelv() {
        let vm = nyttParti(harMål: false)
        XCTAssertNil(vm.aktivtMål)
        vm.budgiver = 0
        vm.makker = 1
        vm.bud = 12
        vm.førRunde()
        XCTAssertEqual(vm.poeng[0], 24)
        XCTAssertFalse(vm.ferdig, "Åpent parti avsluttes manuelt")
    }

    func testPoengAkkumuleresOverFlereRunder() {
        let vm = nyttParti(harMål: false)
        // Runde 1: 2 (budgiver) og 3 klarer 8; motstanderne 0 og 1 får 3 + 1.
        vm.budgiver = 2
        vm.makker = 3
        vm.bud = 8
        vm.motstanderStikk[0] = 3
        vm.motstanderStikk[1] = 1
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [3, 1, 16, 8])
        // Runde 2: 0 (budgiver) og 1 klarer 8; motstanderne 2 og 3 får 0 + 4.
        vm.budgiver = 0
        vm.makker = 1
        vm.bud = 8
        vm.motstanderStikk[2] = 0
        vm.motstanderStikk[3] = 4
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [19, 9, 16, 12])
        XCTAssertEqual(vm.vinnerIndex, 0)
        // Runde 3: 0 (budgiver) og 3 byr 5 og feiler (laget fikk bare 4).
        vm.budgiver = 0
        vm.makker = 3
        vm.bud = 5
        vm.motstanderStikk[1] = 7
        vm.motstanderStikk[2] = 1
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [9, 16, 17, 7])
        XCTAssertEqual(vm.vinnerIndex, 2)
    }

    func testLikhetTiebreakTilBudgiverlaget() {
        let vm = nyttParti(harMål: false)
        // Runde 1: 2 og 3 byr 5 og feiler stort; 0 tar alle 12 stikkene.
        vm.budgiver = 2
        vm.makker = 3
        vm.bud = 5
        vm.motstanderStikk[0] = 12
        vm.motstanderStikk[1] = 0
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [12, 0, -10, -5])
        // Runde 2: 2 og 3 klarer 11 – 2 ender likt med 0 på 12 poeng.
        vm.budgiver = 2
        vm.makker = 3
        vm.bud = 11
        vm.motstanderStikk[0] = 0
        vm.motstanderStikk[1] = 1
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [12, 1, 12, 6])
        // Budgiversiden fra siste runde vinner likheten.
        XCTAssertEqual(vm.vinnerIndex, 2)
    }

    // MARK: - Angre

    func testAngreSisteRundeGjenoppretterAlt() {
        let vm = nyttParti()
        vm.budgiver = 0
        vm.makker = 1
        vm.bud = 7
        vm.motstanderStikk[2] = 2
        vm.motstanderStikk[3] = 3
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [14, 7, 2, 3])
        XCTAssertEqual(vm.budgiver, 1, "Neste budgiver etter runden")

        vm.angreSisteRunde()
        XCTAssertEqual(vm.poeng, [0, 0, 0, 0])
        XCTAssertTrue(vm.runder.isEmpty)
        XCTAssertEqual(vm.budgiver, 0, "Skjemaet er tilbake på den angrede runden")
        XCTAssertEqual(vm.makker, 1)
        XCTAssertEqual(vm.bud, 7)
        XCTAssertEqual(vm.budtype, .vanlig)
        XCTAssertEqual(vm.motstanderStikk, [0, 0, 2, 3])
    }

    func testAngreSoloGjenoppretterBudtypen() {
        let vm = nyttParti()
        vm.budgiver = 2
        vm.budtype = .solo
        vm.førRunde()
        XCTAssertEqual(vm.poeng, [0, 0, 100, 0])
        vm.angreSisteRunde()
        XCTAssertEqual(vm.poeng, [0, 0, 0, 0])
        XCTAssertEqual(vm.budtype, .solo)
        XCTAssertEqual(vm.budgiver, 2)
    }

    // MARK: - MatchRecord og spillerkobling

    func testMatchRecordFårStabileIderOgKoblingTilBrukere() {
        let vm = CompanionViewModel(lagringURL: nil)
        vm.oppføringer = [
            .init(navn: "Du"),
            .init(navn: "Ola"),
            .init(navn: "Kari", gameCenterId: "G:123"),
            .init(navn: "Per"),
        ]
        vm.startParti()

        vm.budgiver = 1
        vm.makker = 2
        vm.bud = 7
        vm.motstanderStikk[0] = 2
        vm.motstanderStikk[3] = 3
        vm.førRunde()

        let record = vm.lagMatchRecord()
        XCTAssertEqual(record.mode, .companion)
        XCTAssertEqual(record.deltakere[0].id, "meg")
        XCTAssertEqual(record.deltakere[1].id, "companion-ola")
        XCTAssertEqual(record.deltakere[2].id, "online-G:123",
                       "Koblet spiller deler id med online-partiene, så H2H slås sammen")
        XCTAssertEqual(record.runder[0].budgiverId, "companion-ola")
        XCTAssertEqual(record.runder[0].makkerId, "online-G:123")
        XCTAssertEqual(record.runder[0].stikk["meg"], 2)
        XCTAssertEqual(record.runder[0].poengEndring["companion-ola"], 14)
        XCTAssertEqual(record.runder[0].poengEndring["online-G:123"], 7)
        XCTAssertTrue(record.runder[0].klarte)
    }

    // MARK: - Persistens av pågående parti

    func testPågåendePartiLagresOgGjenopprettes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let vm = CompanionViewModel(lagringURL: url)
        vm.oppføringer = [.init(navn: "Du"), .init(navn: "Ola"), .init(navn: "Kari"), .init(navn: "Per")]
        vm.harMål = false
        vm.startParti()
        vm.budgiver = 0
        vm.makker = 1
        vm.bud = 7
        vm.motstanderStikk[2] = 2
        vm.motstanderStikk[3] = 3
        vm.førRunde()

        // «Appen startes på nytt» midt i partiet.
        let gjenopprettet = CompanionViewModel(lagringURL: url)
        XCTAssertTrue(gjenopprettet.partiPågår)
        XCTAssertEqual(gjenopprettet.spillere, ["Du", "Ola", "Kari", "Per"])
        XCTAssertEqual(gjenopprettet.poeng, [14, 7, 2, 3])
        XCTAssertEqual(gjenopprettet.runder.count, 1)
        XCTAssertNil(gjenopprettet.aktivtMål)
        XCTAssertEqual(gjenopprettet.budgiver, 1)
    }

    func testAvbrytSletterLagretParti() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let vm = CompanionViewModel(lagringURL: url)
        vm.oppføringer = [.init(navn: "Du"), .init(navn: "Ola"), .init(navn: "Kari")]
        vm.startParti()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        vm.avbryt()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(CompanionViewModel(lagringURL: url).partiPågår)
    }
}
