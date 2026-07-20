import Foundation

/// En lagret spillerprofil for folk du spiller fysisk med (companion-modus).
/// Profilen har en stabil id slik at statistikken følger personen på tvers
/// av partier, og kan kobles til en Game Center-bruker slik at fysiske og
/// online-partier mot samme person telles sammen i H2H.
struct RegistrertSpiller: Codable, Identifiable, Hashable {
    /// Stabil intern id, f.eks. "companion-ola". Endres aldri, selv om
    /// spilleren senere får nytt navn eller kobles til en bruker.
    var id: String
    var navn: String
    /// Game Center-id hvis spilleren er koblet til en ekte bruker.
    var gameCenterId: String? = nil
    var opprettet: Date = Date()

    /// Id-en som brukes i MatchRecord-er. En koblet spiller deler id med
    /// online-partiene ("online-<gcId>"), så all statistikk mot personen
    /// – fysisk og digital – havner på samme H2H-oppføring.
    var deltakerId: String {
        gameCenterId.map { "online-\($0)" } ?? id
    }

    /// Samme id-format som companion-modus brukte før registeret fantes,
    /// så gammel H2H-historikk fortsatt henger sammen med spilleren.
    static func lagId(for navn: String) -> String {
        "companion-\(navn.trimmingCharacters(in: .whitespaces).lowercased())"
    }
}
