import XCTest
@testable import Amerikaneren

/// Ad hoc-analyse (kjøres i WSL, ikke ment for innsjekk):
///  1) EV per utspillskandidat for S3 i stikk 2 (runde 2 i partiloggen),
///     målt over et stort felles verdensett med budvekting – svarer på
///     «hvorfor J♠ og ikke lav trumf?».
///  2) Styrke-A/B med parrede frø: dagens konfig mot pre-fiks-konfigen
///     og mot en kandidat med bredere midtspillsøk.
final class Stikk2EVogABTests: XCTestCase {

    private func sp(_ r: Rank) -> Card { Card(suit: .spar, rank: r) }
    private func hj(_ r: Rank) -> Card { Card(suit: .hjerter, rank: r) }
    private func ru(_ r: Rank) -> Card { Card(suit: .ruter, rank: r) }
    private func kl(_ r: Rank) -> Card { Card(suit: .kløver, rank: r) }

    private func spillStikk(_ engine: GameEngine, _ spill: [(Int, Card)]) {
        for (sete, kort) in spill {
            XCTAssertTrue(engine.spill(kort: kort, seat: sete),
                          "Ulovlig spill: sete \(sete) \(kort.kortSymbol)")
        }
    }

    private func byggTilStikk2() -> GameEngine {
        let engine = GameEngine()
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
        engine.kastByttekort(talon1, seat: 2)
        engine.velgTrumf(suit: .kløver, ønsket: kl(.king))
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
        engine.kastByttekort([sp(.three), ru(.nine), ru(.two), kl(.nine)], seat: 0)
        engine.velgTrumf(suit: .hjerter, ønsket: hj(.queen))
        spillStikk(engine, [(0, hj(.four)), (1, hj(.two)), (2, hj(.six)), (3, hj(.queen))])
        XCTAssertEqual(engine.aktivSpiller, 3)
        return engine
    }

    // MARK: - Kopier av MesterAIs private evaluering (holdes i synk manuelt)

    private func vurderKopi(kandidat: Int, verden: Verden, innsikt: Spillinnsikt,
                            dd: Dobbeltdummy, konfig: MesterKonfig) -> Double {
        var t = Spilltilstand(
            hender: verden.hender, leder: innsikt.leder, pågående: innsikt.pågående,
            trumfFarge: innsikt.trumfFarge, lagMaske: verden.lagMaske,
            budgiver: innsikt.budgiver, pliktkort: innsikt.pliktkort,
            førsteStikk: innsikt.trickNummer == 0
        )
        var perSete = [0, 0, 0, 0]
        if let vinnerSete = Spillregler.utfør(&t, indeks: kandidat) {
            perSete[vinnerSete] += 1
        }
        t = GrådigSpiller.spillUt(t, stoppVedStikkIgjen: konfig.eksaktStikkGrense, perSete: &perSete)

        let ddLag = dd.løs(t)
        var lagStikk = ddLag
        for s in 0..<4 where verden.lagMaske & (1 << UInt8(s)) != 0 {
            lagStikk += innsikt.stikkTatt[s] + perSete[s]
        }
        let mål: Int
        switch innsikt.bud {
        case .bud(let n): mål = n
        case .amerikaner, .soloAmerikaner, .pass: mål = innsikt.stikkTotalt
        }
        let suksess = lagStikk >= mål

        let budgiverPoeng: Int
        let makkerPoeng: Int
        switch innsikt.bud {
        case .soloAmerikaner:
            budgiverPoeng = innsikt.målPoeng; makkerPoeng = 0
        case .amerikaner:
            budgiverPoeng = innsikt.målPoeng / 2; makkerPoeng = innsikt.målPoeng / 4
        case .bud(let n):
            budgiverPoeng = n * innsikt.budgiverFaktor; makkerPoeng = n
        case .pass:
            budgiverPoeng = 0; makkerPoeng = 0
        }

        let spiltStikk = (0..<4).reduce(0) { $0 + innsikt.stikkTatt[$1] + perSete[$1] }
        let haleForsvar = (innsikt.stikkTotalt - spiltStikk) - ddLag
        let antallForsvarere = 4 - (0..<4).count { verden.lagMaske & (1 << UInt8($0)) != 0 }
        let forsvarsAndel = antallForsvarere > 0 ? Double(haleForsvar) / Double(antallForsvarere) : 0

        var delta = [Double](repeating: 0, count: 4)
        for s in 0..<4 {
            if s == innsikt.budgiver {
                delta[s] = Double(suksess ? budgiverPoeng : -budgiverPoeng)
            } else if verden.lagMaske & (1 << UInt8(s)) != 0 {
                delta[s] = Double(suksess ? makkerPoeng : -makkerPoeng)
            } else {
                delta[s] = Double(innsikt.stikkTatt[s] + perSete[s]) + forsvarsAndel
            }
        }

        let meg = innsikt.sete
        var verdi = delta[meg]
        for s in 0..<4 where s != meg {
            let nærhet = Double(min(innsikt.poengNå[s], innsikt.målPoeng)) / Double(innsikt.målPoeng)
            verdi -= (1.0 + nærhet) / 3.0 * delta[s]
        }
        if innsikt.harMålstrek {
            let målstrek = Double(innsikt.målPoeng)
            if Double(innsikt.poengNå[meg]) + delta[meg] >= målstrek {
                verdi += målstrek
            } else if (0..<4).contains(where: { $0 != meg && Double(innsikt.poengNå[$0]) + delta[$0] >= målstrek }) {
                verdi -= målstrek
            }
        }
        return verdi
    }

    private func budVektKopi(innsikt: Spillinnsikt, hender: SIMD4<UInt64>) -> Double {
        var vekt = 1.0
        for s in 0..<4 where s != innsikt.sete {
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

    /// EV ± SE per utspillskandidat for S3 i stikk 2, felles verdensett.
    func testS3UtspillEV() {
        let engine = byggTilStikk2()
        guard let innsikt = Spillinnsikt(engine: engine, sete: 3) else { return XCTFail() }
        let konfig = MesterKonfig.automatisk()
        let lovlige = engine.lovligeKort(for: 3)
        let union = innsikt.ukjente | innsikt.minHånd
        let kandidater = Spillregler.reduserteTrekk(lovlig: Kortmaske.maske(lovlige), union: union)

        var rng = SeededGenerator(seed: 9)
        let antall = 1500
        var vektSum = 0.0
        var sum = [Double](repeating: 0, count: kandidater.count)
        var kvadrat = [Double](repeating: 0, count: kandidater.count)
        var vektKvadrat = 0.0
        for _ in 0..<antall {
            guard let verden = innsikt.sampleVerden(rng: &rng) else { continue }
            let vekt = budVektKopi(innsikt: innsikt, hender: verden.hender)
            vektSum += vekt
            vektKvadrat += vekt * vekt
            let dd = Dobbeltdummy()
            for (i, kandidat) in kandidater.enumerated() {
                let v = vurderKopi(kandidat: kandidat, verden: verden, innsikt: innsikt, dd: dd, konfig: konfig)
                sum[i] += vekt * v
                kvadrat[i] += vekt * v * v
            }
        }
        let nEff = vektSum * vektSum / max(vektKvadrat, 1e-9)
        print("  S3s utspillskandidater (vektet EV over \(antall) verdener, n_eff ≈ \(Int(nEff))):")
        let rangert = kandidater.indices.sorted { sum[$0] > sum[$1] }
        for i in rangert {
            let snitt = sum[i] / vektSum
            let varians = max(0, kvadrat[i] / vektSum - snitt * snitt)
            let se = (varians / nEff).squareRoot()
            print(String(format: "    %@: %+.3f ± %.3f", Kortmaske.kort(kandidater[i]).kortSymbol, snitt, se))
        }
    }

    // MARK: - Styrke-A/B (parrede frø, samme motstandere)

    private func spillRunde(seed: UInt64, spillere: [Int: AIPlayer]) -> RoundResult? {
        let engine = GameEngine()
        engine.startRunde(seed: seed)
        var vakt = 0
        while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
            vakt += 1
            if vakt > 400 { return nil }
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                guard engine.giBud(seat: sete, action: spillere[sete]!.velgBud(engine: engine)) else { return nil }
            case .byttekort:
                let sete = engine.budgiverSeat!
                guard engine.kastByttekort(spillere[sete]!.velgByttekort(engine: engine), seat: sete) else { return nil }
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                guard let (suit, ønsket) = spillere[sete]!.velgTrumfOgMakker(engine: engine),
                      engine.velgTrumf(suit: suit, ønsket: ønsket) else { return nil }
            case .spill:
                let sete = engine.aktivSpiller
                guard let kort = spillere[sete]!.velgKort(engine: engine),
                      engine.spill(kort: kort, seat: sete) else { return nil }
            default:
                return nil
            }
        }
        return engine.sisteRunde
    }

    /// Fremdrift og resultater skrives til en varig fil i tillegg til stderr:
    /// `swift test` fanger testprosessens stdio, så filen er eneste kanal som
    /// garantert overlever både rør og avbrudd. Sharding styres med miljø-
    /// variabler: H2H_FRA/H2H_TIL (frø-intervall) og H2H_LOGG (loggfil).
    private static let loggSti = ProcessInfo.processInfo.environment["H2H_LOGG"]
        ?? (NSHomeDirectory() + "/h2h-v2.log")

    private func fremdrift(_ tekst: String) {
        let linje = "⏳ " + tekst + "\n"
        let data = linje.data(using: .utf8)!
        FileHandle.standardError.write(data)
        if !FileManager.default.fileExists(atPath: Self.loggSti) {
            FileManager.default.createFile(atPath: Self.loggSti, contents: nil)
        }
        if let h = FileHandle(forWritingAtPath: Self.loggSti) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        }
    }

    private func målStyrke(_ konfig: MesterKonfig, navn: String = "arm",
                           frø: ClosedRange<UInt64>) -> [Int?] {
        MesterAI.overstyrKonfig = konfig
        defer { MesterAI.overstyrKonfig = nil }
        var poeng: [Int?] = []
        for seed in frø {
            if seed % 25 == 0 { fremdrift("\(navn): runde \(seed)/\(frø.upperBound)") }
            let spillere: [Int: AIPlayer] = [
                0: AIPlayer(seat: 0, difficulty: .president, personality: .balansert),
                1: AIPlayer(seat: 1, difficulty: .vanskelig, personality: .balansert),
                2: AIPlayer(seat: 2, difficulty: .vanskelig, personality: .balansert),
                3: AIPlayer(seat: 3, difficulty: .vanskelig, personality: .balansert),
            ]
            poeng.append(spillRunde(seed: seed, spillere: spillere)?.poengEndring[0])
        }
        return poeng
    }

    // MARK: - Partinivå: ny President mot gammel (kjøres i sluttvalideringen)

    /// Spiller et helt parti (først til 100) der to seter bruker konfig A og
    /// to bruker konfig B, alle på President-nivå. Returnerer vinnerens konfig.
    private func spillParti(seed: UInt64, konfigA: MesterKonfig, seterA: Set<Int>,
                            konfigB: MesterKonfig) -> String? {
        var spillere: [Int: AIPlayer] = [:]
        for sete in 0..<4 {
            MesterAI.overstyrKonfig = seterA.contains(sete) ? konfigA : konfigB
            spillere[sete] = AIPlayer(seat: sete, difficulty: .president, personality: .balansert)
        }
        MesterAI.overstyrKonfig = nil
        let engine = GameEngine()
        var rundeNr: UInt64 = 0
        var vakt = 0
        while engine.phase != .spillFerdig {
            vakt += 1
            if vakt > 12000 { return nil }
            switch engine.phase {
            case .venterPåStart, .rundeFerdig:
                engine.startRunde(seed: seed &* 1_000_003 &+ rundeNr)
                rundeNr += 1
            case .budrunde:
                let sete = engine.aktivBudgiver
                guard engine.giBud(seat: sete, action: spillere[sete]!.velgBud(engine: engine)) else { return nil }
            case .byttekort:
                let sete = engine.budgiverSeat!
                guard engine.kastByttekort(spillere[sete]!.velgByttekort(engine: engine), seat: sete) else { return nil }
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                guard let (suit, ønsket) = spillere[sete]!.velgTrumfOgMakker(engine: engine),
                      engine.velgTrumf(suit: suit, ønsket: ønsket) else { return nil }
            case .spill:
                let sete = engine.aktivSpiller
                guard let kort = spillere[sete]!.velgKort(engine: engine),
                      engine.spill(kort: kort, seat: sete) else { return nil }
            case .spillFerdig:
                break
            }
        }
        guard let vinner = engine.vinnerSeat else { return nil }
        return seterA.contains(vinner) ? "A" : "B"
    }

    /// Som spillParti, men returnerer også sluttpoeng summert per konfig.
    private func spillPartiMedPoeng(seed: UInt64, konfigA: MesterKonfig, seterA: Set<Int>,
                                    konfigB: MesterKonfig) -> (vinner: String, poengA: Int, poengB: Int)? {
        var spillere: [Int: AIPlayer] = [:]
        for sete in 0..<4 {
            MesterAI.overstyrKonfig = seterA.contains(sete) ? konfigA : konfigB
            spillere[sete] = AIPlayer(seat: sete, difficulty: .president, personality: .balansert)
        }
        MesterAI.overstyrKonfig = nil
        let engine = GameEngine()
        var rundeNr: UInt64 = 0
        var vakt = 0
        while engine.phase != .spillFerdig {
            vakt += 1
            if vakt > 12000 { return nil }
            switch engine.phase {
            case .venterPåStart, .rundeFerdig:
                engine.startRunde(seed: seed &* 1_000_003 &+ rundeNr)
                rundeNr += 1
            case .budrunde:
                let sete = engine.aktivBudgiver
                guard engine.giBud(seat: sete, action: spillere[sete]!.velgBud(engine: engine)) else { return nil }
            case .byttekort:
                let sete = engine.budgiverSeat!
                guard engine.kastByttekort(spillere[sete]!.velgByttekort(engine: engine), seat: sete) else { return nil }
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                guard let (suit, ønsket) = spillere[sete]!.velgTrumfOgMakker(engine: engine),
                      engine.velgTrumf(suit: suit, ønsket: ønsket) else { return nil }
            case .spill:
                let sete = engine.aktivSpiller
                guard let kort = spillere[sete]!.velgKort(engine: engine),
                      engine.spill(kort: kort, seat: sete) else { return nil }
            case .spillFerdig:
                break
            }
        }
        guard let vinner = engine.vinnerSeat else { return nil }
        let poengA = seterA.reduce(0) { $0 + engine.scores[$1] }
        let poengB = (0..<4).filter { !seterA.contains($0) }.reduce(0) { $0 + engine.scores[$1] }
        return (seterA.contains(vinner) ? "A" : "B", poengA, poengB)
    }

    /// H2H v2: parret speildesign – samme frø spilles to ganger med byttede
    /// seter, og poengdifferansen per speilpar er primærmetrikken (langt
    /// strammere enn seier/tap). Fremdrift per parti på stderr.
    func testPartiNyMotGammelV2() {
        var ny = MesterKonfig.automatisk()
        ny.tidsbudsjett = 0.12
        var gammel = ny
        gammel.maksVerdenerSluttspill = gammel.maksVerdener   // pre-fiks

        var seireNy = 0, seireGammel = 0
        var parDiff: [Double] = []
        let miljø = ProcessInfo.processInfo.environment
        let fra = miljø["H2H_FRA"].flatMap { UInt64($0) } ?? 1
        let til = miljø["H2H_TIL"].flatMap { UInt64($0) } ?? 45
        let par = til
        for p in fra...til {
            var diffIParet = 0.0
            for seterNy in [Set([0, 2]), Set([1, 3])] {
                guard let r = spillPartiMedPoeng(seed: p, konfigA: ny, seterA: seterNy, konfigB: gammel) else {
                    fremdrift("parti (frø \(p)) avbrutt"); continue
                }
                if r.vinner == "A" { seireNy += 1 } else { seireGammel += 1 }
                diffIParet += Double(r.poengA - r.poengB)
                fremdrift("par \(p)/\(par): vinner \(r.vinner == "A" ? "NY" : "GML") · poeng ny−gml \(r.poengA - r.poengB) · stilling \(seireNy)–\(seireGammel)")
            }
            parDiff.append(diffIParet)
        }
        let n = seireNy + seireGammel
        let andel = Double(seireNy) / Double(max(1, n))
        let seAndel = (andel * (1 - andel) / Double(max(1, n))).squareRoot()
        let m = Double(parDiff.count)
        let snitt = parDiff.reduce(0, +) / m
        let varians = parDiff.reduce(0) { $0 + ($1 - snitt) * ($1 - snitt) } / max(1, m - 1)
        let seDiff = (varians / m).squareRoot()
        let oppsummering = String(
            format: "H2H v2 FERDIG: ny vant %d av %d (%.0f %% ± %.0f) · poengdiff per speilpar %+.1f ± %.1f",
            seireNy, n, 100 * andel, 100 * seAndel, snitt, seDiff)
        fremdrift(oppsummering)
        print("  " + oppsummering)
    }

    /// Head-to-head over hele partier: ny konfig (A) mot pre-sesjons-konfig (B),
    /// speilvendt setetildeling annenhver gang så seteskjevhet nulles ut.
    func testPartiNyMotGammel() {
        var ny = MesterKonfig.automatisk()
        ny.tidsbudsjett = 0.2
        var gammel = ny
        gammel.maksVerdenerSluttspill = gammel.maksVerdener   // pre-fiks

        var seireNy = 0, seireGammel = 0
        let partier: UInt64 = 40
        for i in 1...partier {
            let seterNy: Set<Int> = i % 2 == 0 ? [0, 2] : [1, 3]
            guard let vinner = spillParti(seed: i, konfigA: ny, seterA: seterNy, konfigB: gammel) else {
                print("  parti \(i) avbrutt"); continue
            }
            if vinner == "A" { seireNy += 1 } else { seireGammel += 1 }
        }
        let n = seireNy + seireGammel
        print(String(format: "  ny President vant %d av %d partier (%.0f %%) mot pre-sesjons-Presidenten",
                     seireNy, n, 100.0 * Double(seireNy) / Double(max(1, n))))
    }

    // MARK: - Hypotese-feier (shardbar via miljøvariabler)

    private static func skrivLinje(_ tekst: String, til sti: String) {
        let data = (tekst + "\n").data(using: .utf8)!
        FileHandle.standardError.write(data)
        if !FileManager.default.fileExists(atPath: sti) {
            FileManager.default.createFile(atPath: sti, contents: nil)
        }
        if let h = FileHandle(forWritingAtPath: sti) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        }
    }

    /// Én arbeider: spiller parrede runder (samme frø, arm A = dagens,
    /// arm B = varianten) og logger poengene per frø til varig fil.
    /// Miljø: RAB_HYP (variantnavn), RAB_FRA/RAB_TIL (frø), RAB_LOGG (fil).
    func testRundeSweep() throws {
        let miljø = ProcessInfo.processInfo.environment
        guard let hyp = miljø["RAB_HYP"] else {
            throw XCTSkip("RAB_HYP ikke satt – kjøres bare som shard-arbeider")
        }
        var dagens = MesterKonfig.automatisk()
        dagens.tidsbudsjett = 0.2
        var variant = dagens
        switch hyp {
        case "minverdener16":  variant.minVerdener = 16
        case "grense6":        variant.eksaktStikkGrense = 6
        case "sluttspill2400": variant.maksVerdenerSluttspill = 2400
        case "sluttspill600":  variant.maksVerdenerSluttspill = 600
        case "utenbudvekt":    variant.budvekting = false
        case "bytte40":        variant.verdenerVedBytte = 40
        case "utenmatch":      variant.matchbevisst = false
        case "prefiks":        variant.maksVerdenerSluttspill = variant.maksVerdener
        case "mester":
            // Evolusjonens «beste noensinne» fra sjekkpunktet.
            let data = FileManager.default.contents(atPath: NSHomeDirectory() + "/evolusjon/tilstand.json")!
            let tilstand = try JSONDecoder().decode(Evolusjon.Tilstand.self, from: data)
            variant.vekter = try XCTUnwrap(tilstand.besteNoensinne)
        default: return XCTFail("ukjent hypotese: \(hyp)")
        }
        let fra = miljø["RAB_FRA"].flatMap { UInt64($0) } ?? 1
        let til = miljø["RAB_TIL"].flatMap { UInt64($0) } ?? 300
        let logg = miljø["RAB_LOGG"] ?? (NSHomeDirectory() + "/sweep-\(hyp).log")

        for seed in fra...til {
            var poeng: [String: Int?] = [:]
            for (arm, konfig) in [("A", dagens), ("B", variant)] {
                MesterAI.overstyrKonfig = konfig
                let spillere: [Int: AIPlayer] = [
                    0: AIPlayer(seat: 0, difficulty: .president, personality: .balansert),
                    1: AIPlayer(seat: 1, difficulty: .vanskelig, personality: .balansert),
                    2: AIPlayer(seat: 2, difficulty: .vanskelig, personality: .balansert),
                    3: AIPlayer(seat: 3, difficulty: .vanskelig, personality: .balansert),
                ]
                MesterAI.overstyrKonfig = nil
                poeng[arm] = spillRunde(seed: seed, spillere: spillere)?.poengEndring[0]
            }
            if let a = poeng["A"] ?? nil, let b = poeng["B"] ?? nil {
                Self.skrivLinje("SWEEP hyp=\(hyp) frø=\(seed) A=\(a) B=\(b)", til: logg)
            } else {
                Self.skrivLinje("SWEEP hyp=\(hyp) frø=\(seed) AVBRUTT", til: logg)
            }
        }
        Self.skrivLinje("SWEEP hyp=\(hyp) frø=\(fra)-\(til) FERDIG", til: logg)
    }

    func testABKonfigurasjoner() {
        var dagens = MesterKonfig.automatisk()
        dagens.tidsbudsjett = 0.2

        var preFiks = dagens
        preFiks.maksVerdenerSluttspill = preFiks.maksVerdener   // som før fiksen

        let frø: ClosedRange<UInt64> = 1...150
        let armer: [(String, MesterKonfig)] = [
            ("dagens                     ", dagens),
            ("pre-fiks (tak 36 overalt)  ", preFiks),
        ]
        var resultater: [[Int?]] = []
        for (navn, konfig) in armer {
            let start = Date()
            let poeng = målStyrke(konfig, navn: navn.trimmingCharacters(in: .whitespaces), frø: frø)
            let gyldige = poeng.compactMap { $0 }
            let snitt = Double(gyldige.reduce(0, +)) / Double(gyldige.count)
            print(String(format: "  %@: %+.2f poeng/runde over %d runder (%.0f s)",
                         navn, snitt, gyldige.count, Date().timeIntervalSince(start)))
            resultater.append(poeng)
        }
        // Parret differanse mot dagens konfig.
        for arm in 1..<armer.count {
            var diff: [Double] = []
            for i in 0..<resultater[0].count {
                if let a = resultater[0][i], let b = resultater[arm][i] { diff.append(Double(a - b)) }
            }
            let n = Double(diff.count)
            let snitt = diff.reduce(0, +) / n
            let varians = diff.reduce(0) { $0 + ($1 - snitt) * ($1 - snitt) } / max(1, n - 1)
            let se = (varians / n).squareRoot()
            print(String(format: "  parret: dagens − %@ = %+.2f ± %.2f poeng/runde",
                         armer[arm].0.trimmingCharacters(in: .whitespaces), snitt, se))
        }
    }
}
