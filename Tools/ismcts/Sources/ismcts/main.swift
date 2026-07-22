import Foundation

// Måleverktøy for informasjonssett-søket (SO-ISMCTS) mot dagens PIMC-baserte
// MesterAI.
//
//   ismcts sanitet   runder=200
//   ismcts fart      tid=0.2
//   ismcts h2h       runder=200 tid=0.2 [traader=1] [blad=0] [pimctak=0] [fra=0]
//   ismcts kurve     runder=120 iter=200,1000,5000,20000 [pimctid=0.2]
//   ismcts blad      runder=150 tid=0.2
//
// ALT skrives fortløpende til ~/ismcts/resultater.jsonl, slik at ingenting
// går tapt om en kjøring blir avbrutt.

// MARK: - Argumenter

let argv = CommandLine.arguments
let kommando = argv.count > 1 ? argv[1] : "hjelp"
var argumenter: [String: String] = [:]
for a in argv.dropFirst(2) {
    let deler = a.split(separator: "=", maxSplits: 1)
    if deler.count == 2 { argumenter[String(deler[0])] = String(deler[1]) }
}
func tall(_ navn: String, _ standard: Int) -> Int { argumenter[navn].flatMap { Int($0) } ?? standard }
func desimal(_ navn: String, _ standard: Double) -> Double { argumenter[navn].flatMap { Double($0) } ?? standard }
func tekst(_ navn: String, _ standard: String) -> String { argumenter[navn] ?? standard }

// MARK: - Varig logg

let loggSti = NSString(string: "~/ismcts/resultater.jsonl").expandingTildeInPath
let loggLås = NSLock()

func logg(_ felt: [String: Any]) {
    var rad = felt
    rad["tid_stempel"] = ISO8601DateFormatter().string(from: Date())
    rad["last"] = maskinlast()
    guard let data = try? JSONSerialization.data(withJSONObject: rad, options: [.sortedKeys]),
          var linje = String(data: data, encoding: .utf8) else { return }
    linje += "\n"
    loggLås.lock()
    defer { loggLås.unlock() }
    let mappe = (loggSti as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: mappe, withIntermediateDirectories: true)
    if let fh = FileHandle(forWritingAtPath: loggSti) {
        fh.seekToEndOfFile()
        fh.write(linje.data(using: .utf8)!)
        try? fh.close()
    } else {
        try? linje.write(toFile: loggSti, atomically: true, encoding: .utf8)
    }
}

func maskinlast() -> Double {
    guard let tekst = try? String(contentsOfFile: "/proc/loadavg", encoding: .utf8),
          let første = tekst.split(separator: " ").first,
          let verdi = Double(første) else { return -1 }
    return verdi
}

let utLås = NSLock()
func si(_ s: String) {
    utLås.lock()
    print(s)
    fflush(stdout)
    utLås.unlock()
}

// MARK: - Statistikk

/// Snitt og standardfeil for en serie (parrede) observasjoner.
func snittOgSE(_ x: [Double]) -> (snitt: Double, se: Double, n: Int) {
    let n = x.count
    guard n > 1 else { return (x.first ?? 0, 0, n) }
    let m = x.reduce(0, +) / Double(n)
    let varians = x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n - 1)
    return (m, (varians / Double(n)).squareRoot(), n)
}

// MARK: - Konfigurasjoner

/// Dagens MesterAI slik den kjører på denne maskinen. `tak` > 0 hever
/// verdenstaket, slik at PIMC faktisk får brukt opp hele tidsbudsjettet
/// (standardtaket på 36 verdener er ellers bindende lenge før tiden er ute).
/// Hvor mange verdener budgivningen bruker. Budrunden er ikke det vi måler –
/// begge armer melder med den SAMME MesterAI-en – men den koster mer per
/// runde enn hele kortspillsøket til sammen (64 verdener × grådig utrulling
/// med eksakt hale, per sete, per runde). Å skru den ned gir mange ganger
/// flere målte runder for samme maskintid, symmetrisk for begge armer.
var budVerdener = 0

func pimcKonfig(tid: Double, tak: Int = 0, utenKlokke: Bool = false,
                sluttTak: Int = 0) -> MesterKonfig {
    var k = MesterKonfig.automatisk()
    k.tidsbudsjett = tid
    if tak > 0 {
        k.maksVerdener = tak
        k.maksVerdenerSluttspill = max(tak, k.maksVerdenerSluttspill)
    }
    // Sluttspillstaket på 1200 verdener er det dyreste MesterAI gjør. Skal
    // motstanderen være KLOKKEFRI (og dermed uavhengig av maskinlast) må det
    // ned, ellers koster ett trekk nesten et sekund.
    if sluttTak > 0 { k.maksVerdenerSluttspill = sluttTak }
    if budVerdener > 0 {
        k.verdenerVedBud = budVerdener
        k.verdenerVedBytte = max(4, budVerdener / 3)
    }
    if utenKlokke {
        // Motstanderen skal være IDENTISK fra punkt til punkt på
        // iterasjonskurven. Med klokke ville maskinlasten – som varierer –
        // gjøre PIMC sterkere eller svakere underveis, og kurven ville måle
        // lasten like mye som iterasjonstallet. Her får PIMC i stedet
        // nøyaktig sine egne verdenstak, uansett hvor lenge det tar.
        k.minVerdener = k.maksVerdener
        k.tidsbudsjett = 3600
    }
    return k
}

func isKonfig(tid: Double, tråder: Int = 1, blad: Int = 0, iterasjoner: Int = Int.max) -> ISMCTSKonfig {
    var k = ISMCTSKonfig()
    k.tidsbudsjett = tid
    k.tråder = tråder
    k.bladstikk = blad
    k.maksIterasjoner = iterasjoner
    return k
}

// MARK: - Seter

enum Kortvalg { case pimc, ismcts, tilfeldig }

/// Ett sete. Bud, byttekort og trumfvalg gjøres ALLTID av MesterAI – det er
/// bare kortspillet som skiftes ut, slik oppdraget krever. Med samme frø gir
/// begge armer derfor identiske bud, vrak og trumfvalg for samme utdeling,
/// og differansen måler kortspillet alene.
final class Sete {
    let nummer: Int
    let valg: Kortvalg
    let mester: MesterAI
    let søk: MesterISMCTS?
    var rng: SeededGenerator

    var søkTrekk = 0
    var iterasjoner = 0
    var verdener = 0
    var sekunder = 0.0
    var ulovlige = 0

    init(nummer: Int, valg: Kortvalg, mesterKonfig: MesterKonfig,
         isKonfig: ISMCTSKonfig?, frø: UInt64) {
        self.nummer = nummer
        self.valg = valg
        self.mester = MesterAI(sete: nummer, konfig: mesterKonfig,
                               seed: frø &+ UInt64(nummer) &* 7919 &+ 1)
        self.søk = valg == .ismcts
            ? MesterISMCTS(sete: nummer, konfig: isKonfig ?? ISMCTSKonfig(),
                           seed: frø &+ UInt64(nummer) &* 104_729 &+ 13)
            : nil
        self.rng = SeededGenerator(seed: frø &+ UInt64(nummer) &* 2_654_435_761 &+ 7)
    }

    func velgKort(engine: GameEngine) -> Card? {
        let lovlige = engine.lovligeKort(for: nummer)
        let start = Date()
        var kort: Card?
        switch valg {
        case .pimc:
            kort = mester.velgKort(engine: engine)
            if mester.sisteVerdenstall > 0 {
                verdener += mester.sisteVerdenstall
                søkTrekk += 1
                sekunder += Date().timeIntervalSince(start)
            }
        case .ismcts:
            kort = søk!.velgKort(engine: engine)
            if søk!.sisteIterasjoner > 0 {
                iterasjoner += søk!.sisteIterasjoner
                søkTrekk += 1
                sekunder += Date().timeIntervalSince(start)
            }
        case .tilfeldig:
            kort = lovlige.randomElement(using: &rng)
        }
        // Sanitet: alle motorer må holde seg til motorens egne lovlige kort.
        if let kort, !lovlige.contains(kort) { ulovlige += 1 }
        return kort ?? lovlige.first
    }
}

// MARK: - Én runde

func spillRunde(seed: UInt64, seter: [Sete]) -> [Int]? {
    let engine = GameEngine()
    engine.startRunde(seed: seed)
    var vakt = 0
    while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
        vakt += 1
        if vakt > 400 { return nil }
        switch engine.phase {
        case .budrunde:
            let s = engine.aktivBudgiver
            let lovlige = engine.lovligeBud(for: s)
            var bud = BidAction.pass
            let b = seter[s].mester.velgBud(engine: engine)
            if lovlige.contains(b) { bud = b }
            guard engine.giBud(seat: s, action: bud) else { return nil }
        case .byttekort:
            guard let s = engine.budgiverSeat else { return nil }
            let antall = engine.rules.antallByttekort
            var vrak = seter[s].mester.velgByttekort(engine: engine)
            if vrak.count != antall { vrak = Array(engine.hands[s].prefix(antall)) }
            guard engine.kastByttekort(vrak, seat: s) else { return nil }
        case .velgTrumf:
            guard let s = engine.budgiverSeat else { return nil }
            let valg = seter[s].mester.velgTrumfOgMakker(engine: engine)
            if let (suit, ønsket) = valg, engine.velgTrumf(suit: suit, ønsket: ønsket) { continue }
            var reddet = false
            for s2 in Suit.allCases {
                if let ø = engine.kortSomKanØnskes(trumf: s2).first,
                   engine.velgTrumf(suit: s2, ønsket: ø) { reddet = true; break }
            }
            if !reddet, !engine.velgTrumf(suit: .spar, ønsket: nil) { return nil }
        case .spill:
            let s = engine.aktivSpiller
            guard let kort = seter[s].velgKort(engine: engine),
                  engine.spill(kort: kort, seat: s) else { return nil }
        default:
            return nil
        }
    }
    return engine.sisteRunde?.poengEndring
}

// MARK: - Parallell over RUNDER

/// Kjører `antall` uavhengige runde-oppgaver fordelt på arbeidere.
///
/// Merk at parallelliteten ligger på RUNDENIVÅ, ikke inne i søket: begge
/// armene i en måling spiller i samme runde, på samme kjerne, under samme
/// last. Da er «samme tidsbudsjett» også samme regnekraft, og målingen er
/// ærlig. (Rotparallelliseringen inne i ISMCTS måles for seg med `traader=`.)
func parallelt(_ antall: Int, arbeidere: Int, _ arbeid: @escaping (Int) -> Void) {
    guard antall > 0 else { return }
    let n = max(1, min(arbeidere, antall))
    if n == 1 {
        for i in 0..<antall { arbeid(i) }
        return
    }
    let lås = NSLock()
    var neste = 0
    DispatchQueue.concurrentPerform(iterations: n) { _ in
        while true {
            lås.lock()
            let i = neste
            neste += 1
            lås.unlock()
            if i >= antall { break }
            arbeid(i)
        }
    }
}

let kjerner = ProcessInfo.processInfo.activeProcessorCount
/// Maskinen deles med andre kjøringer, så antall arbeidere er en parameter.
/// Standarden trekker fra lasten som allerede ligger der.
let standardArbeidere = max(1, tall("arbeidere", max(2, kjerner - Int(maskinlast().rounded()) - 2)))

// MARK: - 1) Sanitet

/// Spiller bare lovlige trekk, og slår tilfeldig spill klart.
func kjørSanitet(runder: Int, tid: Double) {
    si("== Sanitet: lovlighet og styrke mot tilfeldig spill (\(tid) s) ==")
    let arbeidere = min(standardArbeidere, runder)

    var ulovligeIS = 0
    var ulovligePIMC = 0
    var poengIS = [Double](repeating: 0, count: runder)
    var poengPIMC = [Double](repeating: 0, count: runder)
    var poengTilf = [Double](repeating: 0, count: runder)
    var ok = [Bool](repeating: false, count: runder)
    var iterSum = 0, iterTrekk = 0
    let teljeLås = NSLock()

    parallelt(runder, arbeidere: arbeidere) { r in
        let seed = UInt64(r) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let frø = seed &* 31 &+ 7
        var utfall: [Kortvalg: [Int]] = [:]
        var lokalUlovligIS = 0, lokalUlovligPIMC = 0
        var lokalIter = 0, lokalTrekk = 0
        for motor in [Kortvalg.ismcts, .pimc, .tilfeldig] {
            let seter = (0..<4).map {
                Sete(nummer: $0, valg: $0 == 0 ? motor : .tilfeldig,
                     mesterKonfig: pimcKonfig(tid: tid),
                     isKonfig: isKonfig(tid: tid), frø: frø)
            }
            guard let poeng = spillRunde(seed: seed, seter: seter) else { return }
            utfall[motor] = poeng
            if motor == .ismcts {
                lokalUlovligIS = seter.reduce(0) { $0 + $1.ulovlige }
                lokalIter = seter[0].iterasjoner
                lokalTrekk = seter[0].søkTrekk
            }
            if motor == .pimc { lokalUlovligPIMC = seter.reduce(0) { $0 + $1.ulovlige } }
        }
        guard let a = utfall[.ismcts], let b = utfall[.pimc], let c = utfall[.tilfeldig] else { return }
        teljeLås.lock()
        poengIS[r] = Double(a[0]); poengPIMC[r] = Double(b[0]); poengTilf[r] = Double(c[0])
        ulovligeIS += lokalUlovligIS; ulovligePIMC += lokalUlovligPIMC
        iterSum += lokalIter; iterTrekk += lokalTrekk
        ok[r] = true
        teljeLås.unlock()
    }

    let gyldige = (0..<runder).filter { ok[$0] }
    let iS = gyldige.map { poengIS[$0] }
    let pI = gyldige.map { poengPIMC[$0] }
    let tI = gyldige.map { poengTilf[$0] }
    let (mIS, seIS, n) = snittOgSE(iS)
    let (mPI, sePI, _) = snittOgSE(pI)
    let (mTI, seTI, _) = snittOgSE(tI)
    let (dIS, dseIS, _) = snittOgSE(zip(iS, tI).map(-))
    si(String(format: "  ulovlige trekk: ISMCTS %d, PIMC %d (av %d runder)", ulovligeIS, ulovligePIMC, n))
    si(String(format: "  sete 0 poeng/runde mot 3× tilfeldig: ISMCTS %+.2f ± %.2f | PIMC %+.2f ± %.2f | tilfeldig %+.2f ± %.2f",
              mIS, seIS, mPI, sePI, mTI, seTI))
    si(String(format: "  → ISMCTS − tilfeldig (parret): %+.2f ± %.2f (%.1f SE)", dIS, dseIS, dseIS > 0 ? dIS / dseIS : 0))
    si(String(format: "  iterasjoner per trekk: %.0f", iterTrekk > 0 ? Double(iterSum) / Double(iterTrekk) : 0))
    logg(["maaling": "sanitet", "runder": n, "tid": tid,
          "ulovlige_ismcts": ulovligeIS, "ulovlige_pimc": ulovligePIMC,
          "ismcts": mIS, "ismcts_se": seIS, "pimc": mPI, "pimc_se": sePI,
          "tilfeldig": mTI, "tilfeldig_se": seTI,
          "ismcts_minus_tilfeldig": dIS, "se": dseIS,
          "iterasjoner_per_trekk": iterTrekk > 0 ? Double(iterSum) / Double(iterTrekk) : 0])
}

// MARK: - 2) Fart

/// Hvor mange iterasjoner rekker ISMCTS – og hvor mange verdener rekker PIMC –
/// per trekk ved gitt tidsbudsjett, delt på midtspill og sluttspill.
func kjørFart(runder: Int, tid: Double) {
    si("== Fart ved \(tid) s per trekk ==")
    for blad in [0, 2, 4] {
        var sumIter = 0, sumTrekk = 0
        for r in 0..<runder {
            let seed = UInt64(r) &* 7919 &+ 101
            let seter = (0..<4).map {
                Sete(nummer: $0, valg: .ismcts, mesterKonfig: pimcKonfig(tid: tid),
                     isKonfig: isKonfig(tid: tid, blad: blad), frø: seed &* 31 &+ 7)
            }
            guard spillRunde(seed: seed, seter: seter) != nil else { continue }
            sumIter += seter.reduce(0) { $0 + $1.iterasjoner }
            sumTrekk += seter.reduce(0) { $0 + $1.søkTrekk }
        }
        let snitt = sumTrekk > 0 ? Double(sumIter) / Double(sumTrekk) : 0
        si(String(format: "  ISMCTS blad=%d: %.0f iterasjoner/trekk", blad, snitt))
        logg(["maaling": "fart", "motor": "ismcts", "blad": blad, "tid": tid,
              "per_trekk": snitt, "runder": runder])
    }
    for tak in [0, 100_000] {
        var sumV = 0, sumTrekk = 0
        for r in 0..<runder {
            let seed = UInt64(r) &* 7919 &+ 101
            let seter = (0..<4).map {
                Sete(nummer: $0, valg: .pimc, mesterKonfig: pimcKonfig(tid: tid, tak: tak),
                     isKonfig: nil, frø: seed &* 31 &+ 7)
            }
            guard spillRunde(seed: seed, seter: seter) != nil else { continue }
            sumV += seter.reduce(0) { $0 + $1.verdener }
            sumTrekk += seter.reduce(0) { $0 + $1.søkTrekk }
        }
        let snitt = sumTrekk > 0 ? Double(sumV) / Double(sumTrekk) : 0
        si(String(format: "  PIMC tak=%@: %.0f verdener/trekk", tak == 0 ? "standard" : "\(tak)", snitt))
        logg(["maaling": "fart", "motor": "pimc", "tak": tak, "tid": tid,
              "per_trekk": snitt, "runder": runder])
    }
}

// MARK: - 3) Hode mot hode

struct H2HSvar {
    var differanse = 0.0
    var se = 0.0
    var n = 0
    var isIterasjoner = 0.0
    var pimcVerdener = 0.0
}

/// Parret, speilet hode-mot-hode. For hver utdeling spilles runden to ganger:
/// først med ISMCTS på sete 0+2 og PIMC på 1+3, så speilvendt. Måltallet er
/// snittet av (ISMCTS-lagets poeng − PIMC-lagets poeng) over de to
/// orienteringene, slik at seteeffekter og utdelingsflaks kanselleres.
@discardableResult
func kjørH2H(runder: Int, isTid: Double, pimcTid: Double, tråder: Int, blad: Int, pimcTak: Int,
             fra: Int, iterasjoner: Int, merke: String, stille: Bool = false,
             pimcUtenKlokke: Bool = false, pimcSluttTak: Int = 0) -> H2HSvar {
    if !stille {
        si("== Hode mot hode (\(merke)): ISMCTS mot MesterAI ==")
    }
    let arbeidere = tråder > 1 ? 1 : min(standardArbeidere, runder)
    var diff = [Double](repeating: 0, count: runder)
    var ok = [Bool](repeating: false, count: runder)
    var sumIter = 0, sumIterTrekk = 0, sumVerd = 0, sumVerdTrekk = 0
    var ulovlige = 0
    let lås = NSLock()
    let start = Date()

    parallelt(runder, arbeidere: arbeidere) { r in
        let runde = fra + r + 1
        let seed = UInt64(runde) &* 2_654_435_761 &+ 17
        let frø = seed &* 31 &+ 7
        var rundeDiff = 0.0
        var lokalIter = 0, lokalIterTrekk = 0, lokalVerd = 0, lokalVerdTrekk = 0, lokalUlovlig = 0
        for orientering in 0..<2 {
            let isSeter: Set<Int> = orientering == 0 ? [0, 2] : [1, 3]
            let seter = (0..<4).map { s in
                Sete(nummer: s, valg: isSeter.contains(s) ? .ismcts : .pimc,
                     mesterKonfig: pimcKonfig(tid: pimcTid, tak: pimcTak,
                                              utenKlokke: pimcUtenKlokke, sluttTak: pimcSluttTak),
                     isKonfig: isKonfig(tid: isTid, tråder: tråder, blad: blad,
                                        iterasjoner: iterasjoner),
                     frø: frø)
            }
            guard let poeng = spillRunde(seed: seed, seter: seter) else { return }
            let isPoeng = isSeter.reduce(0) { $0 + poeng[$1] }
            let pimcPoeng = (0..<4).filter { !isSeter.contains($0) }.reduce(0) { $0 + poeng[$1] }
            rundeDiff += Double(isPoeng - pimcPoeng) / 2.0
            for s in seter {
                lokalUlovlig += s.ulovlige
                if isSeter.contains(s.nummer) {
                    lokalIter += s.iterasjoner; lokalIterTrekk += s.søkTrekk
                } else {
                    lokalVerd += s.verdener; lokalVerdTrekk += s.søkTrekk
                }
            }
        }
        lås.lock()
        diff[r] = rundeDiff
        ok[r] = true
        sumIter += lokalIter; sumIterTrekk += lokalIterTrekk
        sumVerd += lokalVerd; sumVerdTrekk += lokalVerdTrekk
        ulovlige += lokalUlovlig
        let ferdige = ok.filter { $0 }.count
        if !stille, ferdige % 25 == 0 {
            let (m, se, n) = snittOgSE((0..<runder).filter { ok[$0] }.map { diff[$0] })
            si(String(format: "  ... %d runder: %+.3f ± %.3f (%.0f s)", n, m, se, Date().timeIntervalSince(start)))
            logg(["maaling": "h2h_fremdrift", "merke": merke, "runder": n,
                  "differanse": m, "se": se, "tid": isTid])
        }
        lås.unlock()
    }

    let gyldige = (0..<runder).filter { ok[$0] }.map { diff[$0] }
    let (m, se, n) = snittOgSE(gyldige)
    var svar = H2HSvar(differanse: m, se: se, n: n)
    svar.isIterasjoner = sumIterTrekk > 0 ? Double(sumIter) / Double(sumIterTrekk) : 0
    svar.pimcVerdener = sumVerdTrekk > 0 ? Double(sumVerd) / Double(sumVerdTrekk) : 0
    if !stille {
        si(String(format: "  → ISMCTS − MesterAI: %+.3f ± %.3f poeng per lagrunde (n=%d, %.1f SE, %.0f s)",
                  m, se, n, se > 0 ? m / se : 0, Date().timeIntervalSince(start)))
        si(String(format: "     ISMCTS %.0f iterasjoner/trekk, PIMC %.0f verdener/trekk, ulovlige trekk: %d",
                  svar.isIterasjoner, svar.pimcVerdener, ulovlige))
    }
    logg(["maaling": "h2h", "merke": merke, "differanse": m, "se": se, "n": n,
          "se_avstand": se > 0 ? m / se : 0, "is_tid": isTid, "pimc_tid": pimcTid,
          "traader": tråder,
          "blad": blad, "pimc_tak": pimcTak, "fra": fra,
          "iterasjonstak": iterasjoner == Int.max ? -1 : iterasjoner,
          "ismcts_iter_per_trekk": svar.isIterasjoner,
          "pimc_verdener_per_trekk": svar.pimcVerdener,
          "ulovlige": ulovlige, "differanser": gyldige])
    return svar
}

// MARK: - 4) Iterasjonskurve

/// Styrke som funksjon av antall iterasjoner, mot en FAST motstander og på de
/// SAMME utdelingene, slik at punktene på kurven er parret med hverandre.
/// Motstanderen er den samme som i hovedmålingen (MesterAI ved fast
/// tidsbudsjett), slik at punktene på kurven kan leses på samme skala som
/// hovedtallet. Maskinlasten logges per punkt.
func kjørKurve(runder: Int, iterasjonsliste: [Int], pimcTid: Double, blad: Int,
               utenKlokke: Bool = false, sluttTak: Int = 0, merkelapp: String = "kurve") {
    let hvordan = utenKlokke
        ? "MesterAI med faste verdenstak (klokkefri, sluttspillstak \(sluttTak > 0 ? "\(sluttTak)" : "1200"))"
        : "MesterAI (\(pimcTid) s)"
    si("== Iterasjonskurve: ISMCTS mot \(hvordan) på identiske utdelinger ==")
    for n in iterasjonsliste {
        let svar = kjørH2H(runder: runder, isTid: 0, pimcTid: pimcTid, tråder: 1,
                           blad: blad, pimcTak: 0,
                           fra: 0, iterasjoner: n, merke: "\(merkelapp)_\(n)", stille: true,
                           pimcUtenKlokke: utenKlokke, pimcSluttTak: sluttTak)
        si(String(format: "  %6d iterasjoner: %+.3f ± %.3f poeng per lagrunde (n=%d, %.1f SE)",
                  n, svar.differanse, svar.se, svar.n, svar.se > 0 ? svar.differanse / svar.se : 0))
        logg(["maaling": "kurve_punkt", "iterasjoner": n, "differanse": svar.differanse,
              "se": svar.se, "n": svar.n, "pimc_tid": pimcTid, "blad": blad])
    }
}

// MARK: - 5) Bladevaluering

func kjørBlad(runder: Int, tid: Double) {
    si("== Bladevaluering: grådig utrulling mot dobbeltdummy på halen ==")
    for blad in [0, 2, 3, 4] {
        let svar = kjørH2H(runder: runder, isTid: tid, pimcTid: tid, tråder: 1,
                           blad: blad, pimcTak: 0,
                           fra: 100_000, iterasjoner: Int.max,
                           merke: "blad_\(blad)_tid_\(tid)", stille: true)
        si(String(format: "  blad=%d (%@): %+.3f ± %.3f (n=%d, %.1f SE, %.0f iter/trekk)",
                  blad, blad == 0 ? "ren grådig" : "DD på siste \(blad) stikk",
                  svar.differanse, svar.se, svar.n,
                  svar.se > 0 ? svar.differanse / svar.se : 0, svar.isIterasjoner))
    }
}

// MARK: - 6) Skalering: ISMCTS mot seg selv med færre iterasjoner

/// Den reneste testen på om metoden skalerer: samme algoritme på begge sider,
/// bare ulikt søkebudsjett. Alt annet – målfunksjon, utrullingspolicy,
/// verdensfordeling – er identisk, så en forskjell KAN bare komme av at
/// treet er bedre bygget. Mot PIMC drukner det samme signalet i at de to
/// motorene er forskjellige på mange måter samtidig.
///
/// Speilet og parret som hovedmålingen: samme utdelinger for alle punkter.
func kjørSkalering(runder: Int, basis: Int, liste: [Int], blad: Int) {
    si("== Skalering: ISMCTS(N) mot ISMCTS(\(basis)) på identiske utdelinger ==")
    for n in liste where n != basis {
        let arbeidere = min(standardArbeidere, runder)
        var diff = [Double](repeating: 0, count: runder)
        var ok = [Bool](repeating: false, count: runder)
        let lås = NSLock()
        let start = Date()
        parallelt(runder, arbeidere: arbeidere) { r in
            let seed = UInt64(r + 1) &* 2_654_435_761 &+ 17
            let frø = seed &* 31 &+ 7
            var rundeDiff = 0.0
            for orientering in 0..<2 {
                let store: Set<Int> = orientering == 0 ? [0, 2] : [1, 3]
                let seter = (0..<4).map { s in
                    Sete(nummer: s, valg: .ismcts, mesterKonfig: pimcKonfig(tid: 0.2),
                         isKonfig: isKonfig(tid: 0, blad: blad,
                                            iterasjoner: store.contains(s) ? n : basis),
                         frø: frø)
                }
                guard let poeng = spillRunde(seed: seed, seter: seter) else { return }
                let a = store.reduce(0) { $0 + poeng[$1] }
                let b = (0..<4).filter { !store.contains($0) }.reduce(0) { $0 + poeng[$1] }
                rundeDiff += Double(a - b) / 2.0
            }
            lås.lock()
            diff[r] = rundeDiff
            ok[r] = true
            lås.unlock()
        }
        let gyldige = (0..<runder).filter { ok[$0] }.map { diff[$0] }
        let (m, se, antall) = snittOgSE(gyldige)
        si(String(format: "  %6d mot %d: %+.3f ± %.3f poeng per lagrunde (n=%d, %.1f SE, %.0f s)",
                  n, basis, m, se, antall, se > 0 ? m / se : 0, Date().timeIntervalSince(start)))
        logg(["maaling": "h2h", "merke": "skalering_\(n)_mot_\(basis)",
              "differanse": m, "se": se, "n": antall, "blad": blad,
              "iterasjonstak": n, "basis": basis,
              "se_avstand": se > 0 ? m / se : 0, "differanser": gyldige])
    }
}

// MARK: - 7) Treets overtakelse

/// Måler den mekanistiske påstanden bak ISMCTS: at treet gradvis OVERTAR for
/// den faste utrullingspolicyen. For hvert iterasjonstall rapporteres
///
///   * tredybden ved rotbeslutningen (snitt og maks) – hvor mange av
///     beslutningene fram til rundeslutt som tas av treets egen statistikk,
///   * andelen av beslutningene som treet tar, totalt og per stikk.
///
/// Vokser disse med iterasjonstallet samtidig som styrken vokser, er det
/// treet som gjør jobben – ikke bare at flere utrullinger demper støyen.
func kjørTre(runder: Int, iterasjonsliste: [Int], blad: Int) {
    si("== Treets overtakelse: hvor mye av runden treet selv bestemmer ==")
    let stikkTotalt = 12
    for n in iterasjonsliste {
        var dybdeSum = 0.0, utvalgSum = 0.0, andelSum = 0.0, trekk = 0
        var maks = 0
        // Per stikk: hvor stor andel av beslutningene i det stikket treet tok.
        var perStikkAndel = [Double](repeating: 0, count: stikkTotalt + 1)
        var perStikkTeller = [Double](repeating: 0, count: stikkTotalt + 1)
        // Hvor dypt (i stikk regnet fra roten) treet rekker.
        var stikkDybdeSum = 0.0

        let arbeidere = min(standardArbeidere, runder)
        let lås = NSLock()
        parallelt(runder, arbeidere: arbeidere) { r in
            let seed = UInt64(r + 1) &* 2_654_435_761 &+ 17
            let frø = seed &* 31 &+ 7
            let seter = (0..<4).map {
                Sete(nummer: $0, valg: .ismcts, mesterKonfig: pimcKonfig(tid: 0.2),
                     isKonfig: isKonfig(tid: 0, blad: blad, iterasjoner: n), frø: frø)
            }
            var lokalProfiler: [Treprofil] = []
            let engine = GameEngine()
            engine.startRunde(seed: seed)
            var vakt = 0
            while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
                vakt += 1
                if vakt > 400 { return }
                switch engine.phase {
                case .budrunde:
                    let s = engine.aktivBudgiver
                    let lovlige = engine.lovligeBud(for: s)
                    let b = seter[s].mester.velgBud(engine: engine)
                    guard engine.giBud(seat: s, action: lovlige.contains(b) ? b : .pass) else { return }
                case .byttekort:
                    guard let s = engine.budgiverSeat else { return }
                    var vrak = seter[s].mester.velgByttekort(engine: engine)
                    if vrak.count != engine.rules.antallByttekort {
                        vrak = Array(engine.hands[s].prefix(engine.rules.antallByttekort))
                    }
                    guard engine.kastByttekort(vrak, seat: s) else { return }
                case .velgTrumf:
                    guard let s = engine.budgiverSeat else { return }
                    if let (suit, ø) = seter[s].mester.velgTrumfOgMakker(engine: engine),
                       engine.velgTrumf(suit: suit, ønsket: ø) { continue }
                    var reddet = false
                    for s2 in Suit.allCases {
                        if let ø = engine.kortSomKanØnskes(trumf: s2).first,
                           engine.velgTrumf(suit: s2, ønsket: ø) { reddet = true; break }
                    }
                    if !reddet, !engine.velgTrumf(suit: .spar, ønsket: nil) { return }
                case .spill:
                    let s = engine.aktivSpiller
                    guard let kort = seter[s].velgKort(engine: engine),
                          engine.spill(kort: kort, seat: s) else { return }
                    let p = seter[s].søk!.sisteTreprofil
                    if p.iterasjoner > 0 { lokalProfiler.append(p) }
                default:
                    return
                }
            }
            lås.lock()
            for p in lokalProfiler {
                dybdeSum += p.snittDybde
                utvalgSum += p.snittUtvalgsdybde
                andelSum += p.andelAvRunden
                maks = max(maks, p.maksDybde)
                trekk += 1
                // Snittdybden i STIKK: hvor mange stikk framover treet rekker.
                stikkDybdeSum += p.snittDybde / 4.0
                for (i, a) in p.andelTre.enumerated() {
                    let stikk = min(stikkTotalt, p.stikk(forBeslutning: i))
                    perStikkAndel[stikk] += a
                    perStikkTeller[stikk] += 1
                }
            }
            lås.unlock()
        }

        guard trekk > 0 else { continue }
        let snittDybde = dybdeSum / Double(trekk)
        let snittUtvalg = utvalgSum / Double(trekk)
        let andel = andelSum / Double(trekk)
        si(String(format: "  %6d iterasjoner: tredybde %.2f beslutninger (%.2f uten ekspansjon, maks %d) = %.1f %% av runden, %.2f stikk framover",
                  n, snittDybde, snittUtvalg, maks, andel * 100, stikkDybdeSum / Double(trekk)))
        var perStikk: [String: Any] = [:]
        var linje = "      per stikk (andel tre-beslutninger):"
        for st in 0..<stikkTotalt where perStikkTeller[st] > 0 {
            let a = perStikkAndel[st] / perStikkTeller[st]
            linje += String(format: " s%d:%.0f%%", st + 1, a * 100)
            perStikk["stikk_\(st + 1)"] = a
        }
        si(linje)
        logg(["maaling": "tre_overtakelse", "iterasjoner": n, "blad": blad,
              "snitt_dybde": snittDybde, "snitt_utvalgsdybde": snittUtvalg,
              "maks_dybde": maks, "andel_av_runden": andel,
              "stikk_framover": stikkDybdeSum / Double(trekk),
              "trekk": trekk, "runder": runder, "per_stikk": perStikk])
    }
}

// MARK: - Kjøring

budVerdener = tall("budverdener", 0)
si("kjerner=\(kjerner)  arbeidere=\(standardArbeidere)  budverdener=\(budVerdener == 0 ? 64 : budVerdener)  logg=\(loggSti)")
switch kommando {
case "sanitet":
    kjørSanitet(runder: tall("runder", 200), tid: desimal("tid", 0.2))
case "fart":
    kjørFart(runder: tall("runder", 20), tid: desimal("tid", 0.2))
case "h2h":
    kjørH2H(runder: tall("runder", 200),
            isTid: desimal("istid", desimal("tid", 0.2)),
            pimcTid: desimal("tid", 0.2),
            tråder: tall("traader", 1), blad: tall("blad", 0),
            pimcTak: tall("pimctak", 0), fra: tall("fra", 0),
            iterasjoner: tall("iter", Int.max),
            merke: tekst("merke", "h2h_tid_\(desimal("tid", 0.2))_blad_\(tall("blad", 0))_tak_\(tall("pimctak", 0))"),
            pimcUtenKlokke: tall("pimcfast", 0) == 1)
case "kurve":
    let liste = tekst("iter", "200,1000,5000,20000").split(separator: ",").compactMap { Int($0) }
    kjørKurve(runder: tall("runder", 120), iterasjonsliste: liste,
              pimcTid: desimal("pimctid", 0.2), blad: tall("blad", 0),
              utenKlokke: tall("pimcfast", 0) == 1, sluttTak: tall("pimcslutt", 0),
              merkelapp: tekst("merke", "kurve"))
case "blad":
    kjørBlad(runder: tall("runder", 150), tid: desimal("tid", 0.2))
case "tre":
    let liste = tekst("iter", "200,1000,5000,20000").split(separator: ",").compactMap { Int($0) }
    kjørTre(runder: tall("runder", 30), iterasjonsliste: liste, blad: tall("blad", 0))
case "skalering":
    let liste = tekst("iter", "1000,5000,20000").split(separator: ",").compactMap { Int($0) }
    kjørSkalering(runder: tall("runder", 300), basis: tall("basis", 200),
                  liste: liste, blad: tall("blad", 0))
default:
    si("""
    Bruk:
      ismcts sanitet runder=200 tid=0.2
      ismcts fart    runder=20  tid=0.2
      ismcts h2h     runder=200 tid=0.2 [traader=1] [blad=0] [pimctak=0] [fra=0]
      ismcts kurve   runder=120 iter=200,1000,5000,20000 [pimctid=0.2]
      ismcts blad    runder=150 tid=0.2
    """)
}
