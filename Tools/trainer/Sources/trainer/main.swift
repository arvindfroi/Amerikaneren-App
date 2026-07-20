import Foundation

#if canImport(Glibc)
import Glibc
#endif
setvbuf(stdout, nil, _IOLBF, 0)   // linjebufret logg, også gjennom pipe/tee

// Treningsharness for NevroHjerne:
//   gen <fil> <frøStart> <matcher>   – destilleringsdata fra MesterAI-selvspill
//   train <datafiler...>             – veiledet trening → vekter.bin
//   rl <matcher> <lr>                – REINFORCE-selvspill (seier i partiet = belønning)
//   eval [runder] [matcher]          – nett-argmax mot 3× vanskelig heuristikk
//   export <ut.swift>                – vekter.bin → innebygd Swift-fil
//   importer <inn.ndjson> <ut.bin> [mennesker|alle]
//                                    – innsamlede partiopptak → datasett
//   syntetisk <ut.ndjson> <frø> <matcher>
//                                    – lag NDJSON-testdata som fra appen

let arg = CommandLine.arguments
let kommando = arg.count > 1 ? arg[1] : "hjelp"
let katalog = FileManager.default.currentDirectoryPath

// MARK: - Datasett

struct BudEks { var x: [Float]; var maske: [Bool]; var valg: Int }
struct ByttEks { var x: [Float]; var holdt: [Int]; var kastet: Set<Int> }
struct SpillEks { var x: [Float]; var maske: [Bool]; var valg: Int }

final class Datasett {
    var bud: [BudEks] = []
    var bytt: [ByttEks] = []
    var spill: [SpillEks] = []

    func skriv(til sti: String) throws {
        var data = Data()
        func i32(_ v: Int) { withUnsafeBytes(of: Int32(v).littleEndian) { data.append(contentsOf: $0) } }
        func floats(_ f: [Float]) { f.withUnsafeBufferPointer { data.append(Data(buffer: $0)) } }
        i32(bud.count)
        for e in bud { floats(e.x); i32(e.valg); i32(e.maske.reduce(0) { ($0 << 1) | ($1 ? 1 : 0) }) }
        i32(bytt.count)
        for e in bytt {
            floats(e.x); i32(e.holdt.count)
            for h in e.holdt { i32(h); i32(e.kastet.contains(h) ? 1 : 0) }
        }
        i32(spill.count)
        for e in spill {
            floats(e.x); i32(e.valg)
            var m: UInt64 = 0
            for (i, ok) in e.maske.enumerated() where ok { m |= 1 << UInt64(i) }
            withUnsafeBytes(of: m.littleEndian) { data.append(contentsOf: $0) }
        }
        try data.write(to: URL(fileURLWithPath: sti))
    }

    func les(fra sti: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: sti))
        var pos = 0
        func i32() -> Int {
            let v = data.subdata(in: pos..<pos + 4).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
            pos += 4
            return Int(Int32(littleEndian: v))
        }
        func u64() -> UInt64 {
            let v = data.subdata(in: pos..<pos + 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
            pos += 8
            return UInt64(littleEndian: v)
        }
        func floats(_ antall: Int) -> [Float] {
            let sub = data.subdata(in: pos..<pos + antall * 4)
            pos += antall * 4
            return sub.withUnsafeBytes { rå in
                (0..<antall).map { Float(bitPattern: UInt32(littleEndian: rå.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
            }
        }
        for _ in 0..<i32() {
            let x = floats(NevroTrekk.budDim)
            let valg = i32()
            let mBits = i32()
            let n = NevroTrekk.budHandlinger.count
            var maske = [Bool](repeating: false, count: n)
            for i in 0..<n { maske[i] = (mBits >> (n - 1 - i)) & 1 == 1 }
            bud.append(BudEks(x: x, maske: maske, valg: valg))
        }
        for _ in 0..<i32() {
            let x = floats(NevroTrekk.byttDim)
            var holdt: [Int] = []
            var kastet = Set<Int>()
            for _ in 0..<i32() {
                let h = i32()
                holdt.append(h)
                if i32() == 1 { kastet.insert(h) }
            }
            bytt.append(ByttEks(x: x, holdt: holdt, kastet: kastet))
        }
        for _ in 0..<i32() {
            let x = floats(NevroTrekk.spillDim)
            let valg = i32()
            let m = u64()
            spill.append(SpillEks(x: x, maske: (0..<52).map { m & (1 << UInt64($0)) != 0 }, valg: valg))
        }
    }
}

// MARK: - Felles spill-løkker

func teacherKonfig() -> MesterKonfig {
    var k = MesterKonfig()
    k.maksVerdener = 12
    k.minVerdener = 6
    k.tidsbudsjett = 0.12
    k.verdenerVedBud = 24
    k.verdenerVedBytte = 12
    k.eksaktStikkGrense = 5
    return k
}

func budIndeks(_ handling: BidAction) -> Int {
    NevroTrekk.budHandlinger.firstIndex(of: handling)!
}

/// Spiller ett helt parti med MesterAI i alle seter og samler beslutninger.
func genererMatch(seed: UInt64, inn datasett: Datasett) {
    let engine = GameEngine()
    let mestere = (0..<4).map { MesterAI(sete: $0, konfig: teacherKonfig(), seed: seed &* 4 &+ UInt64($0) &+ 1) }
    engine.startRunde(seed: seed)
    var vakt = 0
    while engine.phase != .spillFerdig {
        vakt += 1
        if vakt > 6000 { return }
        switch engine.phase {
        case .budrunde:
            let sete = engine.aktivBudgiver
            let x = NevroTrekk.bud(engine: engine, sete: sete)
            let lovlige = engine.lovligeBud(for: sete)
            let bud = mestere[sete].velgBud(engine: engine)
            let maske = NevroTrekk.budHandlinger.map { lovlige.contains($0) }
            datasett.bud.append(BudEks(x: x, maske: maske, valg: budIndeks(bud)))
            guard engine.giBud(seat: sete, action: bud) else { return }
        case .byttekort:
            let sete = engine.budgiverSeat!
            let x = NevroTrekk.bytt(engine: engine, sete: sete)
            let holdt = engine.hands[sete].map(Kortmaske.indeks)
            let vrak = mestere[sete].velgByttekort(engine: engine)
            guard engine.kastByttekort(vrak, seat: sete) else { return }
            datasett.bytt.append(ByttEks(x: x, holdt: holdt, kastet: Set(vrak.map(Kortmaske.indeks))))
        case .velgTrumf:
            let sete = engine.budgiverSeat!
            guard let (suit, kort) = mestere[sete].velgTrumfOgMakker(engine: engine),
                  engine.velgTrumf(suit: suit, ønsket: kort) else { return }
        case .spill:
            let sete = engine.aktivSpiller
            let lovlige = engine.lovligeKort(for: sete)
            if lovlige.count > 1 {
                let x = NevroTrekk.spill(engine: engine, sete: sete)
                guard let kort = mestere[sete].velgKort(engine: engine) else { return }
                var maske = [Bool](repeating: false, count: 52)
                for k in lovlige { maske[Kortmaske.indeks(k)] = true }
                datasett.spill.append(SpillEks(x: x, maske: maske, valg: Kortmaske.indeks(kort)))
                guard engine.spill(kort: kort, seat: sete) else { return }
            } else {
                guard engine.spill(kort: lovlige[0], seat: sete) else { return }
            }
        case .rundeFerdig:
            engine.nesteRunde()
        default:
            return
        }
    }
}

/// Ett parti der alle fire seter spiller med nettene. `sampling` styrer om
/// det trekkes fra softmax (RL) eller spilles argmax. Returnerer vinneren og
/// alle beslutninger per sete.
struct RLBeslutning {
    var hode: Int          // 0 bud, 1 bytt, 2 spill
    var sete: Int
    var x: [Float]
    var maske: [Bool]      // bud/spill
    var valg: Int          // bud/spill
    var holdt: [Int] = []  // bytt
    var kastet: Set<Int> = []
}

func nettMatch(
    hjerne: NevroHjerne, seed: UInt64, sampling: Bool,
    rng: inout SeededGenerator, beslutninger: inout [RLBeslutning]
) -> Int? {
    let engine = GameEngine()
    engine.startRunde(seed: seed)
    var vakt = 0
    let epsilon: Float = sampling ? 0.03 : 0

    func velgIndeks(_ p: [Float], maske: [Bool]) -> Int {
        if sampling {
            if Float.random(in: 0..<1, using: &rng) < epsilon {
                let gyldige = maske.indices.filter { maske[$0] }
                return gyldige.randomElement(using: &rng)!
            }
            return sampleFra(p, rng: &rng)
        }
        var beste = -1
        for i in p.indices where maske[i] && (beste < 0 || p[i] > p[beste]) { beste = i }
        return beste
    }

    while engine.phase != .spillFerdig {
        vakt += 1
        if vakt > 12000 { return nil }
        switch engine.phase {
        case .budrunde:
            let sete = engine.aktivBudgiver
            let lovlige = engine.lovligeBud(for: sete)
            let x = NevroTrekk.bud(engine: engine, sete: sete)
            let maske = NevroTrekk.budHandlinger.map { lovlige.contains($0) }
            let p = maskertSoftmax(hjerne.bud.forover(x), maske: maske)
            let valg = velgIndeks(p, maske: maske)
            beslutninger.append(RLBeslutning(hode: 0, sete: sete, x: x, maske: maske, valg: valg))
            guard engine.giBud(seat: sete, action: NevroTrekk.budHandlinger[valg]) else { return nil }
        case .byttekort:
            let sete = engine.budgiverSeat!
            let x = NevroTrekk.bytt(engine: engine, sete: sete)
            let holdt = engine.hands[sete].map(Kortmaske.indeks)
            var logits = hjerne.bytt.forover(x)
            if sampling {
                for i in 0..<logits.count {
                    logits[i] += Float(gauss(&rng)) * 0.5   // Gumbel-aktig utforsking
                }
            }
            let kast = holdt.sorted { logits[$0] < logits[$1] }.prefix(engine.rules.antallByttekort)
            let vrakKort = kast.map { Kortmaske.kort($0) }
            guard engine.kastByttekort(vrakKort, seat: sete) else { return nil }
            beslutninger.append(RLBeslutning(
                hode: 1, sete: sete, x: x, maske: [], valg: 0,
                holdt: holdt, kastet: Set(kast)
            ))
        case .velgTrumf:
            // Trumfvalget har ikke eget nett: velg fargen med flest kort og
            // be om det høyeste manglende trumfkortet (nil ved solo).
            let sete = engine.budgiverSeat!
            let hånd = engine.hands[sete]
            let farger = Kortmaske.farger.sorted { a, b in
                hånd.filter { $0.suit == a }.count > hånd.filter { $0.suit == b }.count
            }
            var valgt = false
            for farge in farger {
                if engine.erSolo {
                    if engine.velgTrumf(suit: farge, ønsket: nil) { valgt = true; break }
                } else if let ønsket = engine.kortSomKanØnskes(trumf: farge).first,
                          engine.velgTrumf(suit: farge, ønsket: ønsket) {
                    valgt = true; break
                }
            }
            guard valgt else { return nil }
        case .spill:
            let sete = engine.aktivSpiller
            let lovlige = engine.lovligeKort(for: sete)
            if lovlige.count > 1 {
                let x = NevroTrekk.spill(engine: engine, sete: sete)
                var maske = [Bool](repeating: false, count: 52)
                for k in lovlige { maske[Kortmaske.indeks(k)] = true }
                let p = maskertSoftmax(hjerne.spill.forover(x), maske: maske)
                let valg = velgIndeks(p, maske: maske)
                beslutninger.append(RLBeslutning(hode: 2, sete: sete, x: x, maske: maske, valg: valg))
                guard engine.spill(kort: Kortmaske.kort(valg), seat: sete) else { return nil }
            } else {
                guard engine.spill(kort: lovlige[0], seat: sete) else { return nil }
            }
        case .rundeFerdig:
            engine.nesteRunde()
        default:
            return nil
        }
    }
    return engine.vinnerSeat
}

// MARK: - Kommandoer

switch kommando {
case "gen":
    let fil = arg[2]
    let frøStart = UInt64(arg[3])!
    let matcher = Int(arg[4])!
    let datasett = Datasett()
    let start = Date()
    for i in 0..<matcher {
        genererMatch(seed: frøStart &+ UInt64(i), inn: datasett)
        if (i + 1) % 10 == 0 {
            let tid = Date().timeIntervalSince(start)
            print("\(fil): \(i + 1)/\(matcher) matcher, \(datasett.spill.count) spilleks, \(Int(tid)) s")
        }
    }
    try datasett.skriv(til: fil)
    print("Skrev \(fil): bud=\(datasett.bud.count) bytt=\(datasett.bytt.count) spill=\(datasett.spill.count)")

case "syntetisk":
    // syntetisk <ut.ndjson> <frø> <matcher>
    // Spiller hele partier med heuristiske AI-er og skriver dem som
    // NDJSON-partiopptak – nøyaktig formatet appen sender og backendens
    // /v1/eksport leverer. Brukes til å teste hele pipelinen.
    let utFil = arg[2]
    let frøStart = UInt64(arg[3])!
    let matcher = Int(arg[4])!
    let koder = JSONEncoder()
    var linjer: [String] = []
    for m in 0..<matcher {
        let engine = GameEngine()
        let ai = (0..<4).map { AIPlayer(seat: $0, difficulty: $0 == 0 ? .president : .vanskelig,
                                        personality: .balansert) }
        engine.startRunde(seed: frøStart &+ UInt64(m) &* 977)
        var opptak: [Rundeopptak] = []
        var vakt = 0
        løkke: while engine.phase != .spillFerdig {
            vakt += 1
            if vakt > 8000 { break løkke }
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                guard engine.giBud(seat: sete, action: ai[sete].velgBud(engine: engine)) else { break løkke }
            case .byttekort:
                let sete = engine.budgiverSeat!
                if !engine.kastByttekort(ai[sete].velgByttekort(engine: engine), seat: sete) {
                    engine.kastByttekort(Array(engine.hands[sete].suffix(4)), seat: sete)
                }
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                if let (suit, kort) = ai[sete].velgTrumfOgMakker(engine: engine),
                   engine.velgTrumf(suit: suit, ønsket: kort) { break }
                for suit in Suit.allCases {
                    if let kort = engine.kortSomKanØnskes(trumf: suit).first,
                       engine.velgTrumf(suit: suit, ønsket: kort) { break }
                    if engine.erSolo, engine.velgTrumf(suit: suit, ønsket: nil) { break }
                }
            case .spill:
                let sete = engine.aktivSpiller
                let kort = ai[sete].velgKort(engine: engine) ?? engine.lovligeKort(for: sete)[0]
                guard engine.spill(kort: kort, seat: sete) else { break løkke }
                if engine.phase == .rundeFerdig || engine.phase == .spillFerdig,
                   let runde = Rundeopptak(fra: engine) {
                    opptak.append(runde)
                }
            case .rundeFerdig:
                engine.nesteRunde()
            default:
                break løkke
            }
        }
        guard engine.phase == .spillFerdig, !opptak.isEmpty else { continue }
        let parti = Partiopptak(
            regler: engine.rules, modus: "syntetisk",
            seter: [Seteinfo(menneske: true, cpuNivå: nil)]
                + (1...3).map { _ in Seteinfo(menneske: false, cpuNivå: "Vanskelig") },
            runder: opptak, sluttPoeng: engine.scores, vinner: engine.vinnerSeat
        )
        linjer.append(String(data: try koder.encode(parti), encoding: .utf8)!)
        print("parti \(m + 1)/\(matcher): \(opptak.count) runder")
    }
    try (linjer.joined(separator: "\n") + "\n")
        .write(toFile: utFil, atomically: true, encoding: .utf8)
    print("Skrev \(linjer.count) partier til \(utFil)")

case "importer":
    // importer <inn.ndjson> <ut.bin> [mennesker|alle]
    // Leser innsamlede Partiopptak (NDJSON fra backendens /v1/eksport),
    // spiller av hvert parti gjennom den ekte motoren (full
    // regelverifisering) og skriver (situasjon → fasit)-par som
    // treningsdatasett. Standard høstes bare valg fra mennesker og
    // President-CPU-er – svake CPU-ers valg er støy, ikke fasit.
    let innFil = arg[2]
    let utFil = arg[3]
    let kilde = arg.count > 4 ? arg[4] : "mennesker"
    let datasett = Datasett()
    var partier = 0, avvist = 0, runder = 0
    var setevalg = 0

    let dekoder = JSONDecoder()
    let innhold = try String(contentsOfFile: innFil, encoding: .utf8)
    for linje in innhold.split(separator: "\n") where !linje.isEmpty {
        guard let parti = try? dekoder.decode(Partiopptak.self, from: Data(linje.utf8)) else {
            avvist += 1
            continue
        }
        let høstSete: (Int) -> Bool = { sete in
            guard kilde != "alle" else { return true }
            guard parti.seter.indices.contains(sete) else { return false }
            return parti.seter[sete].menneske || parti.seter[sete].cpuNivå == "President"
        }
        var partiOK = true
        var nye: (bud: [BudEks], bytt: [ByttEks], spill: [SpillEks]) = ([], [], [])
        for runde in parti.runder {
            do {
                try runde.spillAv(regler: parti.regler) { motor, valg in
                    switch valg {
                    case .bud(let sete, let handling):
                        guard høstSete(sete) else { return }
                        let maske = NevroTrekk.budHandlinger.map { motor.lovligeBud(for: sete).contains($0) }
                        nye.bud.append(BudEks(x: NevroTrekk.bud(engine: motor, sete: sete),
                                              maske: maske, valg: budIndeks(handling)))
                    case .vrak(let sete, let kort):
                        guard høstSete(sete) else { return }
                        nye.bytt.append(ByttEks(x: NevroTrekk.bytt(engine: motor, sete: sete),
                                                holdt: motor.hands[sete].map(Kortmaske.indeks),
                                                kastet: Set(kort.map(Kortmaske.indeks))))
                    case .trumfvalg:
                        break   // ikke eget nett-hode (ennå)
                    case .spill(let sete, let kort):
                        guard høstSete(sete) else { return }
                        let lovlige = motor.lovligeKort(for: sete)
                        guard lovlige.count > 1 else { return }
                        var maske = [Bool](repeating: false, count: 52)
                        for k in lovlige { maske[Kortmaske.indeks(k)] = true }
                        nye.spill.append(SpillEks(x: NevroTrekk.spill(engine: motor, sete: sete),
                                                  maske: maske, valg: Kortmaske.indeks(kort)))
                    }
                }
                runder += 1
            } catch {
                print("avviste parti \(parti.id): \(error)")
                partiOK = false
                break
            }
        }
        // Alt eller ingenting per parti: ett ugyldig opptak skal ikke
        // bidra med et eneste eksempel.
        if partiOK {
            partier += 1
            setevalg += parti.seter.filter(\.menneske).count
            datasett.bud += nye.bud
            datasett.bytt += nye.bytt
            datasett.spill += nye.spill
        } else {
            avvist += 1
        }
    }
    try datasett.skriv(til: utFil)
    print("Importerte \(partier) partier (\(runder) runder, \(setevalg) menneskeseter), avviste \(avvist)")
    print("Skrev \(utFil): bud=\(datasett.bud.count) bytt=\(datasett.bytt.count) spill=\(datasett.spill.count)")

case "train":
    let datasett = Datasett()
    for fil in arg.dropFirst(2) { try datasett.les(fra: fil) }

    // Fargesymmetri-augmentering: permuter fargeblokkene (4×13) i et
    // 52-dims segment, og tilsvarende kortindekser/masker/etiketter.
    func permuterBlokk(_ x: inout [Float], basis: Int, perm: [Int]) {
        var ny = [Float](repeating: 0, count: 52)
        for f in 0..<4 {
            for v in 0..<13 { ny[perm[f] * 13 + v] = x[basis + f * 13 + v] }
        }
        for i in 0..<52 { x[basis + i] = ny[i] }
    }
    func permuterIndeks(_ i: Int, perm: [Int]) -> Int { perm[i / 13] * 13 + i % 13 }
    var augRng = SeededGenerator(seed: 31337)
    let utenAug = ProcessInfo.processInfo.environment["UTEN_AUG"] != nil
    func tilfeldigPerm() -> [Int] { [0, 1, 2, 3].shuffled(using: &augRng) }
    print("Datasett: bud=\(datasett.bud.count) bytt=\(datasett.bytt.count) spill=\(datasett.spill.count)")
    var rng = SeededGenerator(seed: 7)
    let budNett = TreneNett(dims: [NevroTrekk.budDim, 64, 48, NevroTrekk.budHandlinger.count], rng: &rng)
    let byttNett = TreneNett(dims: [NevroTrekk.byttDim, 96, 64, 52], rng: &rng)
    let spillNett = TreneNett(dims: [NevroTrekk.spillDim, 192, 128, 52], rng: &rng)

    func trenKlassifisering(_ nett: TreneNett, x: [[Float]], maske: [[Bool]], valg: [Int],
                            epoker: Int, navn: String) {
        let n = x.count
        guard n > 0 else { return }
        let testN = max(1, n / 20)
        var indekser = Array(0..<n)
        for epoke in 0..<epoker {
            indekser.shuffle(using: &rng)
            let lr: Float = epoke < 2 ? 1e-3 : 5e-4
            var batch = 0
            for i in indekser.dropFirst(testN) {
                let akt = nett.forover(x[i])
                var d = maskertSoftmax(akt.last!, maske: maske[i])
                d[valg[i]] -= 1
                nett.tilbake(aktiveringer: akt, dLogits: d)
                batch += 1
                if batch == 128 { nett.adamSteg(lr: lr, batch: batch); batch = 0 }
            }
            if batch > 0 { nett.adamSteg(lr: lr, batch: batch) }
            var riktig = 0
            for i in indekser.prefix(testN) {
                let logits = nett.forover(x[i]).last!
                var beste = -1
                for j in logits.indices where maske[i][j] && (beste < 0 || logits[j] > logits[beste]) { beste = j }
                if beste == valg[i] { riktig += 1 }
            }
            print("\(navn) epoke \(epoke + 1): testtreff \(riktig)/\(testN)")
        }
    }

    var budX = datasett.bud.map(\.x)
    for i in budX.indices where !utenAug && i % 2 == 1 {
        permuterBlokk(&budX[i], basis: 0, perm: tilfeldigPerm())
    }
    trenKlassifisering(budNett, x: budX, maske: datasett.bud.map(\.maske),
                       valg: datasett.bud.map(\.valg), epoker: 6, navn: "bud")

    // Bytt: binær «behold»-klassifisering per kort på hånden.
    for i in datasett.bytt.indices where !utenAug && i % 2 == 1 {
        let perm = tilfeldigPerm()
        permuterBlokk(&datasett.bytt[i].x, basis: 0, perm: perm)
        datasett.bytt[i].holdt = datasett.bytt[i].holdt.map { permuterIndeks($0, perm: perm) }
        datasett.bytt[i].kastet = Set(datasett.bytt[i].kastet.map { permuterIndeks($0, perm: perm) })
    }
    do {
        let n = datasett.bytt.count
        let testN = max(1, n / 20)
        var indekser = Array(0..<n)
        for epoke in 0..<6 {
            indekser.shuffle(using: &rng)
            var batch = 0
            for i in indekser.dropFirst(testN) {
                let e = datasett.bytt[i]
                let akt = byttNett.forover(e.x)
                var d = [Float](repeating: 0, count: 52)
                for h in e.holdt {
                    let sig = 1 / (1 + exp(-akt.last![h]))
                    d[h] = sig - (e.kastet.contains(h) ? 0 : 1)
                }
                byttNett.tilbake(aktiveringer: akt, dLogits: d)
                batch += 1
                if batch == 128 { byttNett.adamSteg(lr: 1e-3, batch: batch); batch = 0 }
            }
            if batch > 0 { byttNett.adamSteg(lr: 1e-3, batch: batch) }
            var riktig = 0
            var totalt = 0
            for i in indekser.prefix(testN) {
                let e = datasett.bytt[i]
                let logits = byttNett.forover(e.x).last!
                let kast = Set(e.holdt.sorted { logits[$0] < logits[$1] }.prefix(e.kastet.count))
                riktig += kast.intersection(e.kastet).count
                totalt += e.kastet.count
            }
            print("bytt epoke \(epoke + 1): vraktreff \(riktig)/\(totalt)")
        }
    }

    var spillX = datasett.spill.map(\.x)
    var spillMaske = datasett.spill.map(\.maske)
    var spillValg = datasett.spill.map(\.valg)
    for i in spillX.indices where !utenAug && i % 2 == 1 {
        let perm = tilfeldigPerm()
        for basis in [0, 52, 104, 156] { permuterBlokk(&spillX[i], basis: basis, perm: perm) }
        var trumf = [Float](repeating: 0, count: 4)
        for f in 0..<4 { trumf[perm[f]] = spillX[i][220 + f] }
        for f in 0..<4 { spillX[i][220 + f] = trumf[f] }
        var maske = [Bool](repeating: false, count: 52)
        for k in 0..<52 where spillMaske[i][k] { maske[permuterIndeks(k, perm: perm)] = true }
        spillMaske[i] = maske
        spillValg[i] = permuterIndeks(spillValg[i], perm: perm)
    }
    trenKlassifisering(spillNett, x: spillX, maske: spillMaske,
                       valg: spillValg, epoker: 4, navn: "spill")

    let hjerne = NevroHjerne(bud: budNett.somNevroNett, bytt: byttNett.somNevroNett, spill: spillNett.somNevroNett)
    try hjerne.somData.write(to: URL(fileURLWithPath: "vekter.bin"))
    print("Skrev vekter.bin (\(hjerne.somData.count) byte)")

case "rl":
    let matcher = Int(arg[2])!
    let lr = Float(arg[3])!
    let startFil = arg.count > 4 ? arg[4] : "vekter.bin"
    let anker = arg.count > 5 ? Float(arg[5]) ?? 0 : 0
    let data = try Data(contentsOf: URL(fileURLWithPath: startFil))
    guard let startHjerne = NevroHjerne.fra(data: data) else { fatalError("Klarte ikke lese \(startFil)") }
    if anker > 0 { print("Destillasjonsanker aktivt: beta=\(anker)") }
    let budNett = TreneNett(fra: startHjerne.bud)
    let byttNett = TreneNett(fra: startHjerne.bytt)
    let spillNett = TreneNett(fra: startHjerne.spill)
    // Verdihode (kun for trening): P(vinne partiet | spilletilstand) brukes
    // som baseline for kortvalgene – langt lavere varians enn en konstant.
    var vrng = SeededGenerator(seed: 999)
    let verdiNett: TreneNett
    if let vd = try? Data(contentsOf: URL(fileURLWithPath: "verdinett.bin")),
       let lagret = NevroHjerne.fra(data: vd) {
        verdiNett = TreneNett(fra: lagret.spill)   // gjenbruker container-formatet
    } else {
        verdiNett = TreneNett(dims: [NevroTrekk.spillDim, 96, 1], rng: &vrng)
    }
    var rng = SeededGenerator(seed: 4242)
    var ferdige = 0
    let batchStørrelse = 8
    let start = Date()

    /// Deterministisk fremdriftsmåling: kandidaten i sete 0 mot tre FROSNE
    /// kopier av startnettet, argmax mot argmax på faste utdelinger – null
    /// målestøy, så evalueringene er direkte sammenlignbare.
    func evaluer(_ hjerne: NevroHjerne, runder: Int) -> Double {
        var sum = 0
        var utenSvar = 0
        for seed in 1...UInt64(runder) {
            let engine = GameEngine()
            engine.startRunde(seed: 900_000 &+ seed)
            let kandidat = NevroSpiller(sete: 0, hjerne: hjerne)
            func spiller(_ sete: Int) -> NevroSpiller {
                sete == 0 ? kandidat : NevroSpiller(sete: sete, hjerne: startHjerne)
            }
            var vakt = 0
            løkke: while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
                vakt += 1
                if vakt > 500 { utenSvar += 1; break }
                switch engine.phase {
                case .budrunde:
                    let sete = engine.aktivBudgiver
                    guard engine.giBud(seat: sete, action: spiller(sete).velgBud(engine: engine)) else { break løkke }
                case .byttekort:
                    let sete = engine.budgiverSeat!
                    guard engine.kastByttekort(spiller(sete).velgByttekort(engine: engine), seat: sete) else { break løkke }
                case .velgTrumf:
                    let sete = engine.budgiverSeat!
                    var valgt = false
                    if engine.erSolo {
                        valgt = engine.velgTrumf(suit: .spar, ønsket: nil)
                    } else {
                        for suit in Suit.allCases {
                            if let ø = engine.kortSomKanØnskes(trumf: suit).first,
                               engine.velgTrumf(suit: suit, ønsket: ø) { valgt = true; break }
                        }
                    }
                    guard valgt else { break løkke }
                case .spill:
                    let sete = engine.aktivSpiller
                    guard let kort = spiller(sete).velgKort(engine: engine),
                          engine.spill(kort: kort, seat: sete) else { break løkke }
                default:
                    break løkke
                }
            }
            sum += engine.sisteRunde?.poengEndring[0] ?? 0
        }
        if utenSvar > 0 { print("  (\(utenSvar) runder uten svar)") }
        return Double(sum) / Double(runder)
    }

    var besteSnitt = evaluer(startHjerne, runder: 300)
    print(String(format: "RL start: %.2f poeng/runde mot vanskelig (baseline)", besteSnitt))
    var besteData = data
    var sisteEval = 0

    while ferdige < matcher {
        var batchBeslutninger: [[RLBeslutning]] = []
        var belønninger: [[Double]] = []
        for _ in 0..<batchStørrelse {
            var beslutninger: [RLBeslutning] = []
            let hjerne = NevroHjerne(bud: budNett.somNevroNett, bytt: byttNett.somNevroNett, spill: spillNett.somNevroNett)
            let seed = UInt64.random(in: 1...UInt64.max >> 1, using: &rng)
            guard let vinner = nettMatch(hjerne: hjerne, seed: seed, sampling: true,
                                         rng: &rng, beslutninger: &beslutninger) else { continue }
            var r = [Double](repeating: 0, count: 4)
            r[vinner] = 1
            batchBeslutninger.append(beslutninger)
            belønninger.append(r)
            ferdige += 1
        }

        var antallGrad = 0
        for (beslutninger, r) in zip(batchBeslutninger, belønninger) {
            for b in beslutninger {
                let utfall = Float(r[b.sete])
                switch b.hode {
                case 0:
                    let adv = utfall - 0.25
                    if adv == 0 { continue }
                    let akt = budNett.forover(b.x)
                    let pNå = maskertSoftmax(akt.last!, maske: b.maske)
                    var d = pNå
                    d[b.valg] -= 1
                    for i in d.indices { d[i] *= adv }
                    if anker > 0 {
                        let p0 = maskertSoftmax(startHjerne.bud.forover(b.x), maske: b.maske)
                        for i in d.indices { d[i] += anker * (pNå[i] - p0[i]) }
                    }
                    budNett.tilbake(aktiveringer: akt, dLogits: d)
                case 1:
                    let adv = utfall - 0.25
                    if adv == 0 { continue }
                    let akt = byttNett.forover(b.x)
                    var d = [Float](repeating: 0, count: 52)
                    for h in b.holdt {
                        let sig = 1 / (1 + exp(-akt.last![h]))
                        d[h] = adv * (sig - (b.kastet.contains(h) ? 0 : 1))
                    }
                    byttNett.tilbake(aktiveringer: akt, dLogits: d)
                default:
                    // Verdibaseline: adv = utfall − σ(verdi(tilstand)).
                    let vAkt = verdiNett.forover(b.x)
                    let v = 1 / (1 + exp(-vAkt.last![0]))
                    let adv = utfall - v
                    let akt = spillNett.forover(b.x)
                    let pNå = maskertSoftmax(akt.last!, maske: b.maske)
                    var d = pNå
                    d[b.valg] -= 1
                    for i in d.indices { d[i] *= adv }
                    if anker > 0 {
                        let p0 = maskertSoftmax(startHjerne.spill.forover(b.x), maske: b.maske)
                        for i in d.indices { d[i] += anker * (pNå[i] - p0[i]) }
                    }
                    spillNett.tilbake(aktiveringer: akt, dLogits: d)
                    // Tren verdihodet mot det faktiske utfallet (BCE).
                    verdiNett.tilbake(aktiveringer: vAkt, dLogits: [v - utfall])
                }
                antallGrad += 1
            }
        }
        budNett.adamSteg(lr: lr, batch: antallGrad)
        byttNett.adamSteg(lr: lr, batch: antallGrad)
        spillNett.adamSteg(lr: lr, batch: antallGrad)
        verdiNett.adamSteg(lr: 3e-4, batch: antallGrad)

        if ferdige - sisteEval >= 600 {
            sisteEval = ferdige
            let hjerne = NevroHjerne(bud: budNett.somNevroNett, bytt: byttNett.somNevroNett, spill: spillNett.somNevroNett)
            // Ubetinget sjekkpunkt + verdihodet, så en avbrutt kjøring
            // alltid kan plukkes opp igjen.
            try hjerne.somData.write(to: URL(fileURLWithPath: "vekter-siste.bin"))
            let vContainer = NevroHjerne(bud: verdiNett.somNevroNett, bytt: verdiNett.somNevroNett, spill: verdiNett.somNevroNett)
            try vContainer.somData.write(to: URL(fileURLWithPath: "verdinett.bin"))
            let snitt = evaluer(hjerne, runder: 250)
            let tid = Int(Date().timeIntervalSince(start))
            print(String(format: "RL %d matcher (%d s): %.2f poeng/runde", ferdige, tid, snitt))
            if snitt > besteSnitt {
                besteSnitt = snitt
                besteData = hjerne.somData
                try besteData.write(to: URL(fileURLWithPath: "vekter-beste.bin"))
                print("  ny beste – lagret vekter-beste.bin")
            }
        }
    }
    try besteData.write(to: URL(fileURLWithPath: "vekter-beste.bin"))
    print(String(format: "RL ferdig: beste %.2f poeng/runde", besteSnitt))

case "eval":
    let runder = arg.count > 2 ? Int(arg[2])! : 300
    let fil = arg.count > 3 ? arg[3] : "vekter-beste.bin"
    let data = try Data(contentsOf: URL(fileURLWithPath: fil))
    guard let hjerne = NevroHjerne.fra(data: data) else { fatalError("Klarte ikke lese \(fil)") }

    var sum = 0
    var somBudgiver = (0, 0), somForsvar = (0, 0)
    var makkerRunder = 0
    for seed in 1...UInt64(runder) {
        let engine = GameEngine()
        engine.startRunde(seed: 500_000 &+ seed)
        let ai = (1...3).map { AIPlayer(seat: $0, difficulty: .vanskelig, personality: .balansert) }
        let nett = NevroSpiller(sete: 0, hjerne: hjerne)
        var vakt = 0
        løkke: while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
            vakt += 1
            if vakt > 500 { break }
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                let bud = sete == 0 ? nett.velgBud(engine: engine) : ai[sete - 1].velgBud(engine: engine)
                guard engine.giBud(seat: sete, action: bud) else { break løkke }
            case .byttekort:
                let sete = engine.budgiverSeat!
                let vrak = sete == 0 ? nett.velgByttekort(engine: engine) : ai[sete - 1].velgByttekort(engine: engine)
                guard engine.kastByttekort(vrak, seat: sete) else { break løkke }
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                let valg = sete == 0
                    ? AIPlayer(seat: 0, difficulty: .vanskelig, personality: .balansert).velgTrumfOgMakker(engine: engine)
                    : ai[sete - 1].velgTrumfOgMakker(engine: engine)
                guard let (suit, kort) = valg, engine.velgTrumf(suit: suit, ønsket: kort) else { break løkke }
            case .spill:
                let sete = engine.aktivSpiller
                let kort = sete == 0 ? nett.velgKort(engine: engine) : ai[sete - 1].velgKort(engine: engine)
                guard let kort, engine.spill(kort: kort, seat: sete) else { break løkke }
            default:
                break løkke
            }
        }
        guard let runde = engine.sisteRunde else { continue }
        sum += runde.poengEndring[0]
        if runde.budgiver == 0 {
            somBudgiver.0 += 1
            if runde.klarte { somBudgiver.1 += 1 }
        } else if runde.makker == 0 {
            makkerRunder += 1
        } else {
            somForsvar.0 += 1
            if !runde.klarte { somForsvar.1 += 1 }
        }
    }
    print(String(format: "Nett-argmax mot 3× vanskelig over %d runder: %.2f poeng/runde", runder, Double(sum) / Double(runder)))
    print("  budgiver \(somBudgiver.0) (klarte \(somBudgiver.1)), makker \(makkerRunder), forsvar \(somForsvar.0) (felte \(somForsvar.1))")

case "export":
    let ut = arg[2]
    let fil = arg.count > 3 ? arg[3] : "vekter-beste.bin"
    let data = try Data(contentsOf: URL(fileURLWithPath: fil))
    guard NevroHjerne.fra(data: data) != nil else { fatalError("Ugyldige vekter i \(fil)") }
    let base64 = data.base64EncodedString()
    var linjer: [String] = []
    var i = base64.startIndex
    while i < base64.endIndex {
        let slutt = base64.index(i, offsetBy: 4000, limitedBy: base64.endIndex) ?? base64.endIndex
        linjer.append(String(base64[i..<slutt]))
        i = slutt
    }
    let deler = linjer.map { "        \"\($0)\"," }.joined(separator: "\n")
    let kilde = """
    import Foundation

    /// Innebygde vekter for `NevroHjerne`, generert av treningsharnessen
    /// (destillering fra MesterAI + selvspill-REINFORCE med partiseier som
    /// belønning). Regenereres av `trainer export` – ikke rediger for hånd.
    enum NevroVekter {
        private static let deler: [String] = [
    \(deler)
        ]
        static let base64 = deler.joined()
    }

    """
    try kilde.write(toFile: ut, atomically: true, encoding: .utf8)
    print("Skrev \(ut) (\(data.count) byte vekter)")

default:
    print("Kommandoer: gen | train | rl | eval | export")
}
