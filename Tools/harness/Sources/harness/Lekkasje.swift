import Foundation

// MARK: - Fast konfig (lastuavhengig)

/// Alle målinger kjøres med LÅSTE verdenstall (min == maks) og et
/// tidsbudsjett som aldri binder. Da er resultatet identisk uansett hvor
/// mye annet som kjører på maskinen.
func fastKonfig(verdener: Int = 28, sluttspill: Int = 200,
                eksaktFra: Int = 6, bud: Int = 48, bytte: Int = 20) -> MesterKonfig {
    var k = MesterKonfig()
    k.maksVerdener = verdener
    k.minVerdener = verdener
    k.maksVerdenerSluttspill = sluttspill
    k.eksaktStikkGrense = eksaktFra
    k.tidsbudsjett = 1e9          // klokka skal aldri avgjøre noe
    k.verdenerVedBud = bud
    k.verdenerVedBytte = bytte
    return k
}

// MARK: - Dobbeltdummy-fasit på en faktisk utdeling

struct DDFasit {
    var par: Int              // budgiverlagets stikk ved perfekt spill fra start
    var faktisk: Int          // budgiverlagets faktiske stikk
    var tapPerSete: [Int]     // DD-tap i stikk per sete (alltid >= 0), fra stikk k
    var valgPerSete: [Int]    // antall reelle valg (>1 lovlig kort) per sete
    var lagTapStikk: [Int]    // budgiverlagets DD-tap per stikknummer
    var forsvarTapStikk: [Int]
    var tidligDelta: [Int]    // W-endring per stikk for stikkene FOR stikk k
    var wVedK: Int            // W ved starten av stikk k
}

/// Rekonstruerer starttilstanden for stikkspillet fra en ferdigspilt runde.
func startTilstand(
    hender: [[Card]], talon: [Card], kastet: [Card],
    budgiver: Int, makker: Int?, trumf: Suit, ønsket: Card?, erSolo: Bool
) -> Spilltilstand {
    var h = SIMD4<UInt64>(repeating: 0)
    for s in 0..<4 { h[s] = Kortmaske.maske(hender[s]) }
    h[budgiver] = (h[budgiver] | Kortmaske.maske(talon)) & ~Kortmaske.maske(kastet)
    var lag: UInt8 = 1 << UInt8(budgiver)
    if !erSolo, let makker { lag |= 1 << UInt8(makker) }
    return Spilltilstand(
        hender: h, leder: budgiver, pågående: [],
        trumfFarge: Kortmaske.fargeIndeks(trumf), lagMaske: lag,
        budgiver: budgiver, pliktkort: ønsket.map(Kortmaske.indeks),
        førsteStikk: true
    )
}

/// Går den faktisk spilte linja stikk for stikk og fordeler DD-tapet på
/// setene. W(p) = allerede vunne lagstikk + dobbeltdummy-verdien fra p.
/// W er konstant ved perfekt spill; hvert fall skyldes setet som nettopp
/// spilte (og hvert hopp skyldes forsvareren som nettopp spilte).
/// Gaar den faktisk spilte linja og fordeler DD-tapet paa setene.
/// W(p) = allerede vunne lagstikk + dobbeltdummy-verdien fra p. W er konstant
/// ved perfekt spill; hvert fall skyldes setet som nettopp spilte, og hvert
/// hopp skyldes forsvareren som nettopp spilte.
///
/// Full DD paa 12 stikk koster ~9 s, saa de første stikkene måles bare per
/// STIKK (samlet W-endring), og per-kort-attribusjonen starter i stikk
/// `fraStikk`. Naar W ikke endrer seg – det vanlige – holder et ensidig
/// nullvindu, og søket blir mange ganger billigere.

/// MTD(f): finn den eksakte dobbeltdummy-verdien med en følge av
/// nullvindu-søk rundt et gjett. Transposisjonstabellen deles mellom
/// søkene, saa dette er typisk mange ganger billigere enn ett bredt vindu.
func mtdf(_ dd: Dobbeltdummy, _ t: Spilltilstand, gjett: Int) -> Int {
    let maks = t.hender[t.leder].nonzeroBitCount + (t.pågående.isEmpty ? 0 : 1)
    var g = min(max(gjett, 0), maks)
    var nedre = -1
    var øvre = maks + 1
    while nedre < øvre {
        let beta = max(g, nedre + 1)
        g = dd.løsVindu(t, alfa: beta - 1, beta: beta)
        if g < beta { øvre = g } else { nedre = g }
    }
    return g
}

var ddProfil = false
var profilTid = [Double](repeating: 0, count: 16)

func ddAttribusjon(start: Spilltilstand, spilte: [Card], fraStikk: Int, gjettPar: Int) -> DDFasit {
    let dd = Dobbeltdummy()
    var t = start
    var banket = 0
    var tap = [0, 0, 0, 0]
    var valg = [0, 0, 0, 0]
    var tidlig: [Int] = []
    var lagTapS = [Int](repeating: 0, count: 12)
    var forsvarTapS = [Int](repeating: 0, count: 12)
    profilTid = [Double](repeating: 0, count: 16)
    let t0 = Date()
    var w = mtdf(dd, t, gjett: gjettPar)
    let par = w
    if ddProfil { print(String(format: "   p0 (12 stikk): %.1f s", Date().timeIntervalSince(t0))) }

    /// W etter trekket, med ensidig nullvindu naar retningen er kjent.
    func nyttW(erLag: Bool, forventet: Int) -> Int {
        let mål = forventet - banket
        if mål < 0 { return banket + dd.løs(t) }
        // Budgiverlaget kan bare tape paa eget trekk, forsvaret bare gi bort.
        let v = erLag
            ? dd.løsVindu(t, alfa: mål - 1, beta: mål)
            : dd.løsVindu(t, alfa: mål, beta: mål + 1)
        if erLag, v >= mål { return banket + mål }
        if !erLag, v <= mål { return banket + mål }
        return banket + mtdf(dd, t, gjett: mål)
    }

    var i = 0
    var stikkNr = 0
    while i < spilte.count {
        let perKort = stikkNr + 1 >= fraStikk
        var lagTrekk = false
        var forsvarTrekk = false
        for j in 0..<4 {
            let kort = spilte[i + j]
            let sete = Spillregler.aktivtSete(t)
            let erLag = start.lagMaske & (1 << UInt8(sete)) != 0
            if Spillregler.lovligMaske(t).nonzeroBitCount > 1 { valg[sete] += 1 }
            if erLag { lagTrekk = true } else { forsvarTrekk = true }
            if let vinner = Spillregler.utfør(&t, indeks: Kortmaske.indeks(kort)) {
                if start.lagMaske & (1 << UInt8(vinner)) != 0 { banket += 1 }
            }
            if perKort {
                let tk = Date()
                let nyW = nyttW(erLag: erLag, forventet: w)
                if ddProfil { profilTid[stikkNr] += Date().timeIntervalSince(tk) }
                let d = nyW - w
                if erLag, d < 0 { tap[sete] += -d; lagTapS[stikkNr] += -d }
                if !erLag, d > 0 { tap[sete] += d; forsvarTapS[stikkNr] += d }
                w = nyW
            }
        }
        _ = lagTrekk; _ = forsvarTrekk
        if !perKort {
            let tk = Date()
            let nyW = banket + mtdf(dd, t, gjett: w - banket)
            if ddProfil { profilTid[stikkNr] += Date().timeIntervalSince(tk) }
            tidlig.append(nyW - w)
            w = nyW
        }
        i += 4
        stikkNr += 1
    }
    if ddProfil {
        print("   per stikk: " + (0..<12).map { i0 in String(format: "%.1f", profilTid[i0]) }.joined(separator: " "))
    }
    return DDFasit(par: par, faktisk: banket, tapPerSete: tap, valgPerSete: valg,
                   lagTapStikk: lagTapS, forsvarTapStikk: forsvarTapS,
                   tidligDelta: tidlig, wVedK: par + tidlig.reduce(0, +))
}

// MARK: - Etterpåklokskap på vrak/trumf/etterlysning

/// Budgiverlagets stikk ved perfekt spill dersom budvinneren hadde vraket
/// `vrak`, valgt `trumf` og etterlyst `ønske`.
func parFor(
    utdelte: [[Card]], talon: [Card], budgiver: Int,
    vrak: UInt64, trumf: Int, ønske: Int?, erSolo: Bool, terskel: Int? = nil
) -> Int {
    var h = SIMD4<UInt64>(repeating: 0)
    for s in 0..<4 { h[s] = Kortmaske.maske(utdelte[s]) }
    h[budgiver] = (h[budgiver] | Kortmaske.maske(talon)) & ~vrak
    var lag: UInt8 = 1 << UInt8(budgiver)
    if !erSolo, let ønske {
        for s in 0..<4 where s != budgiver && h[s] & (1 << UInt64(ønske)) != 0 {
            lag |= 1 << UInt8(s)
        }
    }
    let t = Spilltilstand(
        hender: h, leder: budgiver, pågående: [], trumfFarge: trumf,
        lagMaske: lag, budgiver: budgiver, pliktkort: ønske, førsteStikk: true
    )
    let dd = Dobbeltdummy()
    guard let terskel else { return mtdf(dd, t, gjett: 8) }
    // Vi trenger bare a vite om alternativet SLAR terskelen; gjor det ikke,
    // holder grensen, og soket blir mye billigere.
    let v = dd.løsVindu(t, alfa: terskel, beta: terskel + 1)
    return v <= terskel ? v : dd.løs(t)
}

/// Vrak-kandidater for en trumffarge: MesterAIs egen heuristikk pluss
/// varianter som tømmer en kort sidefarge helt.
func vrakKandidaterFor(hånd16: UInt64, antall: Int, trumf: Int) -> [UInt64] {
    var ut = [MesterAI.heuristiskVrak(hånd: hånd16, antall: antall, trumfFarge: trumf)]
    for farge in 0..<4 where farge != trumf {
        let iFargen = hånd16 & Kortmaske.fargeMaske(farge)
        let lengde = iFargen.nonzeroBitCount
        guard lengde > 0, lengde <= antall else { continue }
        var vrak = iFargen
        if lengde < antall {
            vrak |= MesterAI.heuristiskVrak(
                hånd: hånd16 & ~iFargen, antall: antall - lengde, trumfFarge: trumf)
        }
        ut.append(vrak)
    }
    return ut
}

/// De `antall` høyeste kortene i fargen som budvinneren ikke har (og
/// dermed lovlig kan etterlyse).
func ønskeKandidater(hånd16: UInt64, trumf: Int, antall: Int) -> [Int] {
    var ut: [Int] = []
    for valør in stride(from: 12, through: 0, by: -1) {
        let idx = trumf * 13 + valør
        if hånd16 & (1 << UInt64(idx)) == 0 {
            ut.append(idx)
            if ut.count == antall { break }
        }
    }
    return ut
}

// MARK: - Poeng gitt et stikktall

/// Poengendring for hvert sete dersom budgiverlaget tar `lagStikk` og
/// forsvarsstikkene fordeles som `forsvar`.
func poengVed(bud: BidAction, budgiver: Int, makker: Int?, erSolo: Bool,
              lagStikk: Int, stikkPerSete: [Int], regler: GameRules) -> [Int] {
    let lag = erSolo ? [budgiver] : [budgiver, makker].compactMap { $0 }
    let klarte: Bool
    let budgiverPoeng: Int
    let makkerPoeng: Int
    switch bud {
    case .soloAmerikaner:
        klarte = lagStikk == regler.kortPerSpiller
        budgiverPoeng = regler.soloAmerikanerPoeng; makkerPoeng = 0
    case .amerikaner:
        klarte = lagStikk == regler.kortPerSpiller
        budgiverPoeng = regler.amerikanerPoeng; makkerPoeng = regler.amerikanerPoeng / 2
    case .bud(let n):
        klarte = lagStikk >= n
        budgiverPoeng = n * regler.budgiverFaktor; makkerPoeng = n
    case .pass:
        klarte = false; budgiverPoeng = 0; makkerPoeng = 0
    }
    var ut = [0, 0, 0, 0]
    for s in 0..<4 {
        if s == budgiver { ut[s] = klarte ? budgiverPoeng : -budgiverPoeng }
        else if lag.contains(s) { ut[s] = klarte ? makkerPoeng : -makkerPoeng }
        else { ut[s] = stikkPerSete[s] }
    }
    return ut
}

// MARK: - Én runde med full logg

struct RundeLogg {
    var frø: UInt64
    var budgiver: Int
    var budRang: Int          // n, 1000 = amerikaner, 2000 = solo
    var budHistorikk: [[Int]] // [sete, rang]
    var trumf: Int
    var makker: Int
    var erSolo: Bool
    var ønsket: Int
    var kastet: [Int]
    var hånd16: [Int]
    var utdelte: [[Int]]
    var stikkPerSete: [Int]
    var lagStikk: Int
    var klarte: Bool
    var poeng: [Int]
    var ddPar: Int
    var ddTap: [Int]
    var ddValg: [Int]
    var altPar: [String: Int]   // "trumf:vrakId:ønske" -> par
    var bestePar: Int
    var besteParSammeTrumf: Int
    var parPerTrumf: [Int]
    var parAndre: [Int]
    var tidligDelta: [Int]
    var gpAktuell: Int
    var gpBeste: Int
    var gpSammeTrumf: Int
    var gpSammeVrak: Int
    var gpPerTrumf: [Int]
    var gpAndre: [Int]
    var lagTapStikk: [Int]
    var forsvarTapStikk: [Int]

    var json: String {
        func arr(_ a: [Int]) -> String { "[" + a.map(String.init).joined(separator: ",") + "]" }
        var deler: [String] = []
        deler.append("\"fro\":\(frø)")
        deler.append("\"budgiver\":\(budgiver)")
        deler.append("\"bud\":\(budRang)")
        deler.append("\"budhist\":[" + budHistorikk.map(arr).joined(separator: ",") + "]")
        deler.append("\"trumf\":\(trumf)")
        deler.append("\"makker\":\(makker)")
        deler.append("\"solo\":\(erSolo)")
        deler.append("\"onsket\":\(ønsket)")
        deler.append("\"kastet\":\(arr(kastet))")
        deler.append("\"hånd16\":\(arr(hånd16))")
        deler.append("\"utdelte\":[" + utdelte.map(arr).joined(separator: ",") + "]")
        deler.append("\"stikk\":\(arr(stikkPerSete))")
        deler.append("\"lagstikk\":\(lagStikk)")
        deler.append("\"klarte\":\(klarte)")
        deler.append("\"poeng\":\(arr(poeng))")
        deler.append("\"ddpar\":\(ddPar)")
        deler.append("\"ddtap\":\(arr(ddTap))")
        deler.append("\"ddvalg\":\(arr(ddValg))")
        deler.append("\"bestepar\":\(bestePar)")
        deler.append("\"bestepar_sammetrumf\":\(besteParSammeTrumf)")
        deler.append("\"par_per_trumf\":\(arr(parPerTrumf))")
        deler.append("\"par_andre\":\(arr(parAndre))")
        deler.append("\"tidlig_delta\":\(arr(tidligDelta))")
        deler.append("\"gp_aktuell\":\(gpAktuell)")
        deler.append("\"gp_beste\":\(gpBeste)")
        deler.append("\"gp_sammetrumf\":\(gpSammeTrumf)")
        deler.append("\"gp_sammevrak\":\(gpSammeVrak)")
        deler.append("\"gp_per_trumf\":\(arr(gpPerTrumf))")
        deler.append("\"gp_andre\":\(arr(gpAndre))")
        deler.append("\"lagtap_stikk\":\(arr(lagTapStikk))")
        deler.append("\"forsvartap_stikk\":\(arr(forsvarTapStikk))")
        return "{" + deler.joined(separator: ",") + "}"
    }
}

/// Spiller én runde med de gitte AI-ene og returnerer full logg + fasit.
func lekkasjeRunde(frø: UInt64, grader: [AIDifficulty], medMotfakta: Bool,
                   fraStikk: Int = 3) -> RundeLogg? {
    let engine = GameEngine()
    let spillere = (0..<4).map {
        AIPlayer(seat: $0, difficulty: grader[$0], personality: .balansert)
    }
    engine.startRunde(seed: frø)
    var budHist: [[Int]] = []
    var vakt = 0
    while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
        vakt += 1
        if vakt > 400 { return nil }
        switch engine.phase {
        case .budrunde:
            let sete = engine.aktivBudgiver
            let bud = spillere[sete].velgBud(engine: engine)
            budHist.append([sete, bud.rang])
            guard engine.giBud(seat: sete, action: bud) else { return nil }
        case .byttekort:
            let sete = engine.budgiverSeat!
            guard engine.kastByttekort(spillere[sete].velgByttekort(engine: engine), seat: sete)
            else { return nil }
        case .velgTrumf:
            let sete = engine.budgiverSeat!
            guard let (suit, ønsket) = spillere[sete].velgTrumfOgMakker(engine: engine),
                  engine.velgTrumf(suit: suit, ønsket: ønsket) else { return nil }
        case .spill:
            let sete = engine.aktivSpiller
            guard let kort = spillere[sete].velgKort(engine: engine),
                  engine.spill(kort: kort, seat: sete) else { return nil }
        default:
            return nil
        }
    }
    guard let r = engine.sisteRunde, let trumf = engine.trumf,
          let budgiver = engine.budgiverSeat else { return nil }

    // Ved omdeling (alle passet) gjelder de siste utdelte hendene.
    let utdelte = engine.utdelteHender
    let talon = engine.utdeltTalon
    let start = startTilstand(
        hender: utdelte, talon: talon, kastet: engine.kastet,
        budgiver: budgiver, makker: r.makker, trumf: trumf,
        ønsket: engine.ønsketKort, erSolo: engine.erSolo)
    let lagFaktisk = [budgiver, r.makker ?? -1].filter { s in s >= 0 }.reduce(0) { a, s in a + r.stikkPerSpiller[s] }
    let fasit = ddAttribusjon(start: start, spilte: engine.spilteKort, fraStikk: fraStikk, gjettPar: lagFaktisk)
    let hånd16 = Kortmaske.maske(utdelte[budgiver]) | Kortmaske.maske(talon)

    var bestePar = fasit.par
    var besteSamme = fasit.par
    var parPerTrumf = [-1, -1, -1, -1]
    var parAndre = [-1, -1, -1, -1]
    var gpAktuell = -1
    var gpBeste = -1
    var gpSammeTrumf = -1
    var gpSammeVrak = -1
    var gpPerTrumf = [-1, -1, -1, -1]
    var gpAndre = [-1, -1, -1, -1]
    if medMotfakta {
        let antall = engine.rules.antallByttekort
        let faktiskTrumf = Kortmaske.fargeIndeks(trumf)
        let faktiskVrak = Kortmaske.maske(engine.kastet)
        let faktiskØnske = engine.ønsketKort.map(Kortmaske.indeks)

        // Etterpåklokskap paa vrak/trumf/etterlysning. Full dobbeltdummy paa
        // 12 stikk koster ~40 s per stilling, saa alternativene måles med
        // MesterAIs EGEN evaluator kjørt med åpne kort (gradig fram til 6
        // stikk igjen, eksakt derfra). Samme målestokk for alle kandidater,
        // og for det faktiske valget - forskjellen er det som teller.
        func gp(_ vrak: UInt64, _ t: Int, _ ø: Int?, budgiver b: Int, hender: [[Card]]) -> Int {
            var h = SIMD4<UInt64>(repeating: 0)
            for i in 0..<4 { h[i] = Kortmaske.maske(hender[i]) }
            h[b] = (h[b] | Kortmaske.maske(talon)) & ~vrak
            var lag: UInt8 = 1 << UInt8(b)
            if !engine.erSolo, let ø {
                for i in 0..<4 where i != b && h[i] & (1 << UInt64(ø)) != 0 { lag |= 1 << UInt8(i) }
            }
            let st = Spilltilstand(hender: h, leder: b, pågående: [], trumfFarge: t,
                                   lagMaske: lag, budgiver: b, pliktkort: ø, førsteStikk: true)
            return GrådigSpiller.lagStikk(st, eksaktFra: 6)
        }

        gpAktuell = gp(faktiskVrak, faktiskTrumf, faktiskØnske, budgiver: budgiver, hender: utdelte)
        for t in 0..<4 {
            var vrakSett = vrakKandidaterFor(hånd16: hånd16, antall: antall, trumf: t)
            if t == faktiskTrumf { vrakSett.append(faktiskVrak) }
            let ønsker: [Int?] = engine.erSolo
                ? [nil] + ønskeKandidater(hånd16: hånd16, trumf: t, antall: 3).map { i in Optional(i) }
                : ønskeKandidater(hånd16: hånd16, trumf: t, antall: 4).map { i in Optional(i) }
            var beste = -1
            var besteFastVrak = -1
            for vrak in Set(vrakSett) where vrak.nonzeroBitCount == antall && vrak & ~hånd16 == 0 {
                for ø in ønsker {
                    let v = gp(vrak, t, ø, budgiver: budgiver, hender: utdelte)
                    beste = max(beste, v)
                    if vrak == faktiskVrak { besteFastVrak = max(besteFastVrak, v) }
                }
            }
            gpPerTrumf[t] = beste
            if t == faktiskTrumf {
                gpSammeTrumf = beste
                gpSammeVrak = besteFastVrak
            }
            gpBeste = max(gpBeste, beste)
        }
        // Hva ville HVER av de andre fått som budvinner? Avslører om
        // MesterAI passer paa hender som burde meldt.
        for sx in 0..<4 where sx != budgiver {
            let deres16 = Kortmaske.maske(utdelte[sx]) | Kortmaske.maske(talon)
            var beste = -1
            for t in 0..<4 {
                let vrak = MesterAI.heuristiskVrak(hånd: deres16, antall: antall, trumfFarge: t)
                for ø in ønskeKandidater(hånd16: deres16, trumf: t, antall: 2) {
                    beste = max(beste, gp(vrak, t, ø, budgiver: sx, hender: utdelte))
                }
            }
            gpAndre[sx] = beste
        }
    }

    return RundeLogg(
        frø: frø, budgiver: budgiver, budRang: r.bud.rang, budHistorikk: budHist,
        trumf: Kortmaske.fargeIndeks(trumf), makker: r.makker ?? -1,
        erSolo: engine.erSolo, ønsket: engine.ønsketKort.map(Kortmaske.indeks) ?? -1,
        kastet: engine.kastet.map(Kortmaske.indeks),
        hånd16: Kortmaske.indekser(hånd16),
        utdelte: utdelte.map { Kortmaske.indekser(Kortmaske.maske($0)) },
        stikkPerSete: r.stikkPerSpiller,
        lagStikk: fasit.faktisk, klarte: r.klarte, poeng: r.poengEndring,
        ddPar: fasit.par, ddTap: fasit.tapPerSete, ddValg: fasit.valgPerSete,
        altPar: [:], bestePar: bestePar, besteParSammeTrumf: besteSamme,
        parPerTrumf: parPerTrumf, parAndre: parAndre,
        tidligDelta: fasit.tidligDelta,
        gpAktuell: gpAktuell, gpBeste: gpBeste, gpSammeTrumf: gpSammeTrumf,
        gpSammeVrak: gpSammeVrak, gpPerTrumf: gpPerTrumf, gpAndre: gpAndre,
        lagTapStikk: fasit.lagTapStikk, forsvarTapStikk: fasit.forsvarTapStikk)
}

// MARK: - Skriving til varig fil

final class Loggfil {
    private let sti: String
    private let handle: FileHandle?
    init(_ sti: String) {
        self.sti = sti
        let dir = (sti as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: sti) {
            FileManager.default.createFile(atPath: sti, contents: nil)
        }
        handle = FileHandle(forWritingAtPath: sti)
        handle?.seekToEndOfFile()
    }
    func skriv(_ linje: String) {
        guard let d = (linje + "\n").data(using: .utf8) else { return }
        handle?.write(d)
        try? handle?.synchronize()      // VM-en har krasjet før – flush hver linje
    }
}
