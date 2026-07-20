import Foundation

enum MatchMode: String, Codable, CaseIterable {
    case offline = "Mot maskinen"
    case online = "Online"
    case ranked = "Ranked"
    case companion = "Companion"
    case kampanje = "Kampanje"
}

/// Én deltaker i et registrert parti. CPU-er har opponentId satt.
struct MatchParticipant: Codable, Hashable, Identifiable {
    var id: String              // "meg", opponentId, eller companion-navn
    var navn: String
    var erMeg: Bool
    var opponentId: String?
    var sluttPoeng: Int
    var vantPartiet: Bool
}

/// Én budrunde i et parti – grunnlaget for detaljert statistikk.
/// Alt statistikk og analyse beregnes fra disse rådataene ved behov,
/// aldri fra lagrede aggregater – nye felter er valgfrie (Optional) så
/// gamle lagrede partier alltid kan leses.
struct RoundRecord: Codable, Hashable {
    var budgiverId: String
    var makkerId: String?
    var bud: Int                 // 1000 = Amerikaner, 2000 = solo-amerikaner
    var trumf: String?
    var klarte: Bool
    var stikk: [String: Int]     // deltaker-id -> stikk
    var poengEndring: [String: Int]
    /// Hvor lenge runden varte (companion: tid mellom føringer).
    var varighetSekunder: Int?

    var erAmerikanerMelding: Bool { bud >= 1000 }
    var erSoloMelding: Bool { bud >= 2000 }

    /// Budlagets stikk, utledet: rundens totale stikk minus motstandernes.
    /// Robust for companion-partier der lagets stikk aldri tastes inn.
    func lagStikk(antallSpillere: Int) -> Int {
        let total = GameRules(antallSpillere: antallSpillere).kortPerSpiller
        let motstanderStikk = stikk
            .filter { $0.key != budgiverId && $0.key != makkerId }
            .values.reduce(0, +)
        return total - motstanderStikk
    }
}

/// Et fullført parti. `deltakere` står i seterekkefølge rundt bordet
/// (med klokka), så plassering er også sporbart.
struct MatchRecord: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var dato: Date = Date()
    var mode: MatchMode
    var deltakere: [MatchParticipant]
    var runder: [RoundRecord]
    var varighetSekunder: Int = 0
    var kampanjeStageId: String? = nil
    /// Ratingendring hvis partiet var ranked.
    var eloDelta: Int? = nil
    /// Poengmålet partiet ble spilt til (nil = åpent parti / ukjent).
    var målPoeng: Int?

    var vinner: MatchParticipant? { deltakere.first { $0.vantPartiet } }
    var jegVant: Bool { vinner?.erMeg == true }
}

