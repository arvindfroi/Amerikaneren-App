import Foundation

// Måleverktøy for parallelliseringen av MesterAI-søket.
//
//   harness parallell gjennomstrømning [runder]
//   harness parallell bredde [runder]
//   harness parallell ab [runder] [tråder]
//   harness parallell h2h [runder] [tråder]
//
// Alle resultater skrives fortløpende til ~/par/resultater.jsonl, slik at
// ingenting går tapt om maskinen faller ned midt i en kjøring.

// MARK: - Varig logg

let parLoggSti = NSString(string: "~/par/resultater.jsonl").expandingTildeInPath

func parLogg(_ felt: [String: Any]) {
    var rad = felt
    rad["tid"] = ISO8601DateFormatter().string(from: Date())
    rad["last"] = maskinlast()
    guard let data = try? JSONSerialization.data(withJSONObject: rad, options: [.sortedKeys]),
          var linje = String(data: data, encoding: .utf8) else { return }
    linje += "\n"
    let mappe = (parLoggSti as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: mappe, withIntermediateDirectories: true)
    if let fh = FileHandle(forWritingAtPath: parLoggSti) {
        fh.seekToEndOfFile()
        fh.write(linje.data(using: .utf8)!)
        try? fh.close()
    } else {
        try? linje.write(toFile: parLoggSti, atomically: true, encoding: .utf8)
    }
    FileHandle.standardOutput.write(("» " + linje).data(using: .utf8)!)
}

/// 1-minutts snittlast fra /proc/loadavg – maskinen deles med treningsjobber,
/// så lasten hører med i enhver parallellmåling.
func maskinlast() -> Double {
    guard let tekst = try? String(contentsOfFile: "/proc/loadavg", encoding: .utf8),
          let første = tekst.split(separator: " ").first,
          let verdi = Double(første) else { return -1 }
    return verdi
}

// MARK: - Statistikk

/// Snitt og standardfeil for en serie parrede differanser.
func snittOgSE(_ x: [Double]) -> (snitt: Double, se: Double, n: Int) {
    let n = x.count
    guard n > 1 else { return (x.first ?? 0, 0, n) }
    let m = x.reduce(0, +) / Double(n)
    let varians = x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n - 1)
    return (m, (varians / Double(n)).squareRoot(), n)
}

// MARK: - Runde med egen konfigurasjon per sete

/// Spillere med full kontroll over MesterAI-konfigurasjon og frø per sete.
/// Nødvendig for hodetil-hode: sete 0+2 parallelle, 1+3 entrådede.
enum Setespiller {
    case mester(MesterAI)
    case heuristikk(AIPlayer)
}

func lagSete(_ sete: Int, konfig: MesterKonfig?, frø: UInt64,
             nivå: AIDifficulty = .vanskelig) -> Setespiller {
    if let konfig {
        return .mester(MesterAI(sete: sete, konfig: konfig, seed: frø &+ UInt64(sete) &* 7919))
    }
    return .heuristikk(AIPlayer(seat: sete, difficulty: nivå, personality: .balansert))
}

/// Spiller én runde. Returnerer resultatet, samt hvor mange verdener hvert
/// MesterAI-sete rakk og hvor mye tid det brukte på kortvalg.
@discardableResult
func spillRundeMedKonfig(seed: UInt64, spillere: [Setespiller],
                         verdener: inout [Int], trekk: inout [Int],
                         sekunder: inout [Double]) -> RoundResult? {
    let engine = GameEngine()
    engine.startRunde(seed: seed)
    var vakt = 0
    while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
        vakt += 1
        if vakt > 400 { print("FEIL: runde henger"); return nil }
        switch engine.phase {
        case .budrunde:
            let sete = engine.aktivBudgiver
            let lovlige = engine.lovligeBud(for: sete)
            var bud = BidAction.pass
            switch spillere[sete] {
            case .mester(let m):
                let b = m.velgBud(engine: engine)
                if lovlige.contains(b) { bud = b }
            case .heuristikk(let a):
                let b = a.velgBud(engine: engine)
                if lovlige.contains(b) { bud = b }
            }
            guard engine.giBud(seat: sete, action: bud) else { return nil }
        case .byttekort:
            let sete = engine.budgiverSeat!
            let antall = engine.rules.antallByttekort
            var vrak: [Card] = []
            switch spillere[sete] {
            case .mester(let m): vrak = m.velgByttekort(engine: engine)
            case .heuristikk(let a): vrak = a.velgByttekort(engine: engine)
            }
            if vrak.count != antall { vrak = Array(engine.hands[sete].prefix(antall)) }
            guard engine.kastByttekort(vrak, seat: sete) else { return nil }
        case .velgTrumf:
            let sete = engine.budgiverSeat!
            var valg: (Suit, Card?)?
            switch spillere[sete] {
            case .mester(let m): valg = m.velgTrumfOgMakker(engine: engine)
            case .heuristikk(let a): valg = a.velgTrumfOgMakker(engine: engine)
            }
            guard let (suit, ønsket) = valg, engine.velgTrumf(suit: suit, ønsket: ønsket) else {
                // Nødvalg: første lovlige farge med et ønskbart kort.
                var reddet = false
                for s in Suit.allCases {
                    if let ø = engine.kortSomKanØnskes(trumf: s).first,
                       engine.velgTrumf(suit: s, ønsket: ø) { reddet = true; break }
                }
                if !reddet, !engine.velgTrumf(suit: .spar, ønsket: nil) { return nil }
                continue
            }
        case .spill:
            let sete = engine.aktivSpiller
            var kort: Card?
            switch spillere[sete] {
            case .mester(let m):
                let start = Date()
                kort = m.velgKort(engine: engine)
                if m.sisteVerdenstall > 0 {
                    verdener[sete] += m.sisteVerdenstall
                    trekk[sete] += 1
                    sekunder[sete] += Date().timeIntervalSince(start)
                }
            case .heuristikk(let a):
                kort = a.velgKort(engine: engine)
            }
            guard let kort, engine.spill(kort: kort, seat: sete) else { return nil }
        default:
            return nil
        }
    }
    return engine.sisteRunde
}

// MARK: - Konfigurasjoner

/// Dagens MesterAI: `automatisk()` slik den var før parallelliseringen –
/// entrådet, med de opprinnelige verdenstakene.
func entrådetKonfig(tid: Double) -> MesterKonfig {
    var k = MesterKonfig()
    if ProcessInfo.processInfo.activeProcessorCount >= 6 {
        k.maksVerdener = 36
        k.verdenerVedBud = 64
        k.eksaktStikkGrense = 7
    }
    k.maksTråder = 1
    k.tidsbudsjett = tid
    return k
}

/// Parallell MesterAI: samme tidsbudsjett, T arbeidere, tak skalert med T.
func parallellKonfig(tid: Double, tråder: Int) -> MesterKonfig {
    var k = entrådetKonfig(tid: tid)
    k.maksTråder = tråder
    k.maksVerdener *= tråder
    k.maksVerdenerSluttspill *= tråder
    return k
}

// MARK: - 1) Gjennomstrømning

/// Verdener per trekk ved fast tidsbudsjett, entrådet mot parallelt, delt på
/// midtspill (grådig utrulling + eksakt hale) og sluttspill (alt eksakt).
func parGjennomstrømning(runder: Int, tid: Double, tråder: Int) {
    print("== Gjennomstrømning: verdener per trekk ved \(tid) s ==")
    for (navn, konfig) in [("entrådet", entrådetKonfig(tid: tid)),
                           ("parallell", parallellKonfig(tid: tid, tråder: tråder))] {
        var midtVerdener = 0, midtTrekk = 0
        var sluttVerdener = 0, sluttTrekk = 0
        var brukt = 0.0
        let start = Date()
        for r in 0..<runder {
            let seed = UInt64(r) &* 7919 &+ 101
            let engine = GameEngine()
            engine.startRunde(seed: seed)
            let mestere = (0..<4).map {
                MesterAI(sete: $0, konfig: konfig, seed: seed &+ UInt64($0) &* 7919)
            }
            var vakt = 0
            while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
                vakt += 1
                if vakt > 400 { break }
                switch engine.phase {
                case .budrunde:
                    let s = engine.aktivBudgiver
                    let b = mestere[s].velgBud(engine: engine)
                    _ = engine.giBud(seat: s, action: engine.lovligeBud(for: s).contains(b) ? b : .pass)
                case .byttekort:
                    let s = engine.budgiverSeat!
                    var v = mestere[s].velgByttekort(engine: engine)
                    if v.count != engine.rules.antallByttekort {
                        v = Array(engine.hands[s].prefix(engine.rules.antallByttekort))
                    }
                    _ = engine.kastByttekort(v, seat: s)
                case .velgTrumf:
                    let s = engine.budgiverSeat!
                    guard let (suit, ø) = mestere[s].velgTrumfOgMakker(engine: engine),
                          engine.velgTrumf(suit: suit, ønsket: ø) else { vakt = 500; break }
                case .spill:
                    let s = engine.aktivSpiller
                    // Stikk igjen FØR trekket avgjør om posisjonen er sluttspill.
                    let igjen = engine.hands[s].count
                    let start = Date()
                    guard let kort = mestere[s].velgKort(engine: engine) else { vakt = 500; break }
                    let n = mestere[s].sisteVerdenstall
                    if n > 0 {
                        brukt += Date().timeIntervalSince(start)
                        if igjen <= konfig.eksaktStikkGrense {
                            sluttVerdener += n; sluttTrekk += 1
                        } else {
                            midtVerdener += n; midtTrekk += 1
                        }
                    }
                    _ = engine.spill(kort: kort, seat: s)
                default:
                    vakt = 500
                }
            }
        }
        let midt = midtTrekk > 0 ? Double(midtVerdener) / Double(midtTrekk) : 0
        let slutt = sluttTrekk > 0 ? Double(sluttVerdener) / Double(sluttTrekk) : 0
        let sek = Double(midtTrekk + sluttTrekk) > 0 ? brukt / Double(midtTrekk + sluttTrekk) : 0
        print(String(format: "  %@ (%d tråder): midtspill %.1f verdener/trekk (n=%d), sluttspill %.1f (n=%d), %.3f s/trekk, %.0f s totalt",
                     navn, konfig.trådtall, midt, midtTrekk, slutt, sluttTrekk, sek,
                     Date().timeIntervalSince(start)))
        parLogg([
            "måling": "gjennomstrømning", "arm": navn, "tråder": konfig.trådtall,
            "tidsbudsjett": tid, "runder": runder,
            "midt_verdener_per_trekk": midt, "midt_trekk": midtTrekk,
            "slutt_verdener_per_trekk": slutt, "slutt_trekk": sluttTrekk,
            "sek_per_trekk": sek,
        ])
    }
}

// MARK: - 2) Breddekurve ved fast verdenstall

/// Kjøper flere verdener i det hele tatt noe utenfor sluttspillet? Fast
/// verdenstall (min == maks), rikelig tid, sete 0 mot 3× vanskelig.
/// `sluttspillTak` pinner sluttspillbredden, slik at bare MIDTSPILLBREDDEN
/// varierer. Det er nettopp den aksen parallelliseringen flytter i praksis
/// (sluttspillet er alt over metningspunktet ved 0,45 s).
func parBredde(runder: Int, verdenstall: [Int], tråder: Int, sluttspillTak: Int? = nil) {
    print("== Breddekurve ved FAST verdenstall (tid binder ikke)"
          + (sluttspillTak.map { ", sluttspill låst til \($0)" } ?? "") + " ==")
    var resultater: [Int: [Double]] = [:]
    for n in verdenstall {
        var konfig = entrådetKonfig(tid: 3600)
        konfig.maksTråder = tråder
        konfig.maksVerdener = n
        konfig.maksVerdenerSluttspill = sluttspillTak ?? n
        konfig.minVerdener = min(n, sluttspillTak ?? n)
        var poeng: [Double] = []
        let start = Date()
        for r in 1...runder {
            let seed = UInt64(r) &* 13 &+ 5
            var v = [0, 0, 0, 0], t = [0, 0, 0, 0], s = [0.0, 0, 0, 0]
            let spillere: [Setespiller] = (0..<4).map {
                lagSete($0, konfig: $0 == 0 ? konfig : nil, frø: seed &* 31 &+ 7)
            }
            guard let runde = spillRundeMedKonfig(seed: seed, spillere: spillere,
                                                  verdener: &v, trekk: &t, sekunder: &s) else { continue }
            poeng.append(Double(runde.poengEndring[0]))
        }
        let (m, se, antall) = snittOgSE(poeng)
        resultater[n] = poeng
        print(String(format: "  %5d verdener: %+.2f ± %.2f poeng/runde (n=%d, %.0f s)",
                     n, m, se, antall, Date().timeIntervalSince(start)))
        parLogg(["måling": "bredde", "verdenstall": n, "tråder": tråder,
                 "sluttspill_tak": sluttspillTak ?? n,
                 "poeng_per_runde": m, "se": se, "n": antall,
                 "poeng": poeng.map { Int($0) }])
    }
    // Parret differanse mot det minste verdenstallet (samme utdelinger).
    if let basis = verdenstall.first, let b = resultater[basis] {
        for n in verdenstall.dropFirst() {
            guard let x = resultater[n], x.count == b.count else { continue }
            let diff = zip(x, b).map(-)
            let (m, se, antall) = snittOgSE(diff)
            print(String(format: "    parret %d − %d: %+.2f ± %.2f (n=%d, %.1f SE)",
                         n, basis, m, se, antall, se > 0 ? m / se : 0))
            parLogg(["måling": "bredde_parret", "fra": basis, "til": n,
                     "sluttspill_tak": sluttspillTak ?? -1,
                     "differanse": m, "se": se, "n": antall])
        }
    }
}

// MARK: - 3) Styrke-A/B: sete 0 mot 3× vanskelig

/// Parret A/B med samme tidsbudsjett i begge armer: sete 0 er President
/// (entrådet eller parallell), setene 1–3 er «vanskelig». Samme utdelinger
/// og samme MesterAI-frø i begge armer.
func parStyrkeAB(runder: Int, tid: Double, tråder: Int, fastVerdenstall: Int?) {
    let merke = fastVerdenstall.map { "FAST \($0) verdener" } ?? "\(tid) s tidsbudsjett"
    print("== Styrke-A/B (\(merke)): sete 0 President mot 3× vanskelig ==")
    var armer: [String: [Double]] = ["entrådet": [], "parallell": []]
    var verdenssnitt: [String: (Int, Int)] = [:]
    for (navn, basis) in [("entrådet", entrådetKonfig(tid: tid)),
                          ("parallell", parallellKonfig(tid: tid, tråder: tråder))] {
        var konfig = basis
        if let n = fastVerdenstall {
            konfig.maksVerdener = n
            konfig.maksVerdenerSluttspill = n
            konfig.minVerdener = n
            konfig.tidsbudsjett = 3600
        }
        var poeng: [Double] = []
        var sumV = 0, sumT = 0
        let start = Date()
        for r in 1...runder {
            let seed = UInt64(r) &* 13 &+ 5
            var v = [0, 0, 0, 0], t = [0, 0, 0, 0], s = [0.0, 0, 0, 0]
            let spillere: [Setespiller] = (0..<4).map {
                lagSete($0, konfig: $0 == 0 ? konfig : nil, frø: seed &* 31 &+ 7)
            }
            guard let runde = spillRundeMedKonfig(seed: seed, spillere: spillere,
                                                  verdener: &v, trekk: &t, sekunder: &s) else { continue }
            poeng.append(Double(runde.poengEndring[0]))
            sumV += v[0]; sumT += t[0]
            if r % 25 == 0 {
                let (m, se, n) = snittOgSE(poeng)
                parLogg(["måling": "styrke_ab_fremdrift", "arm": navn, "runder": n,
                         "poeng_per_runde": m, "se": se, "tråder": konfig.trådtall,
                         "fast_verdenstall": fastVerdenstall ?? -1])
            }
        }
        armer[navn] = poeng
        verdenssnitt[navn] = (sumV, sumT)
        let (m, se, n) = snittOgSE(poeng)
        print(String(format: "  %@: %+.2f ± %.2f poeng/runde (n=%d, %.0f verdener/trekk, %.0f s)",
                     navn, m, se, n,
                     sumT > 0 ? Double(sumV) / Double(sumT) : 0, Date().timeIntervalSince(start)))
        parLogg(["måling": "styrke_ab_arm", "arm": navn, "tråder": konfig.trådtall,
                 "tidsbudsjett": konfig.tidsbudsjett, "fast_verdenstall": fastVerdenstall ?? -1,
                 "poeng_per_runde": m, "se": se, "n": n,
                 "verdener_per_trekk": sumT > 0 ? Double(sumV) / Double(sumT) : 0,
                 "poeng": poeng.map { Int($0) }])
    }
    guard let a = armer["parallell"], let b = armer["entrådet"], a.count == b.count else { return }
    let diff = zip(a, b).map(-)
    let (m, se, n) = snittOgSE(diff)
    print(String(format: "  → parret differanse (parallell − entrådet): %+.3f ± %.3f poeng/runde (n=%d, %.1f SE)",
                 m, se, n, se > 0 ? m / se : 0))
    parLogg(["måling": "styrke_ab_differanse", "differanse": m, "se": se, "n": n,
             "se_avstand": se > 0 ? m / se : 0, "tråder": tråder,
             "fast_verdenstall": fastVerdenstall ?? -1, "tidsbudsjett": tid])
}

// MARK: - 4) Hode mot hode: parallell MesterAI mot dagens MesterAI

/// Fire President-seter. I orientering A er sete 0+2 parallelle og 1+3
/// entrådede; i orientering B er det speilvendt. Samme utdelinger og samme
/// frø i begge orienteringer, så seteeffekter kanselleres. Måltallet er
/// poeng per runde til de parallelle setene minus de entrådede.
func parHodeMotHode(runder: Int, tid: Double, tråder: Int, fra: Int = 0) {
    print("== Hode mot hode: parallell MesterAI mot dagens MesterAI (\(tid) s begge) ==")
    let par = parallellKonfig(tid: tid, tråder: tråder)
    let ent = entrådetKonfig(tid: tid)
    var diff: [Double] = []
    var sumParV = 0, sumParT = 0, sumEntV = 0, sumEntT = 0
    let start = Date()
    // `fra` lar en kjøring fortsette der en tidligere slapp, med nye
    // utdelinger, slik at resultatene kan slås sammen.
    for r in (fra + 1)...(fra + runder) {
        let seed = UInt64(r) &* 2_654_435_761 &+ 17
        var rundeDiff = 0.0
        var ok = true
        for orientering in 0..<2 {
            // orientering 0: parallell på 0+2. orientering 1: parallell på 1+3.
            let parSeter: Set<Int> = orientering == 0 ? [0, 2] : [1, 3]
            var v = [0, 0, 0, 0], t = [0, 0, 0, 0], s = [0.0, 0, 0, 0]
            let spillere: [Setespiller] = (0..<4).map {
                lagSete($0, konfig: parSeter.contains($0) ? par : ent, frø: seed &* 31 &+ 7)
            }
            guard let runde = spillRundeMedKonfig(seed: seed, spillere: spillere,
                                                  verdener: &v, trekk: &t, sekunder: &s) else {
                ok = false; break
            }
            let parPoeng = parSeter.reduce(0) { $0 + runde.poengEndring[$1] }
            let entPoeng = (0..<4).filter { !parSeter.contains($0) }
                .reduce(0) { $0 + runde.poengEndring[$1] }
            // Halv vekt per orientering: snittet av de to speilrundene.
            rundeDiff += Double(parPoeng - entPoeng) / 2.0
            for i in 0..<4 {
                if parSeter.contains(i) { sumParV += v[i]; sumParT += t[i] }
                else { sumEntV += v[i]; sumEntT += t[i] }
            }
        }
        guard ok else { continue }
        diff.append(rundeDiff)
        if r % 10 == 0 {
            let (m, se, n) = snittOgSE(diff)
            print(String(format: "  ... %d runder: %+.3f ± %.3f (%.0f s)",
                         n, m, se, Date().timeIntervalSince(start)))
            parLogg(["måling": "h2h_fremdrift", "runder": n, "differanse": m, "se": se,
                     "tråder": tråder, "tidsbudsjett": tid])
        }
    }
    let (m, se, n) = snittOgSE(diff)
    print(String(format: "  → parallell − entrådet: %+.3f ± %.3f poeng per lagrunde (n=%d, %.1f SE)",
                 m, se, n, se > 0 ? m / se : 0))
    print(String(format: "     verdener/trekk: parallell %.0f, entrådet %.0f",
                 sumParT > 0 ? Double(sumParV) / Double(sumParT) : 0,
                 sumEntT > 0 ? Double(sumEntV) / Double(sumEntT) : 0))
    parLogg(["måling": "h2h", "differanse": m, "se": se, "n": n, "fra": fra,
             "se_avstand": se > 0 ? m / se : 0, "tråder": tråder, "tidsbudsjett": tid,
             "par_verdener_per_trekk": sumParT > 0 ? Double(sumParV) / Double(sumParT) : 0,
             "ent_verdener_per_trekk": sumEntT > 0 ? Double(sumEntV) / Double(sumEntT) : 0,
             "differanser": diff])
}
