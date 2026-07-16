import XCTest
@testable import Amerikaneren

final class EloTests: XCTestCase {

    func testForventetScoreErSymmetrisk() {
        let a = EloCalculator.forventet(1200, mot: 1000)
        let b = EloCalculator.forventet(1000, mot: 1200)
        XCTAssertEqual(a + b, 1.0, accuracy: 0.0001)
        XCTAssertGreaterThan(a, 0.5)
    }

    func testLikeRatingerGirLikForventning() {
        XCTAssertEqual(EloCalculator.forventet(1000, mot: 1000), 0.5, accuracy: 0.0001)
    }

    func testVinnerFårPlussTaperFårMinus() {
        let motstandere = [(rating: 1000, poeng: 30), (rating: 1000, poeng: 20), (rating: 1000, poeng: 10)]
        let vinnerDelta = EloCalculator.delta(rating: 1000, poeng: 52, motstandere: motstandere, k: 32)
        XCTAssertGreaterThan(vinnerDelta, 0)

        let taperMotstandere = [(rating: 1000, poeng: 52), (rating: 1000, poeng: 30), (rating: 1000, poeng: 20)]
        let taperDelta = EloCalculator.delta(rating: 1000, poeng: 10, motstandere: taperMotstandere, k: 32)
        XCTAssertLessThan(taperDelta, 0)
    }

    func testSeierMotSterkereGirMerEnnMotSvakere() {
        let motSterke = EloCalculator.delta(
            rating: 1000, poeng: 52,
            motstandere: [(1400, 30), (1400, 20), (1400, 10)], k: 32)
        let motSvake = EloCalculator.delta(
            rating: 1000, poeng: 52,
            motstandere: [(800, 30), (800, 20), (800, 10)], k: 32)
        XCTAssertGreaterThan(motSterke, motSvake)
    }

    func testFavorittSomVinnerFårLiteMenIkkeNegativt() {
        let delta = EloCalculator.delta(
            rating: 1800, poeng: 52,
            motstandere: [(900, 30), (900, 20), (900, 10)], k: 32)
        XCTAssertGreaterThanOrEqual(delta, 0)
        XCTAssertLessThan(delta, 5)
    }

    func testUavgjortMotLikMotstanderGirNull() {
        let delta = EloCalculator.delta(
            rating: 1000, poeng: 30,
            motstandere: [(1000, 30)], k: 32)
        XCTAssertEqual(delta, 0)
    }

    func testKFaktorHøyereForNyeSpillere() {
        XCTAssertEqual(EloCalculator.kFaktor(antallRankedKamper: 0), 64)
        XCTAssertEqual(EloCalculator.kFaktor(antallRankedKamper: 9), 64)
        XCTAssertEqual(EloCalculator.kFaktor(antallRankedKamper: 10), 32)
    }

    func testDivisjonsgrenser() {
        XCTAssertEqual(RankTier.forRating(1000), .borger)
        XCTAssertEqual(RankTier.forRating(1099), .borger)
        XCTAssertEqual(RankTier.forRating(1100), .ordfører)
        XCTAssertEqual(RankTier.forRating(1250), .senator)
        XCTAssertEqual(RankTier.forRating(1400), .guvernør)
        XCTAssertEqual(RankTier.forRating(1550), .visepresident)
        XCTAssertEqual(RankTier.forRating(1700), .president)
        XCTAssertEqual(RankTier.forRating(2400), .president)
    }

    func testNullsumVedLikeForutsetninger() {
        // Fire spillere med lik rating og lik K: summen av deltaer ≈ 0.
        let ratinger = [1000, 1000, 1000, 1000]
        let poeng = [52, 35, 20, 5]
        var sum = 0
        for i in 0..<4 {
            let motstandere = (0..<4).filter { $0 != i }.map { (rating: ratinger[$0], poeng: poeng[$0]) }
            sum += EloCalculator.delta(rating: ratinger[i], poeng: poeng[i], motstandere: motstandere, k: 32)
        }
        // Avrunding kan gi ±2 totalt.
        XCTAssertLessThanOrEqual(abs(sum), 2)
    }
}
