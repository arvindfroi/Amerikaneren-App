import Foundation

// Trenbar utgave av NevroNett: per-eksempel forover/tilbake med Adam.

final class TreneLag {
    let inn: Int
    let ut: Int
    var w: [Float]
    var b: [Float]
    var gw: [Float]
    var gb: [Float]
    var mw: [Float], vw: [Float], mb: [Float], vb: [Float]

    init(inn: Int, ut: Int, rng: inout SeededGenerator) {
        self.inn = inn
        self.ut = ut
        // He-initialisering
        let std = (2.0 / Double(inn)).squareRoot()
        w = (0..<(inn * ut)).map { _ in Float(gauss(&rng) * std) }
        b = [Float](repeating: 0, count: ut)
        gw = [Float](repeating: 0, count: inn * ut)
        gb = [Float](repeating: 0, count: ut)
        mw = gw; vw = gw; mb = gb; vb = gb
    }

    init(fra lag: NevroLag) {
        inn = lag.inn; ut = lag.ut
        w = lag.vekter; b = lag.bias
        gw = [Float](repeating: 0, count: inn * ut)
        gb = [Float](repeating: 0, count: ut)
        mw = gw; vw = gw; mb = gb; vb = gb
    }

    var somNevroLag: NevroLag { NevroLag(inn: inn, ut: ut, vekter: w, bias: b) }

    func forover(_ x: [Float]) -> [Float] {
        var y = b
        w.withUnsafeBufferPointer { wp in
            x.withUnsafeBufferPointer { xp in
                y.withUnsafeMutableBufferPointer { yp in
                    for r in 0..<ut {
                        var sum: Float = 0
                        let rad = r * inn
                        for c in 0..<inn { sum += wp[rad + c] * xp[c] }
                        yp[r] += sum
                    }
                }
            }
        }
        return y
    }

    /// Akkumulerer gradienter og returnerer dL/dx.
    func tilbake(x: [Float], dY: [Float]) -> [Float] {
        var dX = [Float](repeating: 0, count: inn)
        w.withUnsafeBufferPointer { wp in
            x.withUnsafeBufferPointer { xp in
                dY.withUnsafeBufferPointer { dyp in
                    gw.withUnsafeMutableBufferPointer { gwp in
                        dX.withUnsafeMutableBufferPointer { dxp in
                            for r in 0..<ut {
                                let d = dyp[r]
                                if d == 0 { continue }
                                let rad = r * inn
                                for c in 0..<inn {
                                    gwp[rad + c] += d * xp[c]
                                    dxp[c] += d * wp[rad + c]
                                }
                            }
                        }
                    }
                }
            }
        }
        for r in 0..<ut { gb[r] += dY[r] }
        return dX
    }

    private var t = 0
    func adamSteg(lr: Float, skala: Float) {
        t += 1
        let b1: Float = 0.9, b2: Float = 0.999, eps: Float = 1e-8
        let korr1 = 1 - pow(b1, Float(t))
        let korr2 = 1 - pow(b2, Float(t))
        for i in 0..<w.count {
            let g = gw[i] * skala
            mw[i] = b1 * mw[i] + (1 - b1) * g
            vw[i] = b2 * vw[i] + (1 - b2) * g * g
            w[i] -= lr * (mw[i] / korr1) / ((vw[i] / korr2).squareRoot() + eps)
            gw[i] = 0
        }
        for i in 0..<b.count {
            let g = gb[i] * skala
            mb[i] = b1 * mb[i] + (1 - b1) * g
            vb[i] = b2 * vb[i] + (1 - b2) * g * g
            b[i] -= lr * (mb[i] / korr1) / ((vb[i] / korr2).squareRoot() + eps)
            gb[i] = 0
        }
    }
}

final class TreneNett {
    var lag: [TreneLag]

    init(dims: [Int], rng: inout SeededGenerator) {
        lag = (0..<(dims.count - 1)).map { TreneLag(inn: dims[$0], ut: dims[$0 + 1], rng: &rng) }
    }

    init(fra nett: NevroNett) {
        lag = nett.lag.map { TreneLag(fra: $0) }
    }

    var somNevroNett: NevroNett { NevroNett(lag: lag.map(\.somNevroLag)) }

    /// Forover med lagrede aktiveringer (for tilbake-passet).
    func forover(_ x: [Float]) -> [[Float]] {
        var akt: [[Float]] = [x]
        for (i, l) in lag.enumerated() {
            var y = l.forover(akt[i])
            if i < lag.count - 1 {
                for j in 0..<y.count where y[j] < 0 { y[j] = 0 }
            }
            akt.append(y)
        }
        return akt
    }

    /// Tilbake fra dLogits gjennom alle lag.
    func tilbake(aktiveringer: [[Float]], dLogits: [Float]) {
        var d = dLogits
        for i in stride(from: lag.count - 1, through: 0, by: -1) {
            if i < lag.count - 1 {
                // ReLU-derivert på laget vi går inn i.
                for j in 0..<d.count where aktiveringer[i + 1][j] <= 0 { d[j] = 0 }
            }
            d = lag[i].tilbake(x: aktiveringer[i], dY: d)
        }
    }

    func adamSteg(lr: Float, batch: Int) {
        let skala = 1 / Float(max(1, batch))
        for l in lag { l.adamSteg(lr: lr, skala: skala) }
    }
}

func gauss(_ rng: inout SeededGenerator) -> Double {
    let u1 = Double.random(in: 1e-9..<1, using: &rng)
    let u2 = Double.random(in: 0..<1, using: &rng)
    return (-2 * Foundation.log(u1)).squareRoot() * cos(2 * .pi * u2)
}

/// Maskert softmax over gyldige posisjoner.
func maskertSoftmax(_ logits: [Float], maske: [Bool]) -> [Float] {
    var maks = -Float.infinity
    for i in 0..<logits.count where maske[i] { maks = max(maks, logits[i]) }
    var sum: Float = 0
    var p = [Float](repeating: 0, count: logits.count)
    for i in 0..<logits.count where maske[i] {
        p[i] = exp(logits[i] - maks)
        sum += p[i]
    }
    if sum > 0 { for i in 0..<p.count { p[i] /= sum } }
    return p
}

func sampleFra(_ p: [Float], rng: inout SeededGenerator) -> Int {
    var r = Float.random(in: 0..<1, using: &rng)
    for (i, v) in p.enumerated() {
        r -= v
        if r < 0 { return i }
    }
    return p.indices.last ?? 0
}
