import Foundation

// Amerikaneren på kommandolinjen – for å teste kjernen (spillmotor,
// MesterAI og companion-poengføring) uten Mac, iPhone eller Xcode.
// Bygg og kjør:  swift run -c release Amerikaneren <kommando>

private let hjelpetekst = """
🇺🇸 Amerikaneren CLI

Kommandoer:
  demo       Spill ett parti med full spill-for-spill-logg.
             --seed N       frø for utdelinger og MesterAI (reproduserbart)
             --runder N     fast antall runder (ellers først til målpoeng)
             --mål N        målpoeng (standard 100)
             --tid SEK      MesterAI-tidsbudsjett per trekk (standard 0.2)
             --nivåer A,B,C,D  nivå per sete: lett|middels|vanskelig|president
                            (standard: president,vanskelig,vanskelig,vanskelig)

  arena      Spill mange partier og mål MesterAI mot de andre nivåene.
             --partier N    antall partier (standard 10)
             --mot NIVÅ     motstandernivå på sete 1–3 (standard vanskelig)
             --seed N, --runder N, --mål N, --tid SEK  som over

  spill      Spill selv! Hot-seat med mennesker og AI-er ved samme
             tastatur (hendene skjules når tastaturet bytter spiller).
             --seter A,B,C,D  per sete: menneske|lett|middels|vanskelig|president
                            (standard: menneske,president,menneske,president)
             --navn X,Y     navn på menneskene i seterekkefølge
             --seed N, --runder N, --mål N, --tid SEK  som over

  web        Spill i nettleseren! Starter en lokal web-GUI: du i sete 0
             mot tre President-AI-er. Binder kun til 127.0.0.1.
             Trener-modus (på som standard, bryter i GUI-et) viser MesterAIs
             anbefaling for hvert av dine valg – med EV-rangering ved
             kortvalg. Mens du tenker, ponderer AI-ene svarene sine på
             kloner av motoren, så de kommer øyeblikkelig (og grundigere
             tenkt) når du spiller. Hvert parti logges etterprøvbart til
             ~/spillogger/ (JSONL med Rundeopptak per runde og
             ponder-merking per AI-kortvalg; GET /logg lister dem).
             --port N       port (standard 8787)
             --navn X       navnet ditt (standard Arvind)
             --seed N, --mål N, --tid SEK  som over (standard tid her: 0.6)

  verifiser  Etterprøver en spillogg fra web-kommandoen: hver runde
             («rundeopptak»-linjene) spilles av gjennom motoren, som
             håndhever reglene trekk for trekk og sammenlikner resultatet.
             Bruk: Amerikaneren verifiser ~/spillogger/<fil>.jsonl

  companion  Poengblokken for fysiske kort, i terminalen.
             --demo         kjør et scriptet eksempelparti (ikke interaktivt)

  evolusjon  Turneringsevolusjon over MesterAI-heuristikkvektene: bord à 4
             (alle President), speilrotasjoner og tilfeldige poengstillinger,
             de beste avler neste generasjon. Sjekkpunktes og gjenopptas fra
             --katalog (standard ~/evolusjon); `touch <katalog>/STOPP`
             stanser kontrollert. Ankermåling mot standardvektene hver
             --ankerHver generasjon avgjør «beste noensinne».
             --populasjon N (20) --runder N (24) --omstokk N (2)
             --tid SEK (0.1) --ankerHver N (5) --ankerRunder N (400)
             --generasjoner N (0 = til STOPP)

  hjelp      Denne teksten.

Eksempler:
  swift run -c release Amerikaneren web --port 8787
  swift run -c release Amerikaneren spill --navn Arvind,Kari
  swift run -c release Amerikaneren demo --seed 42 --runder 6 --tid 0.05
  swift run -c release Amerikaneren arena --partier 10 --mot middels
  swift run -c release Amerikaneren companion --demo

Merk: full determinisme krever --seed OG president på alle seter – de
andre nivåene bruker bevisst useedet støy (personlighet/feilspill).
"""

private func flaggVerdi(_ navn: String, _ argv: [String]) -> String? {
    guard let i = argv.firstIndex(of: "--\(navn)"), i + 1 < argv.count else { return nil }
    return argv[i + 1]
}

private func nivå(fra tekst: String) -> AIDifficulty? {
    AIDifficulty.allCases.first { $0.rawValue.lowercased() == tekst.trimmingCharacters(in: .whitespaces).lowercased() }
}

private func lesInnstillinger(_ argv: [String]) -> Kampsimulator.Innstillinger {
    var inn = Kampsimulator.Innstillinger()
    inn.seed = flaggVerdi("seed", argv).flatMap { UInt64($0) }
    inn.maksRunder = flaggVerdi("runder", argv).flatMap { Int($0) }
    if let mål = flaggVerdi("mål", argv).flatMap({ Int($0) }) { inn.målPoeng = mål }
    if let tid = flaggVerdi("tid", argv).flatMap({ Double($0) }) { inn.tidsbudsjett = tid }
    if let tekst = flaggVerdi("nivåer", argv) {
        let nivåer = tekst.components(separatedBy: ",").compactMap(nivå(fra:))
        if nivåer.count == 4 {
            inn.nivåer = nivåer
        } else {
            print("⚠️ --nivåer trenger fire gyldige nivåer – bruker standard.")
        }
    }
    return inn
}

private func kjørDemo(_ argv: [String]) {
    let simulator = Kampsimulator(innstillinger: lesInnstillinger(argv))
    if simulator.spillParti() == nil { exit(1) }
}

private func kjørArena(_ argv: [String]) {
    var inn = lesInnstillinger(argv)
    inn.utskrift = false
    let mot = flaggVerdi("mot", argv).flatMap(nivå(fra:)) ?? .vanskelig
    if flaggVerdi("nivåer", argv) == nil {
        inn.nivåer = [.president, mot, mot, mot]
    }
    let partier = flaggVerdi("partier", argv).flatMap { Int($0) } ?? 10

    print("🏟️ Arena: \(partier) partier – sete 0 \(inn.nivåer[0].rawValue) mot \(inn.nivåer[1].rawValue)/\(inn.nivåer[2].rawValue)/\(inn.nivåer[3].rawValue)")
    var seiere = [0, 0, 0, 0]
    var budTreff = 0, budForsøk = 0
    var runderTotalt = 0
    let start = Date()

    for partiNr in 0..<partier {
        var partiInn = inn
        partiInn.seed = inn.seed.map { $0 &+ UInt64(partiNr) &* 1_000_003 }
        guard let resultat = Kampsimulator(innstillinger: partiInn).spillParti() else {
            print("⚠️ Parti \(partiNr + 1) ble avbrutt – hopper over.")
            continue
        }
        seiere[resultat.vinner] += 1
        runderTotalt += resultat.runder.count
        for runde in resultat.runder where runde.budgiver == 0 {
            budForsøk += 1
            if runde.klarte { budTreff += 1 }
        }
        let poeng = resultat.sluttpoeng.map(String.init).joined(separator: "/")
        print("  Parti \(String(format: "%2d", partiNr + 1)): vinner S\(resultat.vinner) · poeng \(poeng) · \(resultat.runder.count) runder")
    }

    let spilte = seiere.reduce(0, +)
    guard spilte > 0 else { exit(1) }
    print("")
    print("📊 Oppsummering etter \(spilte) partier (\(String(format: "%.0f", Date().timeIntervalSince(start))) s):")
    for sete in 0..<4 {
        let prosent = 100.0 * Double(seiere[sete]) / Double(spilte)
        print("  S\(sete) \(inn.nivåer[sete].rawValue): \(seiere[sete]) seiere (\(String(format: "%.0f", prosent)) %)")
    }
    print("  Snitt runder per parti: \(String(format: "%.1f", Double(runderTotalt) / Double(spilte)))")
    if budForsøk > 0 {
        print("  S0 budtreff som budgiver: \(budTreff)/\(budForsøk) (\(String(format: "%.0f", 100.0 * Double(budTreff) / Double(budForsøk))) %)")
    }
    print("  (Tilfeldig nivå ville vunnet 25 % – alt godt over det er MesterAI i aksjon.)")
}

let argv = Array(CommandLine.arguments.dropFirst())
switch argv.first {
case "demo":
    kjørDemo(argv)
case "arena":
    kjørArena(argv)
case "spill":
    SpillKommando.kjør(argv: argv, innstillinger: lesInnstillinger(argv))
case "web":
    WebSpill.kjør(argv: argv)
case "verifiser":
    VerifiserLogg.kjør(argv: argv)
case "companion":
    CompanionKommando.kjør(demo: argv.contains("--demo"))
case "evolusjon":
    var evo = Evolusjon.Innstillinger()
    if let katalog = flaggVerdi("katalog", argv) { evo.katalog = katalog }
    if let n = flaggVerdi("populasjon", argv).flatMap({ Int($0) }) { evo.populasjon = n }
    if let n = flaggVerdi("runder", argv).flatMap({ Int($0) }) { evo.runderPerBord = n }
    if let n = flaggVerdi("omstokk", argv).flatMap({ Int($0) }) { evo.omstokk = n }
    if let t = flaggVerdi("tid", argv).flatMap({ Double($0) }) { evo.tidsbudsjett = t }
    if let n = flaggVerdi("ankerHver", argv).flatMap({ Int($0) }) { evo.ankerHver = n }
    if let n = flaggVerdi("ankerRunder", argv).flatMap({ Int($0) }) { evo.ankerRunder = n }
    if let n = flaggVerdi("generasjoner", argv).flatMap({ Int($0) }) { evo.maksGenerasjoner = n }
    Evolusjon(innstillinger: evo).kjør()
case "eksporter-runder":
    // Paritetseksport for OpenSpiel-porten: N runder med tilfeldige lovlige
    // trekk som JSONL på stdout.  Bruk: eksporter-runder <antall> <frø>
    EksporterRunder.kjør(argv: argv)
case nil, "hjelp", "--help", "-h":
    print(hjelpetekst)
default:
    print("Ukjent kommando «\(argv[0])».")
    print(hjelpetekst)
    exit(1)
}
