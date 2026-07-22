import Foundation

// Måleverktøy for UTRULLINGSPOLICYEN i MesterAI-søket.
//
//   harness utrulling kurve <runder> <verdenstall> <fra> <policyer>
//   harness utrulling fart  <trekk>
//
// Alt skrives fortløpende til ~/utrulling/resultater.jsonl. Filen åpnes i
// O_APPEND, så flere shard-prosesser kan skrive til den samtidig uten å
// tråkke på hverandre (korte skriv er atomiske på Linux).

// MARK: - Varig logg

let utrullingLoggSti = NSString(string: "~/utrulling/resultater.jsonl").expandingTildeInPath

func utrullingLogg(_ felt: [String: Any], stille: Bool = false) {
    var rad = felt
    rad["tid"] = ISO8601DateFormatter().string(from: Date())
    rad["last"] = maskinlast()
    rad["pid"] = ProcessInfo.processInfo.processIdentifier
    guard let data = try? JSONSerialization.data(withJSONObject: rad, options: [.sortedKeys]),
          var linje = String(data: data, encoding: .utf8) else { return }
    linje += "\n"
    let mappe = (utrullingLoggSti as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: mappe, withIntermediateDirectories: true)
    let fd = open(utrullingLoggSti, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    if fd >= 0 {
        _ = linje.withCString { write(fd, $0, strlen($0)) }
        close(fd)
    }
    if !stille { FileHandle.standardOutput.write(("» " + linje).data(using: .utf8)!) }
}

// MARK: - Konfigurasjon

/// Dagens President-oppsett, men med FAST verdenstall (min == maks) og et
/// tidsbudsjett som aldri binder. Da er målingen helt lastuavhengig og kan
/// shardes fritt over ledige kjerner – og armene skiller seg bare på
/// utrullingspolicyen, ikke på hvor mye søk de rakk.
func utrullingKonfig(verdenstall: Int, policy: Utrullingspolicy) -> MesterKonfig {
    var k = MesterKonfig()
    if ProcessInfo.processInfo.activeProcessorCount >= 6 {
        k.verdenerVedBud = 64
        k.eksaktStikkGrense = 7
    }
    k.maksTråder = 1                    // reproduserbart, og shardbart per prosess
    k.tidsbudsjett = 36_000             // binder aldri
    k.maksVerdener = verdenstall
    k.maksVerdenerSluttspill = verdenstall
    k.minVerdener = verdenstall
    k.utrullingspolicy = policy
    return k
}

// MARK: - 1) Styrkekurve over policyer

/// Sete 0 = President mot 3× vanskelig. Alle armer spiller NØYAKTIG de samme
/// utdelingene med de samme frøene, så differansen mellom to policyer er
/// parret runde for runde.
func utrullingKurve(runder: Int, fra: Int, verdenstall: Int, policyer: [Utrullingspolicy]) {
    print("== Utrullingspolicy ved FAST \(verdenstall) verdener: sete 0 President mot 3× vanskelig ==")
    print("   runder \(fra + 1)–\(fra + runder), policyer: \(policyer.map(\.description).joined(separator: ", "))")
    var armer: [String: [Int: Double]] = [:]     // policy → (rundenr → poeng)
    for policy in policyer {
        let konfig = utrullingKonfig(verdenstall: verdenstall, policy: policy)
        var poeng: [Double] = []
        var perRunde: [Int: Double] = [:]
        var sumV = 0, sumT = 0, sumS = 0.0
        let start = Date()
        for r in (fra + 1)...(fra + runder) {
            // Samme frøformel som breddekurven, så utdelingene er de kjente.
            let seed = UInt64(r) &* 13 &+ 5
            var v = [0, 0, 0, 0], t = [0, 0, 0, 0], s = [0.0, 0, 0, 0]
            let spillere: [Setespiller] = (0..<4).map {
                lagSete($0, konfig: $0 == 0 ? konfig : nil, frø: seed &* 31 &+ 7)
            }
            guard let runde = spillRundeMedKonfig(seed: seed, spillere: spillere,
                                                  verdener: &v, trekk: &t, sekunder: &s) else { continue }
            poeng.append(Double(runde.poengEndring[0]))
            perRunde[r] = Double(runde.poengEndring[0])
            sumV += v[0]; sumT += t[0]; sumS += s[0]
            utrullingLogg([
                "måling": "runde", "policy": policy.description,
                "verdenstall": verdenstall, "runde": r,
                "poeng": runde.poengEndring[0], "trekk": t[0], "sek": s[0],
            ], stille: true)
        }
        armer[policy.description] = perRunde
        let (m, se, n) = snittOgSE(poeng)
        print(String(format: "  %-16@: %+.3f ± %.3f poeng/runde (n=%d, %.3f s/trekk, %.0f s)",
                     policy.description as NSString, m, se, n,
                     sumT > 0 ? sumS / Double(sumT) : 0, Date().timeIntervalSince(start)))
        utrullingLogg([
            "måling": "arm", "policy": policy.description, "verdenstall": verdenstall,
            "fra": fra, "runder": runder, "poeng_per_runde": m, "se": se, "n": n,
            "verdener_per_trekk": sumT > 0 ? Double(sumV) / Double(sumT) : 0,
            "sek_per_trekk": sumT > 0 ? sumS / Double(sumT) : 0,
        ])
    }

    // Parret differanse mot den grådige referansen, runde for runde.
    guard let basis = armer[Utrullingspolicy.grådig.description] else { return }
    for policy in policyer where policy != .grådig {
        guard let x = armer[policy.description] else { continue }
        let felles = basis.keys.filter { x[$0] != nil }.sorted()
        let diff = felles.map { x[$0]! - basis[$0]! }
        let (m, se, n) = snittOgSE(diff)
        print(String(format: "    parret %@ − grådig: %+.3f ± %.3f (n=%d, %.1f SE)",
                     policy.description as NSString, m, se, n, se > 0 ? m / se : 0))
        utrullingLogg([
            "måling": "parret", "policy": policy.description, "verdenstall": verdenstall,
            "fra": fra, "differanse": m, "se": se, "n": n,
            "se_avstand": se > 0 ? m / se : 0,
        ])
    }
}

// MARK: - 2) Fart: hvor dyr er hver policy per utrulling?

/// Utrullinger per sekund for hver policy, målt på tilfeldige midtspill-
/// stillinger. Sier hvor mye søk hver policy kjøper for samme tid – og er
/// forutsetningen for å vurdere om en dyrere policy (f.eks. et nevralt nett)
/// i det hele tatt er praktisk.
func utrullingFart(gjentakelser: Int, policyer: [Utrullingspolicy]) {
    print("== Utrullingsfart: kall per sekund per policy ==")
    var rng = SeededGenerator(seed: 20260722)
    // Midtspillstillinger: 11 stikk igjen, utrulling ned til 7 (som i søket).
    let stillinger = (0..<64).map { _ in tilfeldigTilstand(stikk: 11, rng: &rng) }
    for policy in policyer {
        var r = SeededGenerator(seed: 12345)
        var sum = 0
        let start = Date()
        for i in 0..<gjentakelser {
            var perSete = [0, 0, 0, 0]
            let t = GrådigSpiller.spillUt(stillinger[i % stillinger.count], policy: policy,
                                          rng: &r, stoppVedStikkIgjen: 7, perSete: &perSete)
            sum &+= t.hender[0].nonzeroBitCount
        }
        let sek = Date().timeIntervalSince(start)
        let perSek = Double(gjentakelser) / max(sek, 1e-9)
        print(String(format: "  %-16@: %9.0f utrullinger/s (%.2f s for %d, sjekksum %d)",
                     policy.description as NSString, perSek, sek, gjentakelser, sum))
        utrullingLogg(["måling": "fart", "policy": policy.description,
                       "utrullinger_per_sek": perSek, "gjentakelser": gjentakelser])
    }
}

// MARK: - 3) Er NevroHjerne praktisk som utrullingspolicy?

/// Måler ren foroverpass-fart for kortspillnettet. En nevral utrullings-
/// policy må gjøre ETT oppslag per kort som legges, og en utrulling fra
/// stikk 1 til sluttspillgrensen legger typisk 16–24 kort. Tallet her er
/// altså et TAK: den virkelige policyen ville i tillegg måtte bygge
/// trekkvektoren (238 flyttall) for hver eneste kortlegging.
func nevroFart(gjentakelser: Int) {
    print("== NevroHjerne som utrullingspolicy: er den rask nok? ==")
    guard let hjerne = NevroHjerne.delt else {
        print("  NevroHjerne mangler innebygde vekter – ikke målbar her.")
        utrullingLogg(["måling": "nevrofart", "status": "mangler_vekter"])
        return
    }
    let dims = hjerne.spill.lag.map { "\($0.inn)→\($0.ut)" }.joined(separator: ", ")
    print("  kortspillnettet: \(dims)")
    var x = [Float](repeating: 0, count: NevroTrekk.spillDim)
    for i in stride(from: 0, to: NevroTrekk.spillDim, by: 3) { x[i] = 1 }
    var sum: Float = 0
    let start = Date()
    for _ in 0..<gjentakelser { sum += hjerne.spill.forover(x)[0] }
    let sek = Date().timeIntervalSince(start)
    let perSek = Double(gjentakelser) / max(sek, 1e-9)
    // Grådig gjør ett trekkvalg per kort; sammenlikn per kortlegging.
    print(String(format: "  %.0f foroverpass/s (%.1f µs per kortlegging, sjekksum %.3f)",
                 perSek, 1e6 / perSek, Double(sum)))
    utrullingLogg(["måling": "nevrofart", "foroverpass_per_sek": perSek,
                   "lag": dims, "gjentakelser": gjentakelser])
}

// MARK: - Argumenter

func utrullingPolicyliste(_ tekst: String) -> [Utrullingspolicy] {
    tekst.split(separator: ",").compactMap { Utrullingspolicy.fra(String($0)) }
}
