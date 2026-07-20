import Foundation

// Testharness for MesterAI på Linux: korrekthet, hastighet og styrke.

// MARK: - Brute-force referanseløser (uten TT og sekvensreduksjon)

func bruteForce(_ t: Spilltilstand) -> Int {
    let union = t.hender[0] | t.hender[1] | t.hender[2] | t.hender[3]
    if union == 0 { return 0 }
    let sete = Spillregler.aktivtSete(t)
    let erMaks = t.lagMaske & (1 << UInt8(sete)) != 0
    let lovlig = Spillregler.lovligMaske(t)
    var beste = erMaks ? Int.min : Int.max
    for indeks in Kortmaske.indekser(lovlig) {
        var barn = t
        var verdi = 0
        if let vinner = Spillregler.utfør(&barn, indeks: indeks) {
            verdi += t.lagMaske & (1 << UInt8(vinner)) != 0 ? 1 : 0
        }
        verdi += bruteForce(barn)
        beste = erMaks ? max(beste, verdi) : min(beste, verdi)
    }
    return beste
}

// MARK: - Hjelpere

func tilfeldigTilstand(stikk: Int, rng: inout SeededGenerator, medPlikt: Bool = false) -> Spilltilstand {
    var kort = Array(0..<52)
    kort.shuffle(using: &rng)
    var hender = SIMD4<UInt64>(repeating: 0)
    for s in 0..<4 {
        for i in 0..<stikk { hender[s] |= 1 << UInt64(kort[s * stikk + i]) }
    }
    let trumf = Int.random(in: 0..<5, using: &rng)   // 4 = uten trumf
    let budgiver = Int.random(in: 0..<4, using: &rng)
    var lag: UInt8 = 1 << UInt8(budgiver)
    if Bool.random(using: &rng) {
        var makker = Int.random(in: 0..<4, using: &rng)
        while makker == budgiver { makker = Int.random(in: 0..<4, using: &rng) }
        lag |= 1 << UInt8(makker)
    }
    var plikt: Int?
    if medPlikt {
        // Etterlyst kort hos et annet sete enn budgiver.
        for s in 0..<4 where s != budgiver {
            if hender[s] != 0 { plikt = Kortmaske.laveste(hender[s]); break }
        }
    }
    return Spilltilstand(
        hender: hender, leder: budgiver, pågående: [],
        trumfFarge: trumf == 4 ? nil : trumf, lagMaske: lag,
        budgiver: budgiver, pliktkort: plikt, førsteStikk: medPlikt
    )
}

/// Kjører én runde med gitte AI-er. Returnerer poengendring per sete.
func spillRunde(seed: UInt64, spillere: [Int: AIPlayer]) -> RoundResult? {
    let engine = GameEngine()
    engine.startRunde(seed: seed)
    var vakt = 0
    while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
        vakt += 1
        if vakt > 400 { print("FEIL: runde henger"); return nil }
        switch engine.phase {
        case .budrunde:
            let sete = engine.aktivBudgiver
            let bud = spillere[sete]!.velgBud(engine: engine)
            guard engine.giBud(seat: sete, action: bud) else {
                print("FEIL: ulovlig bud \(bud) fra sete \(sete)"); return nil
            }
        case .byttekort:
            let sete = engine.budgiverSeat!
            guard engine.kastByttekort(spillere[sete]!.velgByttekort(engine: engine), seat: sete) else {
                print("FEIL: ulovlig vrak fra sete \(sete)"); return nil
            }
        case .velgTrumf:
            let sete = engine.budgiverSeat!
            guard let (suit, ønsket) = spillere[sete]!.velgTrumfOgMakker(engine: engine),
                  engine.velgTrumf(suit: suit, ønsket: ønsket) else {
                print("FEIL: ulovlig trumfvalg fra sete \(sete)"); return nil
            }
        case .spill:
            let sete = engine.aktivSpiller
            guard let kort = spillere[sete]!.velgKort(engine: engine),
                  engine.spill(kort: kort, seat: sete) else {
                print("FEIL: ulovlig kort fra sete \(sete)"); return nil
            }
        default:
            return nil
        }
    }
    return engine.sisteRunde
}

// MARK: - Kommandoer

let kommando = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "alle"

if kommando == "dd" || kommando == "alle" {
    print("== Dobbeltdummy mot brute force ==")
    var rng = SeededGenerator(seed: 1234)
    var feil = 0
    for runde in 0..<400 {
        let stikk = 1 + runde % 5
        let t = tilfeldigTilstand(stikk: stikk, rng: &rng, medPlikt: runde % 7 == 0)
        let dd = Dobbeltdummy().løs(t)
        let bf = bruteForce(t)
        if dd != bf {
            feil += 1
            print("AVVIK ved \(stikk) stikk: dd=\(dd) bf=\(bf) trumf=\(String(describing: t.trumfFarge)) lag=\(t.lagMaske)")
        }
        // Test også midt i stikk: spill 1-3 kort grådig først.
        var midt = t
        for _ in 0..<(runde % 4) {
            if midt.hender[0] | midt.hender[1] | midt.hender[2] | midt.hender[3] == 0 { break }
            Spillregler.utfør(&midt, indeks: GrådigSpiller.velg(midt))
        }
        let dd2 = Dobbeltdummy().løs(midt)
        let bf2 = bruteForce(midt)
        if dd2 != bf2 {
            feil += 1
            print("AVVIK midt i stikk: dd=\(dd2) bf=\(bf2)")
        }
    }
    print(feil == 0 ? "OK: 800 stillinger identiske" : "\(feil) AVVIK!")
}

if kommando == "tid" || kommando == "alle" {
    print("== Tidsbruk eksakt løsning ==")
    var rng = SeededGenerator(seed: 77)
    for stikk in 5...9 {
        var verste = 0.0
        var sum = 0.0
        let n = 30
        for _ in 0..<n {
            let t = tilfeldigTilstand(stikk: stikk, rng: &rng)
            let start = Date()
            _ = Dobbeltdummy().løs(t)
            let tid = Date().timeIntervalSince(start)
            verste = max(verste, tid)
            sum += tid
        }
        print(String(format: "  %d stikk: snitt %.1f ms, verste %.1f ms", stikk, sum / Double(n) * 1000, verste * 1000))
    }
}

if kommando == "fuzz" || kommando == "alle" {
    print("== Lovlighetsfuzz (blandede vanskelighetsgrader) ==")
    var ok = 0
    for seed in 1...UInt64(60) {
        let spillere: [Int: AIPlayer] = [
            0: AIPlayer(seat: 0, difficulty: .president, personality: .balansert),
            1: AIPlayer(seat: 1, difficulty: .lett, personality: .balansert),
            2: AIPlayer(seat: 2, difficulty: .president, personality: .balansert),
            3: AIPlayer(seat: 3, difficulty: .vanskelig, personality: .balansert),
        ]
        if spillRunde(seed: seed, spillere: spillere) != nil { ok += 1 }
    }
    print("OK: \(ok)/60 runder fullført lovlig")
}

if kommando == "styrke" || kommando == "alle" {
    print("== Styrke: sete 0 mot 3× vanskelig heuristikk ==")
    let n = UInt64(CommandLine.arguments.count > 2 ? UInt64(CommandLine.arguments[2]) ?? 150 : 150)

    func kjør(_ navn: String, sete0: AIDifficulty) {
        var sum = 0
        var somBudgiver = (antall: 0, klarte: 0, poeng: 0, budSum: 0)
        var somMakker = (antall: 0, klarte: 0, poeng: 0)
        var somForsvar = (antall: 0, felte: 0, poeng: 0)
        let start = Date()
        for seed in 1...n {
            let spillere: [Int: AIPlayer] = [
                0: AIPlayer(seat: 0, difficulty: sete0, personality: .balansert),
                1: AIPlayer(seat: 1, difficulty: .vanskelig, personality: .balansert),
                2: AIPlayer(seat: 2, difficulty: .vanskelig, personality: .balansert),
                3: AIPlayer(seat: 3, difficulty: .vanskelig, personality: .balansert),
            ]
            guard let runde = spillRunde(seed: seed, spillere: spillere) else { continue }
            let p = runde.poengEndring[0]
            sum += p
            if runde.budgiver == 0 {
                somBudgiver.antall += 1
                somBudgiver.poeng += p
                somBudgiver.budSum += runde.bud.rang == 1000 ? 13 : runde.bud.rang
                if runde.klarte { somBudgiver.klarte += 1 }
            } else if runde.makker == 0 {
                somMakker.antall += 1
                somMakker.poeng += p
                if runde.klarte { somMakker.klarte += 1 }
            } else {
                somForsvar.antall += 1
                somForsvar.poeng += p
                if !runde.klarte { somForsvar.felte += 1 }
            }
        }
        let tid = Date().timeIntervalSince(start)
        print(String(format: "  %@: %.2f poeng/runde  (%.0f s)", navn, Double(sum) / Double(n), tid))
        print(String(format: "     budgiver: %d runder, klarte %d, snittbud %.1f, poeng %+d",
                     somBudgiver.antall, somBudgiver.klarte,
                     somBudgiver.antall > 0 ? Double(somBudgiver.budSum) / Double(somBudgiver.antall) : 0,
                     somBudgiver.poeng))
        print(String(format: "     makker:   %d runder, klarte %d, poeng %+d",
                     somMakker.antall, somMakker.klarte, somMakker.poeng))
        print(String(format: "     forsvar:  %d runder, felte %d, poeng %+d",
                     somForsvar.antall, somForsvar.felte, somForsvar.poeng))
    }

    kjør("vanskelig (basislinje)", sete0: .vanskelig)
    kjør("MesterAI  (president) ", sete0: .president)
}

if kommando == "parti" {
    // Hele partier til 52: vinner sete 0 oftere enn 25 %?
    let n = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 40 : 40

    func spillParti(seed: UInt64, sete0: AIDifficulty) -> Int? {
        let engine = GameEngine()
        let spillere: [Int: AIPlayer] = [
            0: AIPlayer(seat: 0, difficulty: sete0, personality: .balansert),
            1: AIPlayer(seat: 1, difficulty: .vanskelig, personality: .balansert),
            2: AIPlayer(seat: 2, difficulty: .vanskelig, personality: .balansert),
            3: AIPlayer(seat: 3, difficulty: .vanskelig, personality: .balansert),
        ]
        engine.startRunde(seed: seed)
        var vakt = 0
        while engine.phase != .spillFerdig {
            vakt += 1
            if vakt > 8000 { return nil }
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                guard engine.giBud(seat: sete, action: spillere[sete]!.velgBud(engine: engine)) else { return nil }
            case .byttekort:
                let sete = engine.budgiverSeat!
                guard engine.kastByttekort(spillere[sete]!.velgByttekort(engine: engine), seat: sete) else { return nil }
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                guard let (suit, ønsket) = spillere[sete]!.velgTrumfOgMakker(engine: engine),
                      engine.velgTrumf(suit: suit, ønsket: ønsket) else { return nil }
            case .spill:
                let sete = engine.aktivSpiller
                guard let kort = spillere[sete]!.velgKort(engine: engine),
                      engine.spill(kort: kort, seat: sete) else { return nil }
            case .rundeFerdig:
                engine.nesteRunde()
            default:
                return nil
            }
        }
        return engine.vinnerSeat
    }

    for (navn, grad) in [("vanskelig", AIDifficulty.vanskelig), ("MesterAI ", .president)] {
        var seiere = 0
        var fullførte = 0
        let start = Date()
        for seed in 1...UInt64(n) {
            guard let vinner = spillParti(seed: seed * 31 + 7, sete0: grad) else { continue }
            fullførte += 1
            if vinner == 0 { seiere += 1 }
        }
        let tid = Date().timeIntervalSince(start)
        print(String(format: "  %@ i sete 0: vant %d av %d partier (%.0f %%)  [forventet 25 %% ved likt spill]  %.0f s",
                     navn, seiere, fullførte, Double(seiere) / Double(max(1, fullførte)) * 100, tid))
    }
}

if kommando == "scenario" {
    // Sjekker de konstruerte testscenarioene fra MesterAITests.
    var hender = SIMD4<UInt64>(repeating: 0)
    for valør in 7...12 { hender[0] |= 1 << UInt64(valør) }
    for valør in 0..<6 { hender[1] |= 1 << UInt64(valør) }
    for valør in 0..<6 { hender[2] |= 1 << UInt64(13 + valør) }
    for valør in 0..<6 { hender[3] |= 1 << UInt64(26 + valør) }
    let topp = Spilltilstand(hender: hender, leder: 0, pågående: [], trumfFarge: 0,
                             lagMaske: 0b0001, budgiver: 0, pliktkort: nil, førsteStikk: false)
    print("toppkort (forventer 6): \(Dobbeltdummy().løs(topp))")

    var h2 = SIMD4<UInt64>(repeating: 0)
    h2[0] = (1 << 11) | (1 << 0)
    h2[1] = (1 << 12) | (1 << 3)
    h2[2] = (1 << 13) | (1 << 14)
    h2[3] = (1 << 26) | (1 << 27)
    let utenPlikt = Spilltilstand(hender: h2, leder: 0, pågående: [], trumfFarge: nil,
                                  lagMaske: 0b0001, budgiver: 0, pliktkort: nil, førsteStikk: true)
    var medPlikt = utenPlikt
    medPlikt.pliktkort = 12
    print("uten plikt (forventer 0): \(Dobbeltdummy().løs(utenPlikt))")
    print("med plikt  (forventer 1): \(Dobbeltdummy().løs(medPlikt))")
}

if kommando == "motorfuzz" {
    // Egenskapsbasert fuzz av selve motoren: tilfeldige LOVLIGE handlinger
    // (også rare: solo uten etterlysning, vrak av talongkort, ville bud),
    // og uavhengig re-verifisering av hver regel etter hver runde.
    let antall = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 3000 : 3000
    var rng = SeededGenerator(seed: 20260719)
    var feil = 0
    var talteRunder = 0
    var meldinger = (tall: 0, amerikaner: 0, solo: 0, alenetall: 0, utenØnske: 0)

    func sjekk(_ ok: Bool, _ melding: String, seed: UInt64) {
        if !ok {
            feil += 1
            print("FEIL (frø \(seed)): \(melding)")
        }
    }

    for runde in 0..<antall {
        let seed = UInt64(runde) &* 2654435761 &+ 17
        let klassisk = runde % 5 == 4
        var regler = GameRules()
        regler.medByttekort = !klassisk
        let engine = GameEngine(rules: regler)
        engine.startRunde(seed: seed)

        let utdelte = engine.hands.flatMap { $0 } + engine.talon
        sjekk(Set(utdelte).count == 52, "utdelingen dekker ikke stokken", seed: seed)
        sjekk(engine.talon.count == regler.antallByttekort, "feil talong", seed: seed)

        var spiltAv: [Card: Int] = [:]
        var føltIkkeFarge: [(sete: Int, farge: Suit)] = []
        var vakt = 0

        mens: while engine.phase != .rundeFerdig && engine.phase != .spillFerdig {
            vakt += 1
            if vakt > 600 { sjekk(false, "runden henger", seed: seed); break }
            switch engine.phase {
            case .budrunde:
                let sete = engine.aktivBudgiver
                let lovlige = engine.lovligeBud(for: sete)
                sjekk(!lovlige.isEmpty, "ingen lovlige bud", seed: seed)
                // Vekt mot pass så budrunden ender, men prøv alt innimellom.
                let valg: BidAction
                let r = Int.random(in: 0..<100, using: &rng)
                if r < 55 || lovlige.count == 1 {
                    valg = .pass
                } else {
                    valg = lovlige.filter { $0 != .pass }.randomElement(using: &rng)!
                }
                // Ulovlige bud skal avvises uten å endre tilstanden.
                let førAntall = engine.bids.count
                sjekk(!engine.giBud(seat: (sete + 1) % 4, action: .bud(5)), "bud fra feil sete godtatt", seed: seed)
                sjekk(engine.bids.count == førAntall, "avvist bud endret historikken", seed: seed)
                sjekk(engine.giBud(seat: sete, action: valg), "lovlig bud avvist", seed: seed)
            case .byttekort:
                let sete = engine.budgiverSeat!
                sjekk(engine.hands[sete].count == regler.kortPerSpiller + regler.antallByttekort,
                      "byttehånden har feil størrelse", seed: seed)
                sjekk(!engine.kastByttekort(Array(engine.hands[sete].prefix(3)), seat: sete),
                      "vrak med feil antall godtatt", seed: seed)
                let vrak = Array(engine.hands[sete].shuffled(using: &rng).prefix(regler.antallByttekort))
                sjekk(engine.kastByttekort(vrak, seat: sete), "lovlig vrak avvist", seed: seed)
            case .velgTrumf:
                let sete = engine.budgiverSeat!
                let suit = Suit.allCases.randomElement(using: &rng)!
                // Egne og vrakede kort skal aldri kunne ønskes.
                for kort in engine.hands[sete] + engine.kastet {
                    sjekk(!engine.kortSomKanØnskes(trumf: kort.suit).contains(kort),
                          "eget/vraket kort i ønskelisten", seed: seed)
                }
                if let dødt = engine.kastet.first {
                    sjekk(!engine.velgTrumf(suit: dødt.suit, ønsket: dødt), "vraket kort ønsket", seed: seed)
                }
                if engine.erSolo, Bool.random(using: &rng) {
                    sjekk(engine.velgTrumf(suit: suit, ønsket: nil), "solo uten ønske avvist", seed: seed)
                    meldinger.utenØnske += 1
                } else if let ønsket = engine.kortSomKanØnskes(trumf: suit).randomElement(using: &rng) {
                    if !engine.erSolo {
                        sjekk(!engine.velgTrumf(suit: suit, ønsket: nil), "manglende ønske godtatt", seed: seed)
                    }
                    sjekk(engine.velgTrumf(suit: suit, ønsket: ønsket), "lovlig trumfvalg avvist", seed: seed)
                    if engine.erSolo {
                        sjekk(engine.makkerSeat == nil, "solo fikk makker", seed: seed)
                    } else {
                        sjekk(engine.makkerSeat != nil && engine.makkerSeat != engine.budgiverSeat,
                              "makker mangler eller er budgiver", seed: seed)
                        sjekk(engine.hands[engine.makkerSeat!].contains(ønsket), "makker har ikke ønskekortet", seed: seed)
                    }
                } else {
                    // Ingen ønskbare i fargen: prøv en annen farge.
                    var valgt = false
                    for annen in Suit.allCases {
                        if let ø = engine.kortSomKanØnskes(trumf: annen).first,
                           engine.velgTrumf(suit: annen, ønsket: ø) { valgt = true; break }
                    }
                    sjekk(valgt || engine.erSolo, "fant ingen lovlig etterlysning", seed: seed)
                    if !valgt { sjekk(engine.velgTrumf(suit: suit, ønsket: nil), "solo-nødvalg avvist", seed: seed) }
                }
            case .spill:
                let sete = engine.aktivSpiller
                let lovlige = engine.lovligeKort(for: sete)
                sjekk(!lovlige.isEmpty, "ingen lovlige kort", seed: seed)
                sjekk(lovlige.allSatisfy { engine.hands[sete].contains($0) }, "lovlig kort ikke på hånden", seed: seed)
                // Følg farge-regelen, uavhengig re-verifisert.
                if let ledet = engine.currentTrick.first?.card.suit {
                    let harFargen = engine.hands[sete].contains { $0.suit == ledet }
                    if harFargen {
                        sjekk(lovlige.allSatisfy { $0.suit == ledet }, "slapp å følge farge", seed: seed)
                    } else {
                        føltIkkeFarge.append((sete, ledet))
                    }
                }
                // Utspillsplikt: budvinneren må åpne første stikk i trumf
                // – har budvinneren trumf, er bare trumf lovlig i utspillet.
                if engine.currentTrick.isEmpty, engine.trickNummer == 0,
                   sete == engine.budgiverSeat, let trumf = engine.trumf,
                   engine.hands[sete].contains(where: { $0.suit == trumf }) {
                    sjekk(lovlige.allSatisfy { $0.suit == trumf },
                          "utspillsplikten (trumf i første stikk) håndheves ikke", seed: seed)
                }
                // Makkerplikt: er det etterlyste kortet lovlig i første stikk,
                // skal det være ENESTE lovlige.
                if engine.trickNummer == 0, let ønsket = engine.ønsketKort, !engine.ønsketLagt,
                   sete != engine.budgiverSeat, engine.hands[sete].contains(ønsket) {
                    let kunneLagt: Bool
                    if let ledet = engine.currentTrick.first?.card.suit {
                        kunneLagt = ønsket.suit == ledet || !engine.hands[sete].contains { $0.suit == ledet }
                    } else {
                        kunneLagt = true
                    }
                    if kunneLagt {
                        sjekk(lovlige == [ønsket], "makkerplikten håndheves ikke", seed: seed)
                    }
                }
                // Et ulovlig kort (utenfor hånden) skal avvises.
                if let annetSete = (0..<4).first(where: { $0 != sete && !engine.hands[$0].isEmpty }),
                   let fremmed = engine.hands[annetSete].first {
                    sjekk(!engine.spill(kort: fremmed, seat: sete), "spilte en annens kort", seed: seed)
                }
                let kort = lovlige.randomElement(using: &rng)!
                spiltAv[kort] = sete
                sjekk(engine.spill(kort: kort, seat: sete), "lovlig kort avvist", seed: seed)
            default:
                break mens
            }
        }

        guard let resultat = engine.sisteRunde else {
            sjekk(false, "runden ga ikke resultat", seed: seed)
            continue
        }
        talteRunder += 1

        // Grunninvarianter.
        sjekk(resultat.stikkPerSpiller.reduce(0, +) == regler.kortPerSpiller, "stikksummen stemmer ikke", seed: seed)
        sjekk(engine.hands.allSatisfy(\.isEmpty), "kort igjen på hånden", seed: seed)
        sjekk(Set(engine.spilteKort).count == regler.kortPerSpiller * 4, "spilte kort teller feil", seed: seed)
        sjekk(Set(engine.spilteKort).isDisjoint(with: engine.kastet), "vrakede kort ble spilt", seed: seed)

        // Ingen fulgte-ikke-farge der de faktisk hadde fargen (dobbeltsjekket
        // via spilteAv-historikken er dekket av lovlige-sjekkene over).
        _ = føltIkkeFarge

        // Poengregler re-verifisert uavhengig av motoren.
        let bud = resultat.bud
        let budgiver = resultat.budgiver
        let lag = [budgiver, resultat.makker].compactMap { $0 }
        let lagStikk = lag.reduce(0) { $0 + resultat.stikkPerSpiller[$1] }
        let forventetKlarte: Bool
        let budgiverPoeng: Int
        let makkerPoeng: Int
        switch bud {
        case .soloAmerikaner:
            forventetKlarte = resultat.stikkPerSpiller[budgiver] == regler.kortPerSpiller
            budgiverPoeng = regler.målPoeng; makkerPoeng = 0
            sjekk(resultat.makker == nil, "solo har makker i resultatet", seed: seed)
            meldinger.solo += 1
        case .amerikaner:
            forventetKlarte = lagStikk == regler.kortPerSpiller
            budgiverPoeng = regler.målPoeng / 2; makkerPoeng = regler.målPoeng / 4
            meldinger.amerikaner += 1
        case .bud(let n):
            forventetKlarte = lagStikk >= n
            budgiverPoeng = 2 * n; makkerPoeng = n
            meldinger.tall += 1
            if resultat.makker == nil { meldinger.alenetall += 1 }
        case .pass:
            forventetKlarte = false; budgiverPoeng = 0; makkerPoeng = 0
            sjekk(false, "runde uten vinnerbud", seed: seed)
        }
        sjekk(resultat.klarte == forventetKlarte, "klarte-flagget stemmer ikke", seed: seed)
        for s in 0..<4 {
            let forventet: Int
            if s == budgiver {
                forventet = forventetKlarte ? budgiverPoeng : -budgiverPoeng
            } else if lag.contains(s) {
                forventet = forventetKlarte ? makkerPoeng : -makkerPoeng
            } else {
                forventet = resultat.stikkPerSpiller[s]
            }
            sjekk(resultat.poengEndring[s] == forventet,
                  "poeng for sete \(s): \(resultat.poengEndring[s]) ≠ \(forventet) (\(bud.beskrivelse))", seed: seed)
        }

        // Partislutt: vinneren skal ha nådd målet.
        if engine.phase == .spillFerdig {
            sjekk(engine.vinnerSeat != nil, "ferdig parti uten vinner", seed: seed)
            if let vinner = engine.vinnerSeat {
                sjekk(engine.scores[vinner] >= regler.målPoeng, "vinner under målet", seed: seed)
                sjekk(engine.scores[vinner] == engine.scores.max(), "vinner har ikke toppscore", seed: seed)
            }
        }
    }
    print(feil == 0
          ? "OK: \(talteRunder) runder verifisert uten avvik"
          : "\(feil) AVVIK over \(talteRunder) runder!")
    print("  meldinger: \(meldinger.tall) tallbud (\(meldinger.alenetall) uten makker), \(meldinger.amerikaner) amerikaner, \(meldinger.solo) solo, \(meldinger.utenØnske) solo uten etterlysning")
}

if kommando == "ab" {
    // A/B: budvekting + forsvarsstikk-bonus av/på, samme frø.
    let n = UInt64(CommandLine.arguments.count > 2 ? UInt64(CommandLine.arguments[2]) ?? 100 : 100)
    for (navn, vekting) in [("uten budvekting", false), ("med budvekting ", true)] {
        var konfig = MesterKonfig()
        konfig.budvekting = vekting
        MesterAI.overstyrKonfig = konfig
        var sum = 0
        var klarte = 0, deklarerte = 0, felte = 0, forsvar = 0
        let start = Date()
        for seed in 1...n {
            let spillere: [Int: AIPlayer] = [
                0: AIPlayer(seat: 0, difficulty: .president, personality: .balansert),
                1: AIPlayer(seat: 1, difficulty: .vanskelig, personality: .balansert),
                2: AIPlayer(seat: 2, difficulty: .vanskelig, personality: .balansert),
                3: AIPlayer(seat: 3, difficulty: .vanskelig, personality: .balansert),
            ]
            guard let runde = spillRunde(seed: seed &* 13 &+ 5, spillere: spillere) else { continue }
            sum += runde.poengEndring[0]
            if runde.budgiver == 0 || runde.makker == 0 {
                deklarerte += 1
                if runde.klarte { klarte += 1 }
            } else {
                forsvar += 1
                if !runde.klarte { felte += 1 }
            }
        }
        let tid = Int(Date().timeIntervalSince(start))
        print(String(format: "  %@: %.2f poeng/runde | budlag %d/%d | forsvar felte %d/%d | %d s",
                     navn, Double(sum) / Double(n), klarte, deklarerte, felte, forsvar, tid))
    }
    MesterAI.overstyrKonfig = nil
}

if kommando == "format" {
    // Endrer atferden seg med partiformatet? Selvspill (4× MesterAI, rask
    // konfig) i «først til 100» mot «20 runder», med og uten matchbevissthet.
    let matcher = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 20 : 20

    func kjørFormat(_ navn: String, maksRunder: Int?, matchbevisst: Bool) {
        var konfig = MesterKonfig()
        konfig.maksVerdener = 10
        konfig.minVerdener = 6
        konfig.tidsbudsjett = 0.1
        konfig.verdenerVedBud = 16
        konfig.verdenerVedBytte = 8
        konfig.eksaktStikkGrense = 5
        konfig.matchbevisst = matchbevisst
        MesterAI.overstyrKonfig = konfig

        var vågale = 0        // amerikaner/solo meldt av noen som lå bak
        var vågaleForan = 0   // ... av noen som ledet/lå likt
        var comebacks = 0     // vinneren lå bak halvveis
        var talteMatcher = 0
        var runderTotalt = 0
        let start = Date()

        for m in 0..<matcher {
            var regler = GameRules()
            regler.maksRunder = maksRunder
            let engine = GameEngine(rules: regler)
            let spillere = (0..<4).map { AIPlayer(seat: $0, difficulty: .president, personality: .balansert) }
            engine.startRunde(seed: UInt64(m) &* 6947 &+ 11)
            var halvveisLeder: Int?
            var vakt = 0
            løkke: while engine.phase != .spillFerdig {
                vakt += 1
                if vakt > 20000 { break }
                switch engine.phase {
                case .budrunde:
                    let sete = engine.aktivBudgiver
                    let bud = spillere[sete].velgBud(engine: engine)
                    if bud == .amerikaner || bud == .soloAmerikaner {
                        let besteAndre = (0..<4).filter { $0 != sete }.map { engine.scores[$0] }.max() ?? 0
                        if engine.scores[sete] < besteAndre { vågale += 1 } else { vågaleForan += 1 }
                    }
                    guard engine.giBud(seat: sete, action: bud) else { break løkke }
                case .byttekort:
                    let sete = engine.budgiverSeat!
                    guard engine.kastByttekort(spillere[sete].velgByttekort(engine: engine), seat: sete) else { break løkke }
                case .velgTrumf:
                    let sete = engine.budgiverSeat!
                    guard let (suit, ønsket) = spillere[sete].velgTrumfOgMakker(engine: engine),
                          engine.velgTrumf(suit: suit, ønsket: ønsket) else { break løkke }
                case .spill:
                    let sete = engine.aktivSpiller
                    guard let kort = spillere[sete].velgKort(engine: engine),
                          engine.spill(kort: kort, seat: sete) else { break løkke }
                case .rundeFerdig:
                    let halvveis = maksRunder.map { $0 / 2 } ?? 0
                    if maksRunder != nil, engine.rundeResultater.count == halvveis {
                        halvveisLeder = (0..<4).max { engine.scores[$0] < engine.scores[$1] }
                    } else if maksRunder == nil, halvveisLeder == nil,
                              engine.scores.contains(where: { $0 >= engine.rules.målPoeng / 2 }) {
                        halvveisLeder = (0..<4).max { engine.scores[$0] < engine.scores[$1] }
                    }
                    engine.nesteRunde()
                default:
                    break løkke
                }
            }
            guard engine.phase == .spillFerdig, let vinner = engine.vinnerSeat else { continue }
            talteMatcher += 1
            runderTotalt += engine.rundeResultater.count
            if let leder = halvveisLeder, leder != vinner { comebacks += 1 }
        }
        let tid = Int(Date().timeIntervalSince(start))
        print(String(format: "  %@: %d matcher, %.1f runder/match | vågale meldinger bak/foran: %d/%d | comebacks %d | %d s",
                     navn, talteMatcher, Double(runderTotalt) / Double(max(1, talteMatcher)),
                     vågale, vågaleForan, comebacks, tid))
    }

    print("== Partiformat-eksperiment (4× MesterAI selvspill) ==")
    kjørFormat("til 100, matchbevisst  ", maksRunder: nil, matchbevisst: true)
    kjørFormat("til 100, uten           ", maksRunder: nil, matchbevisst: false)
    kjørFormat("20 runder, matchbevisst", maksRunder: 20, matchbevisst: true)
    kjørFormat("20 runder, uten        ", maksRunder: 20, matchbevisst: false)
    MesterAI.overstyrKonfig = nil
}
