import Foundation

// Måleverktøy for budkalibreringen i MesterAI.
//
// Alt kjøres med LÅSTE verdenstall (min == maks) og et tidsbudsjett som
// aldri binder, slik at resultatene er uavhengige av maskinlasten og kan
// shardes fritt over mange prosesser.

// MARK: - Fast konfig

func budFastKonfig(verdener: Int = 28, sluttspill: Int = 200, eksaktFra: Int = 6,
                   bud: Int = 64, bytte: Int = 20,
                   aggresjon: Double = 0) -> MesterKonfig {
    var k = MesterKonfig()
    k.maksVerdener = verdener
    k.minVerdener = verdener
    k.maksVerdenerSluttspill = sluttspill
    k.eksaktStikkGrense = eksaktFra
    k.tidsbudsjett = 1e9            // klokka skal aldri avgjøre noe
    k.verdenerVedBud = bud
    k.verdenerVedBytte = bytte
    k.budAggresjon = aggresjon
    return k
}

// MARK: - Én runde med per-sete-konfig

/// Alt vi trenger å vite om én ferdigspilt runde.
struct Budrunde {
    var frø: UInt64
    var førsteBudgiver: Int
    var budgiver: Int
    var budRang: Int              // n, 1000 = amerikaner, 2000 = solo
    var makker: Int
    var klarte: Bool
    var lagStikk: Int
    var poeng: [Int]
    var stikk: [Int]
    /// Budbeslutninger i rekkefølge: sete, minsteBud, p, evBud, evPass,
    /// snittStikk, valgt rang.
    var beslutninger: [Buddiagnoselinje]
}

struct Buddiagnoselinje {
    var sete: Int
    var minsteBud: Int
    var p: Double
    var evBud: Double
    var evPass: Double
    var snittStikk: Double
    var valgtRang: Int
}

/// Spiller én runde med én MesterAI per sete, hver med sin egen konfig.
/// Frøene er utledet av rundefrøet, så to armer med samme rundefrø deler
/// både utdeling og Monte Carlo-sekvens.
func budSpillRunde(frø: UInt64, konfigPerSete: [MesterKonfig],
                   samleDiagnose: Bool = false) -> Budrunde? {
    let rules = GameRules()
    let engine = GameEngine(rules: rules)

    // Roter hvem som åpner budrunden, ellers sitter sete 0 alltid i samme
    // auksjonsposisjon (motoren starter alltid med dealer = 0).
    let stokk = Deck.stokket(seed: frø)
    let iSpill = stokk.count - rules.antallByttekort
    let hender = (0..<4).map { s in
        stride(from: s, to: iSpill, by: 4).map { stokk[$0] }.sortertForHånd()
    }
    let førsteBudgiver = Int(frø % 4)
    engine.startRunde(hender: hender, talon: Array(stokk.suffix(rules.antallByttekort)),
                      førsteBudgiver: førsteBudgiver)

    let mestere = (0..<4).map {
        MesterAI(sete: $0, konfig: konfigPerSete[$0], seed: frø &* 7919 &+ UInt64($0) &+ 1)
    }
    let reserve = (0..<4).map { AIPlayer(seat: $0, difficulty: .vanskelig, personality: .balansert) }

    var beslutninger: [Buddiagnoselinje] = []
    var aktivtSete = 0
    if samleDiagnose {
        MesterAI.budkrok = { d in
            guard let b = d.minsteBud else { return }
            beslutninger.append(Buddiagnoselinje(
                sete: aktivtSete, minsteBud: b, p: d.pTallbud,
                evBud: d.evTallbud, evPass: d.evPass,
                snittStikk: d.snittStikk, valgtRang: d.valgt.rang))
        }
    }
    defer { MesterAI.budkrok = nil }

    var vakt = 0
    while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
        vakt += 1
        if vakt > 400 { return nil }
        switch engine.phase {
        case .budrunde:
            let sete = engine.aktivBudgiver
            aktivtSete = sete
            let lovlige = engine.lovligeBud(for: sete)
            var bud = mestere[sete].velgBud(engine: engine)
            if !lovlige.contains(bud) { bud = .pass }
            let førAntall = engine.bids.count
            engine.giBud(seat: sete, action: bud)
            // Alle passet -> motoren deler ut på nytt; da er runden ikke
            // sammenliknbar mellom armer, så vi forkaster den.
            if engine.bids.count <= førAntall && engine.phase == .budrunde { return nil }
        case .byttekort:
            let sete = engine.budgiverSeat!
            let antall = engine.rules.antallByttekort
            var vrak = mestere[sete].velgByttekort(engine: engine)
            if vrak.count != antall || !vrak.allSatisfy({ engine.hands[sete].contains($0) }) {
                vrak = reserve[sete].velgByttekort(engine: engine)
            }
            if !engine.kastByttekort(vrak, seat: sete) { return nil }
        case .velgTrumf:
            let sete = engine.budgiverSeat!
            var valg = mestere[sete].velgTrumfOgMakker(engine: engine)
            if valg == nil || !(valg!.1 == nil || engine.kortSomKanØnskes(trumf: valg!.0).contains(valg!.1!)) {
                valg = reserve[sete].velgTrumfOgMakker(engine: engine)
            }
            guard let (suit, ønsket) = valg, engine.velgTrumf(suit: suit, ønsket: ønsket) else { return nil }
        case .spill:
            let sete = engine.aktivSpiller
            let lovlige = engine.lovligeKort(for: sete)
            var kort = mestere[sete].velgKort(engine: engine)
            if kort == nil || !lovlige.contains(kort!) { kort = lovlige[0] }
            if !engine.spill(kort: kort!, seat: sete) { return nil }
        default:
            return nil
        }
    }
    guard let r = engine.sisteRunde else { return nil }
    let lag = [r.budgiver, r.makker].compactMap { $0 }
    return Budrunde(
        frø: frø, førsteBudgiver: førsteBudgiver, budgiver: r.budgiver,
        budRang: r.bud.rang, makker: r.makker ?? -1, klarte: r.klarte,
        lagStikk: lag.reduce(0) { $0 + r.stikkPerSpiller[$1] },
        poeng: r.poengEndring, stikk: r.stikkPerSpiller,
        beslutninger: beslutninger)
}

// MARK: - JSON

private func jsonArr(_ a: [Int]) -> String { "[" + a.map(String.init).joined(separator: ",") + "]" }
private func f(_ x: Double) -> String { String(format: "%.5f", x) }

extension Budrunde {
    func json(arm: String, kjøring: String) -> String {
        var d: [String] = []
        d.append("\"arm\":\"\(arm)\"")
        d.append("\"kjoring\":\"\(kjøring)\"")
        d.append("\"fro\":\(frø)")
        d.append("\"forstebudgiver\":\(førsteBudgiver)")
        d.append("\"budgiver\":\(budgiver)")
        d.append("\"bud\":\(budRang)")
        d.append("\"makker\":\(makker)")
        d.append("\"klarte\":\(klarte)")
        d.append("\"lagstikk\":\(lagStikk)")
        d.append("\"poeng\":\(jsonArr(poeng))")
        d.append("\"stikk\":\(jsonArr(stikk))")
        if !beslutninger.isEmpty {
            let b = beslutninger.map { l in
                "{\"sete\":\(l.sete),\"minstebud\":\(l.minsteBud),\"p\":\(f(l.p))," +
                "\"evbud\":\(f(l.evBud)),\"evpass\":\(f(l.evPass))," +
                "\"snittstikk\":\(f(l.snittStikk)),\"valgt\":\(l.valgtRang)}"
            }.joined(separator: ",")
            d.append("\"beslutninger\":[\(b)]")
        }
        return "{" + d.joined(separator: ",") + "}"
    }
}

/// Skriving med ekte O_APPEND, så mange shards kan dele én fil uten å
/// overskrive hverandre. `FileHandle(forWritingAtPath:)` + `seekToEndOfFile`
/// er IKKE nok: da har hver prosess sin egen forskyvning, og parallelle
/// skrivinger klipper hverandre i stykker.
final class Tilleggsfil {
    private let fd: Int32
    init(_ sti: String) {
        let dir = (sti as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        fd = open(sti, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    }
    func skriv(_ linje: String) {
        guard fd >= 0, let d = (linje + "\n").data(using: .utf8) else { return }
        // Én write(2) per linje: med O_APPEND legges den atomisk bakerst.
        d.withUnsafeBytes { buf in
            var skrevet = 0
            while skrevet < buf.count {
                let n = write(fd, buf.baseAddress!.advanced(by: skrevet), buf.count - skrevet)
                if n <= 0 { break }
                skrevet += n
            }
        }
        fsync(fd)   // VM-en har krasjet før – hold linjene på disk
    }
    deinit { if fd >= 0 { close(fd) } }
}

// MARK: - Kommandoer

func budkalKommando(_ argv: [String]) {
    // budkal <frøStart> <antall> <utfil> <kjøring>
    // 4x MesterAI-selvspill med diagnosekrok på alle budbeslutninger.
    let start = UInt64(argv[2]) ?? 1
    let antall = UInt64(argv[3]) ?? 100
    let fil = Tilleggsfil(argv[4])
    let kjøring = argv.count > 5 ? argv[5] : "k1"
    let konfig = budFastKonfig()
    var n = 0
    for frø in start..<(start + antall) {
        guard let r = budSpillRunde(frø: frø, konfigPerSete: Array(repeating: konfig, count: 4),
                                    samleDiagnose: true) else { continue }
        fil.skriv(r.json(arm: "kalibrering", kjøring: kjøring))
        n += 1
    }
    print("budkal: \(n)/\(antall) runder fra frø \(start)")
}

func budabKommando(_ argv: [String]) {
    // budab <frøStart> <antall> <aggresjon> <verdenerVedBud> <utfil> <arm> <kjøring>
    // Sete 0 kjører armkonfigen, sete 1-3 kjører basiskonfigen.
    let start = UInt64(argv[2]) ?? 1
    let antall = UInt64(argv[3]) ?? 100
    let aggresjon = Double(argv[4]) ?? 0
    let verdenerBud = Int(argv[5]) ?? 64
    let fil = Tilleggsfil(argv[6])
    let arm = argv.count > 7 ? argv[7] : "arm"
    let kjøring = argv.count > 8 ? argv[8] : "k1"

    let basis = budFastKonfig()
    let armKonfig = budFastKonfig(bud: verdenerBud, aggresjon: aggresjon)
    let konfiger = [armKonfig, basis, basis, basis]

    var n = 0
    for frø in start..<(start + antall) {
        guard let r = budSpillRunde(frø: frø, konfigPerSete: konfiger) else { continue }
        fil.skriv(r.json(arm: arm, kjøring: kjøring))
        n += 1
    }
    print("budab \(arm)/\(kjøring): \(n)/\(antall) runder fra frø \(start)")
}
