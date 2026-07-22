import XCTest
@testable import Amerikaneren

/// Reproduserer det dokumenterte feilspillet fra runde 2 i partiloggen
/// (spill-logg.txt): ved stikk 11 leder budgiveren (sete 0, bud 10, trumf
/// hjerter) 5♥. Sete 1 sitter med {A♠, K♦}, er renons i hjerter, og alle
/// hjerter er ute. De ni usette kortene for sete 1 er ♠K,10,9,3 ♦Q,9,2
/// ♣Q,9 – fem levende og fire i budgiverens vrakhaug. Riktig er å beholde
/// A♠ (vinner siste stikk når spar ledes, 4/9 av uniforme verdener) og
/// vrake K♦ (vinner bare når ruter ledes, 3/9). MesterAI kastet A♠.
final class MesterAIStikk11Tests: XCTestCase {

    // MARK: - Kort-hjelpere

    private func sp(_ r: Rank) -> Card { Card(suit: .spar, rank: r) }
    private func hj(_ r: Rank) -> Card { Card(suit: .hjerter, rank: r) }
    private func ru(_ r: Rank) -> Card { Card(suit: .ruter, rank: r) }
    private func kl(_ r: Rank) -> Card { Card(suit: .kløver, rank: r) }

    private func spillStikk(_ engine: GameEngine, _ spill: [(Int, Card)],
                            file: StaticString = #filePath, line: UInt = #line) {
        for (sete, kort) in spill {
            XCTAssertTrue(engine.spill(kort: kort, seat: sete),
                          "Ulovlig spill: sete \(sete) \(kort.kortSymbol)", file: file, line: line)
        }
    }

    // MARK: - Fikstur: posisjonen ved stikk 11

    /// Spiller frem hele partiet til beslutningspunktet: runde 1 gir
    /// poengstillingen [9, 0, 18, 0], runde 2 spilles til sete 1 skal
    /// legge sitt nest siste kort på budgiverens 5♥.
    private func byggPosisjon(file: StaticString = #filePath, line: UInt = #line) -> GameEngine {
        let engine = GameEngine()

        // ── Runde 1 (S2 vant med 9, trumf kløver, etterlyst K♣) ──
        let hender1: [[Card]] = [
            [sp(.king), sp(.ten), hj(.jack), hj(.six), hj(.three),
             ru(.king), ru(.nine), ru(.five), kl(.king), kl(.nine), kl(.four), kl(.three)],
            [sp(.seven), sp(.five), sp(.three), sp(.two), hj(.ace), hj(.ten), hj(.two),
             ru(.ten), ru(.six), ru(.four), kl(.queen), kl(.six)],
            [sp(.ace), ru(.ace), ru(.queen), ru(.jack), ru(.seven), ru(.two),
             kl(.ace), kl(.jack), kl(.ten), kl(.seven), kl(.five), kl(.two)],
            [sp(.queen), sp(.jack), sp(.six), sp(.four), hj(.nine), hj(.eight),
             hj(.seven), hj(.five), hj(.four), ru(.eight), ru(.three), kl(.eight)],
        ]
        let talon1 = [sp(.nine), sp(.eight), hj(.king), hj(.queen)]
        engine.startRunde(hender: hender1, talon: talon1, førsteBudgiver: 1)

        engine.giBud(seat: 1, action: .bud(5))
        engine.giBud(seat: 2, action: .bud(6))
        engine.giBud(seat: 3, action: .bud(7))
        engine.giBud(seat: 0, action: .bud(8))
        engine.giBud(seat: 1, action: .pass)
        engine.giBud(seat: 2, action: .bud(9))
        engine.giBud(seat: 3, action: .pass)
        engine.giBud(seat: 0, action: .pass)
        XCTAssertTrue(engine.kastByttekort(talon1, seat: 2), file: file, line: line)
        XCTAssertTrue(engine.velgTrumf(suit: .kløver, ønsket: kl(.king)), file: file, line: line)

        spillStikk(engine, [(2, kl(.two)), (3, kl(.eight)), (0, kl(.king)), (1, kl(.queen))])
        spillStikk(engine, [(0, kl(.nine)), (1, kl(.six)), (2, kl(.five)), (3, ru(.three))])
        spillStikk(engine, [(0, kl(.four)), (1, hj(.two)), (2, kl(.ace)), (3, ru(.eight))])
        spillStikk(engine, [(2, sp(.ace)), (3, sp(.four)), (0, sp(.ten)), (1, sp(.three))])
        spillStikk(engine, [(2, ru(.ace)), (3, hj(.five)), (0, ru(.five)), (1, ru(.four))])
        spillStikk(engine, [(2, ru(.queen)), (3, hj(.four)), (0, ru(.nine)), (1, ru(.six))])
        spillStikk(engine, [(2, ru(.seven)), (3, sp(.six)), (0, ru(.king)), (1, ru(.ten))])
        spillStikk(engine, [(0, sp(.king)), (1, sp(.seven)), (2, ru(.jack)), (3, sp(.queen))])
        spillStikk(engine, [(0, hj(.jack)), (1, hj(.ace)), (2, kl(.jack)), (3, hj(.nine))])
        spillStikk(engine, [(2, ru(.two)), (3, hj(.eight)), (0, kl(.three)), (1, sp(.five))])
        spillStikk(engine, [(0, hj(.three)), (1, hj(.ten)), (2, kl(.ten)), (3, hj(.seven))])
        spillStikk(engine, [(2, kl(.seven)), (3, sp(.jack)), (0, hj(.six)), (1, sp(.two))])

        XCTAssertEqual(engine.phase, .rundeFerdig, file: file, line: line)
        XCTAssertEqual(engine.scores, [9, 0, 18, 0], file: file, line: line)

        // ── Runde 2 (Arvind vant med 10, trumf hjerter, etterlyst Q♥) ──
        let hender2: [[Card]] = [
            [sp(.queen), sp(.three), hj(.ace), hj(.ten), hj(.nine), hj(.eight), hj(.four),
             ru(.nine), ru(.two), kl(.ace), kl(.king), kl(.nine)],
            [sp(.ace), sp(.eight), sp(.two), hj(.jack), hj(.seven), hj(.two),
             ru(.king), ru(.jack), ru(.seven), ru(.four), kl(.five), kl(.three)],
            [sp(.five), sp(.four), hj(.six), ru(.queen), ru(.six), ru(.five), ru(.three),
             kl(.queen), kl(.eight), kl(.seven), kl(.six), kl(.two)],
            [sp(.jack), sp(.ten), sp(.nine), sp(.seven), sp(.six), hj(.queen), hj(.three),
             ru(.ten), ru(.eight), kl(.jack), kl(.ten), kl(.four)],
        ]
        let talon2 = [sp(.king), hj(.king), hj(.five), ru(.ace)]
        engine.startRunde(hender: hender2, talon: talon2, førsteBudgiver: 2)

        engine.giBud(seat: 2, action: .bud(5))
        engine.giBud(seat: 3, action: .bud(6))
        engine.giBud(seat: 0, action: .bud(8))
        engine.giBud(seat: 1, action: .bud(9))
        engine.giBud(seat: 2, action: .pass)
        engine.giBud(seat: 3, action: .pass)
        engine.giBud(seat: 0, action: .bud(10))
        engine.giBud(seat: 1, action: .pass)
        XCTAssertTrue(engine.kastByttekort([sp(.three), ru(.nine), ru(.two), kl(.nine)], seat: 0),
                      file: file, line: line)
        XCTAssertTrue(engine.velgTrumf(suit: .hjerter, ønsket: hj(.queen)), file: file, line: line)

        spillStikk(engine, [(0, hj(.four)), (1, hj(.two)), (2, hj(.six)), (3, hj(.queen))])
        spillStikk(engine, [(3, sp(.jack)), (0, sp(.queen)), (1, sp(.two)), (2, sp(.five))])
        spillStikk(engine, [(0, hj(.ace)), (1, hj(.seven)), (2, sp(.four)), (3, hj(.three))])
        spillStikk(engine, [(0, hj(.king)), (1, hj(.jack)), (2, kl(.two)), (3, ru(.eight))])
        spillStikk(engine, [(0, ru(.ace)), (1, ru(.four)), (2, ru(.three)), (3, ru(.ten))])
        spillStikk(engine, [(0, kl(.ace)), (1, kl(.three)), (2, kl(.eight)), (3, kl(.four))])
        spillStikk(engine, [(0, kl(.king)), (1, kl(.five)), (2, kl(.seven)), (3, kl(.jack))])
        spillStikk(engine, [(0, hj(.ten)), (1, ru(.seven)), (2, ru(.six)), (3, sp(.seven))])
        spillStikk(engine, [(0, hj(.nine)), (1, ru(.jack)), (2, ru(.five)), (3, sp(.six))])
        spillStikk(engine, [(0, hj(.eight)), (1, sp(.eight)), (2, kl(.six)), (3, kl(.ten))])
        spillStikk(engine, [(0, hj(.five))])

        XCTAssertEqual(engine.trickNummer, 10, file: file, line: line)
        XCTAssertEqual(engine.aktivSpiller, 1, file: file, line: line)
        XCTAssertEqual(Set(engine.hands[1]), Set([sp(.ace), ru(.king)]), file: file, line: line)
        return engine
    }

    func testPosisjonenErKorrektOppstilt() {
        let engine = byggPosisjon()
        XCTAssertEqual(engine.currentTrick.map(\.card), [hj(.five)])
        XCTAssertEqual(engine.hands[0], [sp(.king)])
        XCTAssertEqual(Set(engine.hands[2]), Set([ru(.queen), kl(.queen)]))
        XCTAssertEqual(Set(engine.hands[3]), Set([sp(.ten), sp(.nine)]))
        XCTAssertEqual(engine.stikkTatt, [9, 0, 0, 1])
        XCTAssertEqual(engine.scores, [9, 0, 18, 0])

        let innsikt = Spillinnsikt(engine: engine, sete: 1)
        XCTAssertNotNil(innsikt)
        XCTAssertEqual(innsikt?.antallDødeUkjente, 4)
        XCTAssertEqual(innsikt?.ukjente.nonzeroBitCount, 9)
    }

    // MARK: - Diagnostikk

    /// Fordeles vrakhaugens fire døde kort uniformt? Sete 0s siste kort skal
    /// være hvert av de ni usette kortene med sannsynlighet 1/9, og spar
    /// med 4/9.
    func testSampleVerdenFordelerDeUkjenteUniformt() {
        let engine = byggPosisjon()
        guard let innsikt = Spillinnsikt(engine: engine, sete: 1) else {
            return XCTFail("Spillinnsikt manglet")
        }
        var rng = SeededGenerator(seed: 42)
        var perKort: [Int: Int] = [:]
        let antall = 20000
        for _ in 0..<antall {
            guard let verden = innsikt.sampleVerden(rng: &rng) else {
                return XCTFail("sampleVerden feilet")
            }
            XCTAssertEqual(verden.hender[0].nonzeroBitCount, 1)
            XCTAssertEqual(verden.hender[2].nonzeroBitCount, 2)
            XCTAssertEqual(verden.hender[3].nonzeroBitCount, 2)
            perKort[Kortmaske.høyeste(verden.hender[0]), default: 0] += 1
        }
        var sparAndel = 0.0
        for (kortIdx, n) in perKort.sorted(by: { $0.value > $1.value }) {
            let andel = Double(n) / Double(antall)
            print(String(format: "  sete 0 har %@: %5.2f %% (forventet 11.11 %%)",
                         Kortmaske.kort(kortIdx).kortSymbol, andel * 100))
            if kortIdx / 13 == 0 { sparAndel += andel }
            XCTAssertEqual(andel, 1.0 / 9.0, accuracy: 0.01,
                           "Skjevt: \(Kortmaske.kort(kortIdx).kortSymbol)")
        }
        print(String(format: "  → P(sete 0 leder spar) = %.3f (forventet 0.444)", sparAndel))
    }

    /// Budvektens gjennomsnitt per verdenstype (fargen på sete 0s siste
    /// kort). Kopierer den private budVekt-logikken fra MesterAI.
    func testBudvektPerVerdenstype() {
        let engine = byggPosisjon()
        guard let innsikt = Spillinnsikt(engine: engine, sete: 1) else {
            return XCTFail("Spillinnsikt manglet")
        }
        func budVekt(hender: SIMD4<UInt64>) -> Double {
            var vekt = 1.0
            for s in 0..<4 where s != 1 {
                let profil = innsikt.budProfiler[s]
                guard profil.harSignal else { continue }
                let full = hender[s] | innsikt.spiltAvSete[s]
                guard full != 0 else { continue }
                let est = AIPlayer.besteTrumf(hånd: Kortmaske.kortliste(full)).estimat
                if profil.meldteAlle {
                    vekt *= exp(-0.5 * max(0, Double(innsikt.stikkTotalt) - 2.0 - est))
                } else if let n = profil.tallbud {
                    vekt *= exp(-0.6 * max(0, Double(n) - (est + 2.5)))
                }
                if let gulv = profil.passetVedGulv {
                    vekt *= exp(-0.4 * max(0, est + 2.0 - Double(gulv) - 1.5))
                }
            }
            return max(vekt, 0.02)
        }

        var rng = SeededGenerator(seed: 7)
        var sumVekt = [Double](repeating: 0, count: 4)
        var antallPerFarge = [Int](repeating: 0, count: 4)
        for _ in 0..<5000 {
            guard let verden = innsikt.sampleVerden(rng: &rng) else { continue }
            let farge = Kortmaske.høyeste(verden.hender[0]) / 13
            sumVekt[farge] += budVekt(hender: verden.hender)
            antallPerFarge[farge] += 1
        }
        for farge in 0..<4 where antallPerFarge[farge] > 0 {
            print(String(format: "  sete 0 leder %@: snittvekt %.3f (n=%d)",
                         Kortmaske.farger[farge].navn, sumVekt[farge] / Double(antallPerFarge[farge]),
                         antallPerFarge[farge]))
        }
        let vektetSpar = sumVekt[0]
        let vektetRuter = sumVekt[2]
        print(String(format: "  → vektet masse spar %.1f mot ruter %.1f", vektetSpar, vektetRuter))
    }

    /// Regresjonstesten for selve feilspillet: sete 1 skal legge K♦ og
    /// beholde A♠. Før fiksen (verdenstak 28/36 også i sluttspillet) valgte
    /// MesterAI feil i ~35 % av frøene; med sluttspillstaket skal valget
    /// være stabilt over praktisk talt alle frø.
    func testStikk11LeggerRuterKongeOgBeholderSparEss() {
        let engine = byggPosisjon()
        var valgte: [Card: Int] = [:]
        let antallFrø = 60
        for frø in 1...antallFrø {
            let mester = MesterAI(sete: 1, konfig: MesterKonfig.automatisk(), seed: UInt64(frø))
            guard let valg = mester.velgKort(engine: engine) else {
                return XCTFail("velgKort ga ingen kort")
            }
            valgte[valg, default: 0] += 1
        }
        for (kort, n) in valgte.sorted(by: { $0.value > $1.value }) {
            print(String(format: "  legger %@ (beholder %@): %3d av %d (%.1f %%)",
                         kort.kortSymbol,
                         engine.hands[1].first { $0 != kort }!.kortSymbol,
                         n, antallFrø, 100.0 * Double(n) / Double(antallFrø)))
        }
        // Én sløv verden kan alltid snike seg inn – men fordelingsmarginen
        // (4/9 mot 3/9 over 1200 verdener) skal gjøre feilvalg eksepsjonelt.
        XCTAssertGreaterThanOrEqual(valgte[ru(.king), default: 0], antallFrø - 2,
                                    "Feilspillet er tilbake: A♠ kastes i sluttspillet")
    }

    /// Hvor mange verdener rekker søket i sluttspillet, og hvor mange ville
    /// tidsbudsjettet tillatt? Replikerer velgKort-løkka uten verdenstak.
    func testVerdenerInnenTidsbudsjettISluttspill() {
        let engine = byggPosisjon()
        guard let innsikt = Spillinnsikt(engine: engine, sete: 1) else {
            return XCTFail("Spillinnsikt manglet")
        }
        let konfig = MesterKonfig.automatisk()
        var rng = SeededGenerator(seed: 3)
        let frist = Date().addingTimeInterval(konfig.tidsbudsjett)
        var verdener = 0
        while Date() < frist {
            guard let verden = innsikt.sampleVerden(rng: &rng) else { break }
            // Samme arbeid som vurder(): grådig + eksakt løsning per kandidat.
            let dd = Dobbeltdummy()
            for kandidat in [Kortmaske.indeks(sp(.ace)), Kortmaske.indeks(ru(.king))] {
                var t = Spilltilstand(
                    hender: verden.hender, leder: innsikt.leder, pågående: innsikt.pågående,
                    trumfFarge: innsikt.trumfFarge, lagMaske: verden.lagMaske,
                    budgiver: innsikt.budgiver, pliktkort: innsikt.pliktkort, førsteStikk: false
                )
                var perSete = [0, 0, 0, 0]
                if let vinner = Spillregler.utfør(&t, indeks: kandidat) { perSete[vinner] += 1 }
                t = GrådigSpiller.spillUt(t, stoppVedStikkIgjen: konfig.eksaktStikkGrense, perSete: &perSete)
                _ = dd.løs(t)
            }
            verdener += 1
        }
        print("  tidsbudsjettet (\(konfig.tidsbudsjett) s) rakk \(verdener) verdener – taket er \(konfig.maksVerdener)")
    }
}
