import Foundation

/// Et lite nevralt nett i ren Swift: tette lag med ReLU, raskt nok til at
/// inferens tar mikrosekunder på telefonen. Vektene trenes offline
/// (destillering fra MesterAI + selvspill-forsterkningslæring med seier i
/// hele partiet som belønning) og skipes innebygd i appen.
struct NevroLag {
    let inn: Int
    let ut: Int
    var vekter: [Float]   // ut × inn, radvis
    var bias: [Float]

    func forover(_ x: [Float], relu: Bool) -> [Float] {
        var y = bias
        vekter.withUnsafeBufferPointer { w in
            x.withUnsafeBufferPointer { xv in
                y.withUnsafeMutableBufferPointer { yv in
                    for r in 0..<ut {
                        var sum: Float = 0
                        let rad = r * inn
                        for c in 0..<inn {
                            sum += w[rad + c] * xv[c]
                        }
                        yv[r] += sum
                    }
                }
            }
        }
        if relu {
            for i in 0..<ut where y[i] < 0 { y[i] = 0 }
        }
        return y
    }
}

/// Flerlags perseptron: ReLU på alle lag unntatt det siste (logits).
struct NevroNett {
    var lag: [NevroLag]

    func forover(_ x: [Float]) -> [Float] {
        var a = x
        for (i, l) in lag.enumerated() {
            a = l.forover(a, relu: i < lag.count - 1)
        }
        return a
    }
}

/// De tre nettene: bud, byttekort-vrak og kortspill.
struct NevroHjerne {
    var bud: NevroNett
    var bytt: NevroNett
    var spill: NevroNett

    /// Det innebygde, ferdigtrente nettet – nil om vektene mangler.
    static let delt: NevroHjerne? = NevroVekter.base64.isEmpty
        ? nil
        : Data(base64Encoded: NevroVekter.base64).flatMap { fra(data: $0) }

    // MARK: - Serialisering (Int32/Float32 little-endian)

    var somData: Data {
        var data = Data()
        func skriv(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let nett = [bud, bytt, spill]
        skriv(Int32(nett.count))
        for n in nett {
            skriv(Int32(n.lag.count))
            for l in n.lag {
                skriv(Int32(l.inn))
                skriv(Int32(l.ut))
                l.vekter.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
                l.bias.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
            }
        }
        return data
    }

    static func fra(data: Data) -> NevroHjerne? {
        var pos = 0
        func lesInt() -> Int? {
            guard pos + 4 <= data.count else { return nil }
            let v = data.subdata(in: pos..<pos + 4).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
            pos += 4
            return Int(Int32(littleEndian: v))
        }
        func lesFloats(_ antall: Int) -> [Float]? {
            guard pos + antall * 4 <= data.count else { return nil }
            let sub = data.subdata(in: pos..<pos + antall * 4)
            pos += antall * 4
            return sub.withUnsafeBytes { rå in
                (0..<antall).map { Float(bitPattern: UInt32(littleEndian: rå.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
            }
        }
        guard let antallNett = lesInt(), antallNett == 3 else { return nil }
        var nett: [NevroNett] = []
        for _ in 0..<3 {
            guard let antallLag = lesInt() else { return nil }
            var lag: [NevroLag] = []
            for _ in 0..<antallLag {
                guard let inn = lesInt(), let ut = lesInt(),
                      let vekter = lesFloats(inn * ut), let bias = lesFloats(ut) else { return nil }
                lag.append(NevroLag(inn: inn, ut: ut, vekter: vekter, bias: bias))
            }
            nett.append(NevroNett(lag: lag))
        }
        return NevroHjerne(bud: nett[0], bytt: nett[1], spill: nett[2])
    }
}

/// Trekkuttrekk for nettene. Bruker BARE informasjon setet lovlig har –
/// samme grense som `Spillinnsikt`: egen hånd, spilte kort, meldinger,
/// avslørt makker og poengstillingen. Alt kodes relativt til eget sete.
enum NevroTrekk {
    static let budDim = 64
    static let byttDim = 58
    static let spillDim = 237

    /// Budhandlingene nettet kan velge mellom (maskeres mot lovlige bud).
    static let budHandlinger: [BidAction] = [.pass] + (5...13).map { BidAction.bud($0) } + [.amerikaner]

    private static func settKort(_ v: inout [Float], _ basis: Int, _ kort: [Card]) {
        for k in kort { v[basis + Kortmaske.indeks(k)] = 1 }
    }

    private static func rel(_ sete: Int, _ annet: Int) -> Int { (annet - sete + 4) % 4 }

    static func bud(engine: GameEngine, sete: Int) -> [Float] {
        var v = [Float](repeating: 0, count: budDim)
        settKort(&v, 0, engine.hands[sete])
        let lovlige = engine.lovligeBud(for: sete)
        let minste = lovlige.compactMap { a -> Int? in
            if case .bud(let n) = a { return n }
            return nil
        }.min() ?? 0
        v[52] = Float(minste) / 13
        if let høyeste = engine.høyesteBud {
            v[53] = Float(max(0, høyeste.action.rang == 1000 ? 13 : høyeste.action.rang)) / 13
            v[54 + rel(sete, høyeste.seat)] = 1
        }
        v[58] = Float(engine.harPasset.count) / 3
        v[59] = Float(min(engine.scores[sete], engine.rules.målPoeng)) / Float(engine.rules.målPoeng)
        let maksAndre = (0..<4).filter { $0 != sete }.map { engine.scores[$0] }.max() ?? 0
        v[60] = Float(min(maksAndre, engine.rules.målPoeng)) / Float(engine.rules.målPoeng)
        v[61] = engine.rules.medByttekort ? 1 : 0
        v[62] = Float(engine.rules.kortPerSpiller) / 13
        v[63] = 1   // bias-inngang
        return v
    }

    static func bytt(engine: GameEngine, sete: Int) -> [Float] {
        var v = [Float](repeating: 0, count: byttDim)
        settKort(&v, 0, engine.hands[sete])
        if case .bud(let n)? = engine.høyesteBud?.action { v[52] = Float(n) / 13 }
        v[53] = engine.erAmerikaner ? 1 : 0
        v[54] = Float(min(engine.scores[sete], engine.rules.målPoeng)) / Float(engine.rules.målPoeng)
        let maksAndre = (0..<4).filter { $0 != sete }.map { engine.scores[$0] }.max() ?? 0
        v[55] = Float(min(maksAndre, engine.rules.målPoeng)) / Float(engine.rules.målPoeng)
        v[56] = Float(engine.rules.kortPerSpiller) / 13
        v[57] = 1
        return v
    }

    static func spill(engine: GameEngine, sete: Int) -> [Float] {
        var v = [Float](repeating: 0, count: spillDim)
        settKort(&v, 0, engine.hands[sete])
        settKort(&v, 52, engine.spilteKort)
        settKort(&v, 104, engine.currentTrick.map(\.card))
        if let ønsket = engine.ønsketKort, !engine.makkerAvslørt {
            v[156 + Kortmaske.indeks(ønsket)] = 1
        }
        if let budgiver = engine.budgiverSeat { v[208 + rel(sete, budgiver)] = 1 }
        let leder = engine.currentTrick.first?.seat ?? engine.aktivSpiller
        v[212 + rel(sete, leder)] = 1
        // Makker slik setet kjenner den: avslørt for alle, eller meg selv.
        if engine.makkerAvslørt, let makker = engine.makkerSeat {
            v[216 + rel(sete, makker)] = 1
        } else if engine.makkerSeat == sete {
            v[216] = 1
        }
        if let trumf = engine.trumf {
            v[220 + Kortmaske.fargeIndeks(trumf)] = 1
        } else {
            v[224] = 1
        }
        if case .bud(let n)? = engine.høyesteBud?.action { v[225] = Float(n) / 13 }
        v[226] = engine.erAmerikaner ? 1 : 0
        v[227] = (sete == engine.budgiverSeat || engine.makkerSeat == sete) ? 1 : 0
        v[228] = Float(engine.trickNummer) / Float(max(1, engine.rules.kortPerSpiller))
        v[229] = Float(engine.stikkTatt[sete]) / 13
        var lagStikk = engine.budgiverSeat.map { engine.stikkTatt[$0] } ?? 0
        if engine.makkerAvslørt, let makker = engine.makkerSeat { lagStikk += engine.stikkTatt[makker] }
        v[230] = Float(lagStikk) / 13
        v[231] = Float(min(engine.scores[sete], engine.rules.målPoeng)) / Float(engine.rules.målPoeng)
        let maksAndre = (0..<4).filter { $0 != sete }.map { engine.scores[$0] }.max() ?? 0
        v[232] = Float(min(maksAndre, engine.rules.målPoeng)) / Float(engine.rules.målPoeng)
        for s in 0..<4 {
            v[233 + rel(sete, s)] = Float(engine.stikkTatt[s]) / 13
        }
        return v
    }
}

/// Ren nettspiller: alle beslutninger tas med ett nettoppslag (argmax over
/// lovlige handlinger). Brukes i trening/benchmark – og av MesterAI som
/// kandidatgenerator for vrak.
struct NevroSpiller {
    let sete: Int
    let hjerne: NevroHjerne

    func velgBud(engine: GameEngine) -> BidAction {
        let lovlige = engine.lovligeBud(for: sete)
        guard !lovlige.isEmpty else { return .pass }
        let logits = hjerne.bud.forover(NevroTrekk.bud(engine: engine, sete: sete))
        var beste = BidAction.pass
        var besteLogit = -Float.infinity
        for (i, handling) in NevroTrekk.budHandlinger.enumerated() where lovlige.contains(handling) {
            if logits[i] > besteLogit {
                besteLogit = logits[i]
                beste = handling
            }
        }
        return beste
    }

    func velgByttekort(engine: GameEngine) -> [Card] {
        let hånd = engine.hands[sete]
        let antall = engine.rules.antallByttekort
        guard antall > 0, hånd.count > antall else { return [] }
        let beholdLogits = hjerne.bytt.forover(NevroTrekk.bytt(engine: engine, sete: sete))
        return hånd
            .sorted { beholdLogits[Kortmaske.indeks($0)] < beholdLogits[Kortmaske.indeks($1)] }
            .prefix(antall)
            .map { $0 }
    }

    func velgKort(engine: GameEngine) -> Card? {
        let lovlige = engine.lovligeKort(for: sete)
        guard !lovlige.isEmpty else { return nil }
        if lovlige.count == 1 { return lovlige[0] }
        let logits = hjerne.spill.forover(NevroTrekk.spill(engine: engine, sete: sete))
        return lovlige.max { logits[Kortmaske.indeks($0)] < logits[Kortmaske.indeks($1)] }
    }
}
