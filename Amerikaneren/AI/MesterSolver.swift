import Foundation

/// Full spilltilstand for én samplet verden, slik søkeren ser den.
struct Spilltilstand {
    var hender: SIMD4<UInt64>
    var leder: Int
    var pågående: [(sete: Int, indeks: Int)]
    var trumfFarge: Int?
    var lagMaske: UInt8      // budgiverlagets seter
    var budgiver: Int
    var pliktkort: Int?      // etterlyst kort, håndheves i første stikk
    var førsteStikk: Bool
}

/// Felles trekklogikk for søker og utspillspolicy. Speiler `GameEngine`s
/// regler (følg farge, budvinnerens trumfutspill og makkerplikt i første
/// stikk) på bitmasker.
enum Spillregler {
    static func aktivtSete(_ t: Spilltilstand) -> Int {
        (t.leder + t.pågående.count) % 4
    }

    /// Slår `ny` det hittil beste kortet i stikket?
    static func slår(_ ny: Int, _ beste: Int, trumfFarge: Int?) -> Bool {
        let nyFarge = ny / 13, besteFarge = beste / 13
        if nyFarge == besteFarge { return ny % 13 > beste % 13 }
        return nyFarge == trumfFarge
    }

    static func vinner(_ spill: [(sete: Int, indeks: Int)], trumfFarge: Int?) -> Int {
        var beste = spill[0]
        for kandidat in spill.dropFirst() where slår(kandidat.indeks, beste.indeks, trumfFarge: trumfFarge) {
            beste = kandidat
        }
        return beste.sete
    }

    static func lovligMaske(_ t: Spilltilstand) -> UInt64 {
        let sete = aktivtSete(t)
        let hånd = t.hender[sete]
        var m = hånd
        if let første = t.pågående.first {
            let følg = hånd & Kortmaske.fargeMaske(første.indeks / 13)
            if følg != 0 { m = følg }
        } else if t.førsteStikk, sete == t.budgiver, let trumf = t.trumfFarge {
            // Utspillsplikt: budvinneren åpner første stikk i trumf (om mulig).
            let trumfKort = hånd & Kortmaske.fargeMaske(trumf)
            if trumfKort != 0 { m = trumfKort }
        }
        if t.førsteStikk, let plikt = t.pliktkort, sete != t.budgiver,
           m & (1 << UInt64(plikt)) != 0 {
            return 1 << UInt64(plikt)
        }
        return m
    }

    /// Legger kortet, og fullfører stikket når fjerdemann har lagt.
    /// Returnerer vinnersetet når stikket ble avgjort.
    @discardableResult
    static func utfør(_ t: inout Spilltilstand, indeks: Int) -> Int? {
        let sete = aktivtSete(t)
        t.hender[sete] &= ~(1 << UInt64(indeks))
        t.pågående.append((sete, indeks))
        guard t.pågående.count == 4 else { return nil }
        let vinnerSete = vinner(t.pågående, trumfFarge: t.trumfFarge)
        t.leder = vinnerSete
        t.pågående.removeAll(keepingCapacity: true)
        t.førsteStikk = false
        t.pliktkort = nil
        return vinnerSete
    }

    /// Reduserer lovlige kort til én representant per «likeverdig» sekvens:
    /// kort som ligger inntil hverandre blant de gjenværende kortene er
    /// utbyttbare, så bare det høyeste i hver egen sekvens prøves.
    static func reduserteTrekk(lovlig: UInt64, union: UInt64) -> [Int] {
        var trekk: [Int] = []
        for farge in 0..<4 {
            let fm = Kortmaske.fargeMaske(farge)
            guard lovlig & fm != 0 else { continue }
            var u = union & fm
            var forrigeVarMin = false
            while u != 0 {
                let idx = 63 - u.leadingZeroBitCount
                u &= ~(1 << UInt64(idx))
                if lovlig & (1 << UInt64(idx)) != 0 {
                    if !forrigeVarMin { trekk.append(idx) }
                    forrigeVarMin = true
                } else {
                    forrigeVarMin = false
                }
            }
        }
        return trekk
    }
}

/// Eksakt dobbeltdummy-løser: gitt åpne kort spiller begge lag optimalt, og
/// løseren returnerer hvor mange av de gjenstående stikkene budgiverlaget
/// tar. Alfa-beta med transposisjonstabell og sekvens-reduksjon.
final class Dobbeltdummy {
    private struct Nøkkel: Hashable {
        let hender: SIMD4<UInt64>
        let leder: Int8
        let lag: UInt8       // budgiverlaget – MÅ med for deling på tvers av verdener (makkeren varierer)
    }
    private struct Grense {
        var nedre: Int8
        var øvre: Int8
    }

    private var tabell: [Nøkkel: Grense] = [:]

    init() {
        tabell.reserveCapacity(1 << 14)
    }

    /// Tømmer transposisjonstabellen. Kalles ved rundestart (ny trumf gjør
    /// gamle verdier ugyldige), så TT-en trygt kan bæres gjennom hele runden.
    func tøm() { tabell.removeAll(keepingCapacity: true) }

    /// Relativ-rang-kanonisering: bare kortenes innbyrdes rekkefølge i hver
    /// farge betyr noe for verdien, så mange absolutte stillinger deler samme
    /// TT-nøkkel. Fargeidentitet (trumf) bevares. Gir vesentlig færre noder.
    static func kanonisk(_ hender: SIMD4<UInt64>) -> SIMD4<UInt64> {
        var c = SIMD4<UInt64>(repeating: 0)
        let uni = hender[0] | hender[1] | hender[2] | hender[3]
        for s in 0..<4 {
            let skift = UInt64(s * 13)
            let u = (uni & Kortmaske.fargeMaske(s)) >> skift
            for p in 0..<4 {
                let h = (hender[p] & Kortmaske.fargeMaske(s)) >> skift
                c[p] |= pext(h, u) << skift
            }
        }
        return c
    }
    /// Parallell bit-ekstraksjon (pext-emulering; ingen maskinvare-intrinsic i Swift).
    private static func pext(_ v: UInt64, _ mask: UInt64) -> UInt64 {
        var res: UInt64 = 0, m = mask, bb: UInt64 = 1
        while m != 0 {
            let lsb = m & (~m &+ 1)
            if v & lsb != 0 { res |= bb }
            bb <<= 1
            m &= m &- 1
        }
        return res
    }

    func løs(_ t: Spilltilstand) -> Int {
        let maks = t.hender[t.leder].nonzeroBitCount + (t.pågående.isEmpty ? 0 : 1)
        return løs(t, alfa: -1, beta: maks + 1)
    }

    private func løs(_ t: Spilltilstand, alfa: Int, beta: Int) -> Int {
        let union = t.hender[0] | t.hender[1] | t.hender[2] | t.hender[3]
        if union == 0 { return 0 }

        var alfa = alfa, beta = beta
        var nøkkel: Nøkkel?
        var maks = Int.max
        if t.pågående.isEmpty {
            maks = t.hender[t.leder].nonzeroBitCount
            if alfa >= maks { return maks }
            if beta <= 0 { return 0 }
            let k = Nøkkel(hender: Dobbeltdummy.kanonisk(t.hender), leder: Int8(t.leder), lag: t.lagMaske)
            nøkkel = k
            if let g = tabell[k] {
                if Int(g.nedre) >= beta { return Int(g.nedre) }
                if Int(g.øvre) <= alfa { return Int(g.øvre) }
                alfa = max(alfa, Int(g.nedre))
                beta = min(beta, Int(g.øvre))
            }
        }

        let sete = Spillregler.aktivtSete(t)
        let erMaks = t.lagMaske & (1 << UInt8(sete)) != 0
        let unionMedStikk = t.pågående.reduce(union) { $0 | (1 << UInt64($1.indeks)) }
        let trekk = Spillregler.reduserteTrekk(lovlig: Spillregler.lovligMaske(t), union: unionMedStikk)

        var beste = erMaks ? -1 : Int.max
        var a = alfa, b = beta
        for indeks in trekk {
            var barn = t
            let vinnerSete = Spillregler.utfør(&barn, indeks: indeks)
            let verdi: Int
            if let vinnerSete {
                let bonus = t.lagMaske & (1 << UInt8(vinnerSete)) != 0 ? 1 : 0
                verdi = bonus + løs(barn, alfa: a - bonus, beta: b - bonus)
            } else {
                verdi = løs(barn, alfa: a, beta: b)
            }
            if erMaks {
                if verdi > beste { beste = verdi }
                if beste > a { a = beste }
                if beste >= b { break }
            } else {
                if verdi < beste { beste = verdi }
                if beste < b { b = beste }
                if beste <= a { break }
            }
        }

        if let nøkkel {
            var g = tabell[nøkkel] ?? Grense(nedre: 0, øvre: Int8(maks))
            if beste <= alfa {
                g.øvre = min(g.øvre, Int8(beste))
            } else if beste >= beta {
                g.nedre = max(g.nedre, Int8(beste))
            } else {
                g.nedre = Int8(beste)
                g.øvre = Int8(beste)
            }
            tabell[nøkkel] = g
        }
        return beste
    }
}

/// Rask, grådig fullinformasjonspolicy brukt til utrullinger tidlig i runden:
/// trekker trumf for budgiverlaget, spiller sikre vinnere, dekker makker og
/// stikker billigst mulig. Ikke optimal, men god – og lik for alle seter, så
/// sammenlikningen mellom kandidatkort blir rettferdig.
enum GrådigSpiller {
    /// Spiller ut til `stoppVedStikkIgjen` stikk gjenstår (0 = hele veien),
    /// og teller stikk per sete underveis.
    static func spillUt(
        _ start: Spilltilstand,
        stoppVedStikkIgjen: Int = 0,
        perSete: inout [Int]
    ) -> Spilltilstand {
        var t = start
        while t.hender[0] | t.hender[1] | t.hender[2] | t.hender[3] != 0 {
            let stikkIgjen = t.hender[t.leder].nonzeroBitCount + (t.pågående.isEmpty ? 0 : 1)
            if stikkIgjen <= stoppVedStikkIgjen { break }
            let valg = velg(t)
            if let vinnerSete = Spillregler.utfør(&t, indeks: valg) {
                perSete[vinnerSete] += 1
            }
        }
        return t
    }

    /// Spiller runden ut – grådig fram til `eksaktFra` stikk gjenstår og
    /// eksakt derfra – og returnerer budgiverlagets stikk.
    static func lagStikk(_ start: Spilltilstand, eksaktFra: Int = 0) -> Int {
        var perSete = [0, 0, 0, 0]
        let rest = spillUt(start, stoppVedStikkIgjen: eksaktFra, perSete: &perSete)
        var stikk = eksaktFra > 0 ? Dobbeltdummy().løs(rest) : 0
        for s in 0..<4 where start.lagMaske & (1 << UInt8(s)) != 0 {
            stikk += perSete[s]
        }
        return stikk
    }

    static func velg(_ t: Spilltilstand) -> Int {
        let m = Spillregler.lovligMaske(t)
        if m & (m - 1) == 0 { return Kortmaske.laveste(m) }

        let sete = Spillregler.aktivtSete(t)
        let mittLag: UInt8 = t.lagMaske & (1 << UInt8(sete)) != 0 ? t.lagMaske : ~t.lagMaske & 0xF
        let fiender = (0..<4).filter { mittLag & (1 << UInt8($0)) == 0 }
        let union = t.hender[0] | t.hender[1] | t.hender[2] | t.hender[3]

        guard let ledet = t.pågående.first else {
            return velgUtspill(t, m: m, sete: sete, fiender: fiender, union: union)
        }

        let ledFarge = ledet.indeks / 13
        var besteSete = ledet.sete
        var besteIdx = ledet.indeks
        for spill in t.pågående.dropFirst() where Spillregler.slår(spill.indeks, besteIdx, trumfFarge: t.trumfFarge) {
            besteSete = spill.sete
            besteIdx = spill.indeks
        }
        let gjenstår = (t.pågående.count + 1)..<4
        let fienderIgjen = gjenstår.map { (t.leder + $0) % 4 }.filter { fiender.contains($0) }
        let makkereIgjen = gjenstår.map { (t.leder + $0) % 4 }.filter { !fiender.contains($0) && $0 != sete }
        let vinnerErVår = mittLag & (1 << UInt8(besteSete)) != 0

        func noenKanSlå(_ seter: [Int], _ idx: Int) -> Bool {
            seter.contains { kanSlå(t, sete: $0, beste: idx, ledFarge: ledFarge) }
        }

        // Laget har stikket, og ingen fiende bak kan ta det: legg billigst.
        if vinnerErVår, !noenKanSlå(fienderIgjen, besteIdx) {
            return billigste(m, trumfFarge: t.trumfFarge)
        }

        // Prøv billigste vinnerkort som står seg mot fiendene bak.
        let vinnere = Kortmaske.indekser(m)
            .filter { Spillregler.slår($0, besteIdx, trumfFarge: t.trumfFarge) }
            .sorted { Kortmaske.kostnad($0, trumfFarge: t.trumfFarge) < Kortmaske.kostnad($1, trumfFarge: t.trumfFarge) }
        if let holdbar = vinnere.first(where: { !noenKanSlå(fienderIgjen, $0) }) {
            return holdbar
        }
        if vinnerErVår {
            return billigste(m, trumfFarge: t.trumfFarge)
        }
        // Makker bak kan fortsatt vinne stikket: dukk.
        if noenKanSlå(makkereIgjen, besteIdx) {
            return billigste(m, trumfFarge: t.trumfFarge)
        }
        // Sistemann presser med billigste vinner om det finnes.
        if let vinner = vinnere.first { return vinner }
        return billigste(m, trumfFarge: t.trumfFarge)
    }

    private static func velgUtspill(_ t: Spilltilstand, m: UInt64, sete: Int, fiender: [Int], union: UInt64) -> Int {
        // Budgiverlaget trekker trumf så lenge fiendene faktisk har trumf.
        if let trumf = t.trumfFarge, t.lagMaske & (1 << UInt8(sete)) != 0 {
            let tm = Kortmaske.fargeMaske(trumf)
            let fiendtligTrumf = fiender.reduce(UInt64(0)) { $0 | t.hender[$1] } & tm
            let minTrumf = m & tm
            if fiendtligTrumf != 0, minTrumf != 0 {
                return Kortmaske.høyeste(minTrumf)
            }
        }
        // Sikre vinnere: høyeste gjenværende kort i en farge fienden må følge
        // (eller ikke kan trumfe).
        for farge in 0..<4 where farge != t.trumfFarge {
            let fm = Kortmaske.fargeMaske(farge)
            let mine = m & fm
            guard mine != 0 else { continue }
            let topp = Kortmaske.høyeste(mine)
            guard topp == Kortmaske.høyeste(union & fm) else { continue }
            let holdbar = fiender.allSatisfy { f in
                t.hender[f] & fm != 0
                    || t.trumfFarge == nil
                    || t.hender[f] & Kortmaske.fargeMaske(t.trumfFarge!) == 0
            }
            if holdbar { return topp }
        }
        // Prinsipielt default-utspill: led lavt fra lengste sidefarge (etabler
        // lengde) i stedet for det globalt billigste kortet. Løftet
        // åpnings-optimaliteten (11 kort 88 %→94 %) i C++-måling.
        return ledFraLengde(m, trumfFarge: t.trumfFarge)
    }

    /// Led lavt fra den lengste sidefargen (ikke trumf). Utvikler stikk i lange
    /// farger; makkeren er oftere kort og kan trumfe.
    private static func ledFraLengde(_ m: UInt64, trumfFarge: Int?) -> Int {
        var besteFarge = -1, besteLengde = 0
        for f in 0..<4 where f != trumfFarge {
            let len = (m & Kortmaske.fargeMaske(f)).nonzeroBitCount
            if len > besteLengde { besteLengde = len; besteFarge = f }
        }
        if besteFarge < 0 { return billigste(m, trumfFarge: trumfFarge) }
        return Kortmaske.laveste(m & Kortmaske.fargeMaske(besteFarge))
    }

    private static func kanSlå(_ t: Spilltilstand, sete: Int, beste: Int, ledFarge: Int) -> Bool {
        let hånd = t.hender[sete]
        let følg = hånd & Kortmaske.fargeMaske(ledFarge)
        if følg != 0 {
            guard beste / 13 == ledFarge else { return false }  // stikket er alt trumfet
            return Kortmaske.høyeste(følg) % 13 > beste % 13
        }
        guard let trumf = t.trumfFarge else { return false }
        let minTrumf = hånd & Kortmaske.fargeMaske(trumf)
        guard minTrumf != 0 else { return false }
        if beste / 13 == trumf { return Kortmaske.høyeste(minTrumf) > beste }
        return true
    }

    private static func billigste(_ m: UInt64, trumfFarge: Int?) -> Int {
        Kortmaske.indekser(m).min {
            Kortmaske.kostnad($0, trumfFarge: trumfFarge) < Kortmaske.kostnad($1, trumfFarge: trumfFarge)
        }!
    }
}
