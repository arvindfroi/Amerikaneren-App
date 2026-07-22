import Foundation

/// Turneringsevolusjon over `MesterVekter`: en populasjon vektsett spiller
/// mot hverandre ved bord à fire (alle på President-nivå, individuell
/// poengsum), de beste overlever og avler neste generasjon. Fitness måles
/// med speilrotasjoner (hver kandidat sitter i hvert sete på samme
/// utdeling) og tilfeldige poengstillinger, så både kortflaks, seteflaks
/// og matchsituasjonene dekkes. Hver `ankerHver`. generasjon måles
/// turneringsvinneren mot standardvektene i parrede runder mot 3×
/// Vanskelig – det er fremgangsmåleren, og bare den kan krones til
/// «beste noensinne». Alt sjekkpunktes til katalogen og kan gjenopptas;
/// en fil ved navn STOPP stanser løkka kontrollert ved neste grense.
struct Evolusjon {
    struct Innstillinger {
        var katalog = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("evolusjon").path
        var populasjon = 20
        var bordStørrelse = 4
        var runderPerBord = 24     // utdelinger per bord (hver spilles 4 veier)
        var omstokk = 2            // ganger bordene stokkes om per generasjon
        var tidsbudsjett = 0.1
        var ankerHver = 5          // generasjoner mellom ankermålinger
        var ankerRunder = 400      // parrede runder per ankermåling
        var maksGenerasjoner = 0   // 0 = til STOPP-fila dukker opp
        var sigma = 0.12           // mutasjonssteg (andel av genets skala)
        var rate = 0.35            // andel gener som muteres
        var elite = 5              // antall som overlever uendret
    }

    struct Tilstand: Codable {
        var generasjon = 0
        var populasjon: [MesterVekter] = []
        var besteNoensinne: MesterVekter?
        var besteAnkerDiff = -1e18
        var ankerRå: [[Kode]] = []   // per måling: [(generasjon, diff), (0, se)]
        struct Kode: Codable { var i = 0; var d = 0.0 }
    }

    let inn: Innstillinger
    private let kø = DispatchQueue(label: "evolusjon.samling")

    init(innstillinger: Innstillinger) {
        self.inn = innstillinger
    }

    // MARK: - Hovedløkka

    func kjør() {
        try? FileManager.default.createDirectory(
            atPath: inn.katalog, withIntermediateDirectories: true)
        var tilstand = lesSjekkpunkt() ?? Tilstand()
        if tilstand.populasjon.isEmpty {
            var rng = SeededGenerator(seed: 0xE701)
            let standard = MesterVekter()
            tilstand.populasjon = [standard] + (1..<inn.populasjon).map { _ in
                standard.mutert(sigma: inn.sigma, rate: 0.5, rng: &rng)
            }
            logg("generasjon 0: populasjon sådd fra standardvektene (\(inn.populasjon) individer)")
        } else {
            logg("gjenopptar fra generasjon \(tilstand.generasjon) (\(tilstand.populasjon.count) individer)")
        }

        while inn.maksGenerasjoner == 0 || tilstand.generasjon < inn.maksGenerasjoner {
            if FileManager.default.fileExists(atPath: inn.katalog + "/STOPP") {
                logg("STOPP-fil funnet – avslutter kontrollert etter generasjon \(tilstand.generasjon)")
                break
            }
            let start = Date()
            let poeng = spillGenerasjon(tilstand.populasjon, generasjon: tilstand.generasjon)
            let rangert = poeng.enumerated().sorted { $0.element > $1.element }
            let beste = rangert[0].offset

            // Ankermåling: turneringsvinneren mot standardvektene.
            var ankerTekst = ""
            if tilstand.generasjon % inn.ankerHver == 0 {
                let (diff, se) = anker(tilstand.populasjon[beste], generasjon: tilstand.generasjon)
                tilstand.ankerRå.append([.init(i: tilstand.generasjon, d: diff), .init(i: 0, d: se)])
                ankerTekst = String(format: " · anker %+.2f ± %.2f", diff, se)
                if diff - se > tilstand.besteAnkerDiff {
                    tilstand.besteAnkerDiff = diff - se
                    tilstand.besteNoensinne = tilstand.populasjon[beste]
                    ankerTekst += " (ny beste noensinne)"
                }
            }

            // Seleksjon: eliten overlever, resten avles fra den.
            var rng = SeededGenerator(seed: 0xAB1 &+ UInt64(tilstand.generasjon) &* 7919)
            let elite = rangert.prefix(inn.elite).map { tilstand.populasjon[$0.offset] }
            var neste = Array(elite)
            while neste.count < inn.populasjon {
                let mor = elite.randomElement(using: &rng)!
                let barn: MesterVekter
                if Double.random(in: 0..<1, using: &rng) < 0.3 {
                    let far = elite.randomElement(using: &rng)!
                    barn = MesterVekter.krysning(mor, far, rng: &rng)
                        .mutert(sigma: inn.sigma, rate: inn.rate, rng: &rng)
                } else {
                    barn = mor.mutert(sigma: inn.sigma, rate: inn.rate, rng: &rng)
                }
                neste.append(barn)
            }
            tilstand.populasjon = neste
            tilstand.generasjon += 1

            let tid = Int(Date().timeIntervalSince(start))
            logg("generasjon \(tilstand.generasjon): beste sum \(rangert[0].element), " +
                 "median \(rangert[rangert.count / 2].element), \(tid) s\(ankerTekst)")
            skrivSjekkpunkt(tilstand)
            skrivLiveSide(tilstand, sistePoeng: rangert.map(\.element))
        }
        skrivSjekkpunkt(tilstand)
        logg("ferdig – tilstand lagret i \(inn.katalog)")
    }

    // MARK: - Turneringen

    /// Spiller én generasjon: bordene stokkes `omstokk` ganger, hvert bord
    /// spiller `runderPerBord` utdelinger i fire speilrotasjoner, og alle
    /// bord+utdelinger kjøres parallelt. Returnerer sum poeng per individ.
    private func spillGenerasjon(_ populasjon: [MesterVekter], generasjon: Int) -> [Int] {
        var jobber: [(kandidater: [Int], frø: UInt64)] = []
        var stokkRng = SeededGenerator(seed: 0xB0D &+ UInt64(generasjon) &* 104729)
        for om in 0..<inn.omstokk {
            var rekkefølge = Array(populasjon.indices)
            rekkefølge.shuffle(using: &stokkRng)
            for bord in 0..<(populasjon.count / inn.bordStørrelse) {
                let kandidater = (0..<inn.bordStørrelse).map {
                    rekkefølge[bord * inn.bordStørrelse + $0]
                }
                for runde in 0..<inn.runderPerBord {
                    let frø = UInt64(generasjon) &* 1_000_003
                        &+ UInt64(om) &* 65_537
                        &+ UInt64(bord) &* 4_099
                        &+ UInt64(runde)
                    jobber.append((kandidater, frø))
                }
            }
        }

        var sum = [Int](repeating: 0, count: populasjon.count)
        DispatchQueue.concurrentPerform(iterations: jobber.count) { i in
            let jobb = jobber[i]
            var lokal = [Int](repeating: 0, count: jobb.kandidater.count)
            var rng = SeededGenerator(seed: jobb.frø &* 31 &+ 17)
            // Fast poengstilling per utdeling – kandidatene roterer gjennom
            // alle setene, så stillingen rammer alle likt.
            let stilling = (0..<4).map { _ in Int.random(in: 0..<95, using: &rng) }
            for rotasjon in 0..<jobb.kandidater.count {
                let poeng = spillRunde(
                    frø: jobb.frø, stilling: stilling,
                    vekter: (0..<4).map { sete in
                        populasjon[jobb.kandidater[(sete + rotasjon) % jobb.kandidater.count]]
                    })
                guard let poeng else { continue }
                for sete in 0..<4 {
                    lokal[(sete + rotasjon) % jobb.kandidater.count] += poeng[sete]
                }
            }
            kø.sync {
                for (k, kandidat) in jobb.kandidater.enumerated() {
                    sum[kandidat] += lokal[k]
                }
            }
        }
        return sum
    }

    /// Én runde med fire MesterAI-er med hver sine vekter. Returnerer
    /// poengendringen per sete, eller nil om noe ulovlig skulle skje.
    private func spillRunde(frø: UInt64, stilling: [Int], vekter: [MesterVekter]) -> [Int]? {
        let engine = GameEngine()
        engine.settPoengstilling(stilling)
        engine.startRunde(seed: frø)
        let aier = (0..<4).map { sete -> MesterAI in
            var konfig = MesterKonfig.automatisk()
            konfig.tidsbudsjett = inn.tidsbudsjett
            konfig.vekter = vekter[sete]
            return MesterAI(sete: sete, konfig: konfig, seed: frø &+ UInt64(sete) &* 7)
        }
        var vakt = 0
        while engine.phase == .budrunde || engine.phase == .byttekort
            || engine.phase == .velgTrumf || engine.phase == .spill {
            vakt += 1
            if vakt > 400 { return nil }
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                let bud = aier[sete].velgBud(engine: engine)
                if !engine.giBud(seat: sete, action: bud) {
                    engine.giBud(seat: sete, action: .pass)
                }
            case .byttekort:
                let sete = engine.budgiverSeat!
                var vrak = aier[sete].velgByttekort(engine: engine)
                if vrak.count != engine.rules.antallByttekort
                    || !vrak.allSatisfy({ engine.hands[sete].contains($0) }) {
                    vrak = Array(engine.hands[sete].prefix(engine.rules.antallByttekort))
                }
                guard engine.kastByttekort(vrak, seat: sete) else { return nil }
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                if let (suit, ønsket) = aier[sete].velgTrumfOgMakker(engine: engine),
                   engine.velgTrumf(suit: suit, ønsket: ønsket) {
                    break
                }
                // Nødvalg: første farge med lovlig etterlysning.
                var valgt = false
                for suit in Kortmaske.farger {
                    if let ø = engine.kortSomKanØnskes(trumf: suit).first,
                       engine.velgTrumf(suit: suit, ønsket: ø) { valgt = true; break }
                }
                if !valgt { return nil }
            case .spill:
                let sete = engine.aktivSpiller
                let lovlige = engine.lovligeKort(for: sete)
                var kort = aier[sete].velgKort(engine: engine)
                if kort == nil || !lovlige.contains(kort!) { kort = lovlige.first }
                guard let kort, engine.spill(kort: kort, seat: sete) else { return nil }
            default:
                break
            }
        }
        guard let resultat = engine.sisteRunde else { return nil }
        return resultat.poengEndring
    }

    // MARK: - Ankermåling

    /// Parrede runder mot 3× Vanskelig: kandidat-vekter mot standardvekter
    /// på samme utdelinger. Positiv diff = kandidaten er sterkere enn
    /// standarden i absolutt forstand (ikke bare mot søsknene sine).
    private func anker(_ kandidat: MesterVekter, generasjon: Int) -> (diff: Double, se: Double) {
        var differ = [Double](repeating: .nan, count: inn.ankerRunder)
        DispatchQueue.concurrentPerform(iterations: inn.ankerRunder) { i in
            let frø = 0xA2C0 &+ UInt64(generasjon) &* 524_287 &+ UInt64(i)
            var poeng: [Double] = []
            for vekter in [kandidat, MesterVekter()] {
                var konfig = MesterKonfig.automatisk()
                konfig.tidsbudsjett = inn.tidsbudsjett
                konfig.vekter = vekter
                let engine = GameEngine()
                engine.startRunde(seed: frø)
                let president = MesterAI(sete: 0, konfig: konfig, seed: frø &+ 3)
                let andre = (1..<4).map {
                    AIPlayer(seat: $0, difficulty: .vanskelig, personality: .balansert)
                }
                var vakt = 0
                var ok = true
                while engine.phase == .budrunde || engine.phase == .byttekort
                    || engine.phase == .velgTrumf || engine.phase == .spill {
                    vakt += 1
                    if vakt > 400 { ok = false; break }
                    let sete = engine.phase == .budrunde ? engine.aktivBudgiver
                        : engine.phase == .spill ? engine.aktivSpiller
                        : engine.budgiverSeat!
                    if sete == 0 {
                        switch engine.phase {
                        case .budrunde:
                            if !engine.giBud(seat: 0, action: president.velgBud(engine: engine)) {
                                engine.giBud(seat: 0, action: .pass)
                            }
                        case .byttekort:
                            var vrak = president.velgByttekort(engine: engine)
                            if vrak.count != engine.rules.antallByttekort
                                || !vrak.allSatisfy({ engine.hands[0].contains($0) }) {
                                vrak = Array(engine.hands[0].prefix(engine.rules.antallByttekort))
                            }
                            if !engine.kastByttekort(vrak, seat: 0) { ok = false }
                        case .velgTrumf:
                            if let (suit, ønsket) = president.velgTrumfOgMakker(engine: engine),
                               engine.velgTrumf(suit: suit, ønsket: ønsket) { break }
                            ok = false
                        case .spill:
                            let lovlige = engine.lovligeKort(for: 0)
                            var kort = president.velgKort(engine: engine)
                            if kort == nil || !lovlige.contains(kort!) { kort = lovlige.first }
                            if kort == nil || !engine.spill(kort: kort!, seat: 0) { ok = false }
                        default: break
                        }
                    } else {
                        let spiller = andre[sete - 1]
                        switch engine.phase {
                        case .budrunde:
                            if !engine.giBud(seat: sete, action: spiller.velgBud(engine: engine)) {
                                engine.giBud(seat: sete, action: .pass)
                            }
                        case .byttekort:
                            if !engine.kastByttekort(spiller.velgByttekort(engine: engine), seat: sete) { ok = false }
                        case .velgTrumf:
                            if let (suit, ønsket) = spiller.velgTrumfOgMakker(engine: engine),
                               engine.velgTrumf(suit: suit, ønsket: ønsket) { break }
                            ok = false
                        case .spill:
                            if let kort = spiller.velgKort(engine: engine),
                               engine.spill(kort: kort, seat: sete) { break }
                            ok = false
                        default: break
                        }
                    }
                    if !ok { break }
                }
                guard ok, let r = engine.sisteRunde else { poeng.append(.nan); continue }
                poeng.append(Double(r.poengEndring[0]))
            }
            if poeng.count == 2, !poeng[0].isNaN, !poeng[1].isNaN {
                differ[i] = poeng[0] - poeng[1]
            }
        }
        let gyldige = differ.filter { !$0.isNaN }
        let n = Double(gyldige.count)
        let snitt = gyldige.reduce(0, +) / n
        let varians = gyldige.reduce(0) { $0 + ($1 - snitt) * ($1 - snitt) } / max(1, n - 1)
        return (snitt, (varians / n).squareRoot())
    }

    // MARK: - Sjekkpunkt, logg og live-side

    private var sjekkpunktSti: String { inn.katalog + "/tilstand.json" }

    private func lesSjekkpunkt() -> Tilstand? {
        guard let data = FileManager.default.contents(atPath: sjekkpunktSti) else { return nil }
        return try? JSONDecoder().decode(Tilstand.self, from: data)
    }

    private func skrivSjekkpunkt(_ tilstand: Tilstand) {
        guard let data = try? JSONEncoder().encode(tilstand) else { return }
        let tmp = sjekkpunktSti + ".tmp"
        FileManager.default.createFile(atPath: tmp, contents: data)
        // replaceItemAt krever at målet finnes (Linux), så flytt manuelt.
        try? FileManager.default.removeItem(atPath: sjekkpunktSti)
        try? FileManager.default.moveItem(atPath: tmp, toPath: sjekkpunktSti)
    }

    private func logg(_ tekst: String) {
        let stempel = ISO8601DateFormatter().string(from: Date())
        let linje = "\(stempel) \(tekst)\n"
        print(linje, terminator: "")
        let sti = inn.katalog + "/evolusjon.log"
        if !FileManager.default.fileExists(atPath: sti) {
            FileManager.default.createFile(atPath: sti, contents: nil)
        }
        if let h = FileHandle(forWritingAtPath: sti) {
            h.seekToEndOfFile()
            h.write(linje.data(using: .utf8)!)
            h.closeFile()
        }
    }

    private func skrivLiveSide(_ tilstand: Tilstand, sistePoeng: [Int]) {
        var html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="refresh" content="10"><title>Evolusjon</title>
        <style>body{font-family:system-ui;background:#131417;color:#e8e8e8;max-width:700px;margin:40px auto;padding:0 16px}
        table{border-collapse:collapse;width:100%}td,th{padding:4px 8px;text-align:right;border-bottom:1px solid #2a2c31}
        th{color:#9aa}td:first-child,th:first-child{text-align:left}.lit{color:#9aa;font-size:.88em}</style></head><body>
        <h1>🧬 Turneringsevolusjon — generasjon \(tilstand.generasjon)</h1>
        <p class=lit>Stopp kontrollert: `touch \(inn.katalog)/STOPP` · gjenoppta: kjør kommandoen igjen</p>
        <h2>Ankermålinger (vinner mot standardvekter, poeng/runde)</h2>
        <table><tr><th>Generasjon</th><th>Diff</th><th>± SE</th></tr>
        """
        for rad in tilstand.ankerRå.suffix(20) {
            html += String(format: "<tr><td>%d</td><td>%+.2f</td><td>%.2f</td></tr>", rad[0].i, rad[0].d, rad[1].d)
        }
        html += "</table><h2>Siste generasjons poengsummer</h2><p>"
        html += sistePoeng.map(String.init).joined(separator: " · ")
        html += "</p><p class=lit>Oppdatert \(ISO8601DateFormatter().string(from: Date()))</p></body></html>"
        FileManager.default.createFile(atPath: inn.katalog + "/index.html",
                                       contents: html.data(using: .utf8))
    }
}
