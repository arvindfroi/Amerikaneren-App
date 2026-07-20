import Foundation

/// UI-fri poengføring for companion-modus (digital poengblokk for fysiske
/// kort). Logikken deles mellom appen (`CompanionViewModel`) og
/// kommandolinjeverktøyet, og enhetstestes derfor uten UI – også på Linux.
struct CompanionParti: Codable {
    struct FørtRunde: Codable {
        var budgiver: Int
        var makker: Int?
        var bud: Int            // 1000 = Amerikaner, 2000 = solo-amerikaner
        var klarte: Bool
        var stikk: [Int]
        var poengEndring: [Int]

        func beskrivelse(spillere: [String]) -> String {
            let budTekst = bud >= 2000 ? "Solo-amerikaner" : bud >= 1000 ? "Amerikaner" : "\(bud) stikk"
            var tekst = "\(spillere[budgiver]): \(budTekst)"
            if let makker { tekst += " (m/ \(spillere[makker]))" }
            return tekst
        }
    }

    let spillere: [String]
    let målPoeng: Int
    private(set) var poeng: [Int]
    private(set) var runder: [FørtRunde] = []

    init(spillere: [String], målPoeng: Int = 100) {
        self.spillere = spillere
        self.målPoeng = målPoeng
        self.poeng = Array(repeating: 0, count: spillere.count)
    }

    /// Rensker navnelisten (trim + fjern tomme) og godtar den bare hvis
    /// 3–6 unike navn står igjen – samme krav som oppsettskjermen stiller.
    static func gyldigeSpillere(_ navneliste: [String]) -> [String]? {
        let navn = navneliste
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard (3...6).contains(navn.count), Set(navn).count == navn.count else { return nil }
        return navn
    }

    /// Satser og kortfordeling deles med motoren (GameRules), så
    /// companion-poengene aldri kan drive fra spillets egne regler.
    private var regler: GameRules {
        GameRules(antallSpillere: spillere.count, målPoeng: målPoeng)
    }

    var kortPerSpiller: Int { regler.kortPerSpiller }

    /// Spillerindekser sortert på poeng, best først.
    var sortert: [Int] {
        spillere.indices.sorted { poeng[$0] > poeng[$1] }
    }

    var ferdig: Bool {
        poeng.contains { $0 >= målPoeng }
    }

    var vinner: Int? { ferdig ? sortert.first : nil }

    /// Poengregler: budvinneren får alltid dobbelt av makkeren.
    /// Tallbud n: ±2n / ±n. Amerikaner: ±målPoeng/2 / ±målPoeng/4.
    /// Solo-amerikaner: ±målPoeng til solisten alene.
    /// Øvrige spillere får ett poeng per eget stikk.
    @discardableResult
    mutating func førRunde(
        budgiver: Int, makker: Int?, bud: Int,
        erAmerikaner: Bool, erSolo: Bool,
        klarte: Bool, stikk: [Int]
    ) -> FørtRunde {
        var endring = Array(repeating: 0, count: spillere.count)
        let budVerdi = erSolo ? 2000 : erAmerikaner ? 1000 : bud
        let makkerIndex = erSolo || makker == budgiver
            ? nil
            : makker.flatMap { $0 >= 0 ? $0 : nil }

        let budgiverPoeng = erSolo ? regler.soloAmerikanerPoeng
            : erAmerikaner ? regler.amerikanerPoeng
            : bud * regler.budgiverFaktor
        let makkerPoeng = erAmerikaner ? regler.amerikanerPoeng / 2 : bud
        endring[budgiver] = klarte ? budgiverPoeng : -budgiverPoeng
        if let makkerIndex { endring[makkerIndex] = klarte ? makkerPoeng : -makkerPoeng }
        for i in spillere.indices where i != budgiver && i != makkerIndex {
            endring[i] += stikk[i]
        }
        for i in spillere.indices { poeng[i] += endring[i] }

        let runde = FørtRunde(
            budgiver: budgiver, makker: makkerIndex, bud: budVerdi,
            klarte: klarte, stikk: stikk, poengEndring: endring
        )
        runder.append(runde)
        return runde
    }
}
