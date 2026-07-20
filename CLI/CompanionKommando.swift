import Foundation

/// Companion-modus i terminalen: samme poengføringslogikk som appen
/// (`CompanionParti`), slik at reglene kan prøves og etterprøves uten
/// iPhone. `--demo` kjører et scriptet eksempelparti (brukes også i CI);
/// uten flagg føres et ekte parti interaktivt.
enum CompanionKommando {

    static func kjør(demo: Bool) {
        if demo { kjørDemo() } else { kjørInteraktivt() }
    }

    // MARK: - Demo

    static func kjørDemo() {
        print("📝 Companion-demo: poengblokken for fysiske kort, i terminalen.")
        print("   Fire spillere, først til 52 poeng.")
        var parti = CompanionParti(spillere: ["Du", "Kari", "Ola", "Petter"], målPoeng: 52)

        // (budgiver, makker, bud, amerikaner, solo, klarte, stikk til øvrige)
        let runder: [(Int, Int?, Int, Bool, Bool, Bool, [Int])] = [
            (0, 1, 6, false, false, true,  [0, 0, 4, 3]),
            (1, 3, 7, false, false, false, [6, 0, 2, 0]),
            (2, nil, 5, false, false, true, [3, 2, 0, 3]),
            (3, 0, 13, true, false, false, [0, 5, 4, 0]),
            (0, 2, 8, false, false, true,  [0, 3, 0, 2]),
            (1, 0, 9, false, false, true,  [0, 0, 2, 2]),
        ]
        for (nr, r) in runder.enumerated() {
            guard !parti.ferdig else { break }
            let runde = parti.førRunde(
                budgiver: r.0, makker: r.1, bud: r.2,
                erAmerikaner: r.3, erSolo: r.4, klarte: r.5, stikk: r.6
            )
            print("")
            print("Runde \(nr + 1): \(runde.beskrivelse(spillere: parti.spillere)) → \(runde.klarte ? "klarte ✓" : "røk ✗")")
            skrivPoengtavle(parti)
        }
        print("")
        if let vinner = parti.vinner {
            print("🏆 \(parti.spillere[vinner]) vant!")
        } else {
            print("(Demoen stoppet før noen nådde \(parti.målPoeng) poeng.)")
        }
    }

    // MARK: - Interaktivt

    static func kjørInteraktivt() {
        print("📝 Companion: poengføring for fysiske kort. (Ctrl-C avslutter.)")
        var parti: CompanionParti
        while true {
            let svar = spør("Spillere (3–6 navn, kommaseparert)", standard: "Du, Kari, Ola, Petter")
            if let navn = CompanionParti.gyldigeSpillere(svar.components(separatedBy: ",")) {
                let mål = Int(spør("Spill til hvor mange poeng?", standard: "100")) ?? 100
                parti = CompanionParti(spillere: navn, målPoeng: mål)
                break
            }
            print("Trenger 3–6 unike, ikke-tomme navn – prøv igjen.")
        }

        while !parti.ferdig {
            print("")
            print("── Runde \(parti.runder.count + 1) ──")
            for (i, navn) in parti.spillere.enumerated() { print("  \(i): \(navn)") }
            guard let budgiver = tallSvar("Budgiver (nummer)", i: parti.spillere.indices) else { continue }

            let type = spør("Bud: tall / amerikaner / solo", standard: "tall").lowercased()
            let erSolo = type.hasPrefix("s")
            let erAmerikaner = !erSolo && type.hasPrefix("a")
            var bud = 0
            if !erSolo && !erAmerikaner {
                bud = Int(spør("Antall stikk budt", standard: "\(max(5, parti.kortPerSpiller / 2))")) ?? 5
            }
            var makker: Int?
            if !erSolo {
                let svar = spør("Makker (nummer, tom = ingen)", standard: "")
                makker = Int(svar.trimmingCharacters(in: .whitespaces))
            }
            let klarte = spør(erAmerikaner || erSolo ? "Tok de alle stikkene? (j/n)" : "Klarte laget budet? (j/n)", standard: "j")
                .lowercased().hasPrefix("j")

            var stikk = Array(repeating: 0, count: parti.spillere.count)
            for i in parti.spillere.indices where i != budgiver && i != makker {
                stikk[i] = Int(spør("Stikk til \(parti.spillere[i])", standard: "0")) ?? 0
            }

            let runde = parti.førRunde(
                budgiver: budgiver, makker: makker, bud: bud,
                erAmerikaner: erAmerikaner, erSolo: erSolo, klarte: klarte, stikk: stikk
            )
            print("Ført: \(runde.beskrivelse(spillere: parti.spillere)) → \(runde.klarte ? "klarte ✓" : "røk ✗")")
            skrivPoengtavle(parti)
        }
        if let vinner = parti.vinner {
            print("")
            print("🏆 \(parti.spillere[vinner]) vant med \(parti.poeng[vinner]) poeng!")
        }
    }

    // MARK: - Hjelpere

    private static func skrivPoengtavle(_ parti: CompanionParti) {
        print("Poengtavle (først til \(parti.målPoeng)):")
        for (plass, i) in parti.sortert.enumerated() {
            print("  \(plass + 1). \(parti.spillere[i])  \(parti.poeng[i])")
        }
    }

    private static func spør(_ tekst: String, standard: String) -> String {
        print("\(tekst)\(standard.isEmpty ? "" : " [\(standard)]"): ", terminator: "")
        guard let linje = readLine(), !linje.trimmingCharacters(in: .whitespaces).isEmpty else {
            return standard
        }
        return linje
    }

    private static func tallSvar(_ tekst: String, i gyldige: Range<Int>) -> Int? {
        guard let tall = Int(spør(tekst, standard: "0")), gyldige.contains(tall) else {
            print("Ugyldig nummer.")
            return nil
        }
        return tall
    }
}
