import Foundation
import SwiftUI

/// En CPU-motstander med Civ-inspirert lederprofil og Punch-Out-attityde.
/// Alle figurer er parodier.
struct Opponent: Identifiable, Codable, Hashable {
    let id: String
    let navn: String
    let tittel: String
    let emoji: String
    let farge: String            // hex, brukes som portrettbakgrunn
    let hjemsted: String
    let agenda: String           // Civ-stil «agenda»-beskrivelse
    let difficulty: AIDifficulty
    let personality: AIPersonality
    let introReplikk: String     // før kampen (Punch-Out-stil)
    let seierReplikk: String     // når CPU-en vinner
    let tapReplikk: String       // når CPU-en taper

    var portrettFarge: Color { Color(hex: farge) }
}

/// Hele motstandergalleriet. Parodi på amerikanske skikkelser.
enum OpponentRoster {
    static let alle: [Opponent] = bronse + sølv + gull + [mester]

    // MARK: Bronseligaen (Minor Circuit)
    static let bronse: [Opponent] = [
        Opponent(
            id: "vaskington",
            navn: "Georg Vaskington",
            tittel: "Grunnleggeren",
            emoji: "🌳",
            farge: "7A9E7E",
            hjemsted: "Mount Vernon-ish",
            agenda: "Kan ikke lyve – byr aldri over evne, og forakter bløffere.",
            difficulty: .lett,
            personality: AIPersonality(aggresjon: 0.3, risiko: 0.2, bløff: 0.0, lojalitet: 0.9, storhetsdrøm: 0.1),
            introReplikk: "Jeg kan ikke lyve: Jeg kommer til å slå deg.",
            seierReplikk: "Ærlighet varer lengst. Det gjør visst seiersrekken min også.",
            tapReplikk: "Jeg felte et kirsebærtre én gang. Nå felte du meg."
        ),
        Opponent(
            id: "franklyn",
            navn: "Ben Franklyn",
            tittel: "Lynmesteren",
            emoji: "🪁",
            farge: "B8A15C",
            hjemsted: "Philadelphia-aktig",
            agenda: "Eksperimenterer med ville bud – av og til slår lynet ned.",
            difficulty: .lett,
            personality: AIPersonality(aggresjon: 0.6, risiko: 0.8, bløff: 0.3, lojalitet: 0.5, storhetsdrøm: 0.3),
            introReplikk: "En sparer er en tjener – men et stikk tatt er et stikk tjent!",
            seierReplikk: "Elektrisk! Rett og slett elektrisk!",
            tapReplikk: "Hm. Tilbake til laboratoriet."
        ),
        Opponent(
            id: "jeffersen",
            navn: "Tomas Jeffersen",
            tittel: "Erklæringen",
            emoji: "📜",
            farge: "9E7A5C",
            hjemsted: "Monticello-light",
            agenda: "Erklærer sin uavhengighet fra makkeren – stoler bare på seg selv.",
            difficulty: .middels,
            personality: AIPersonality(aggresjon: 0.5, risiko: 0.5, bløff: 0.2, lojalitet: 0.2, storhetsdrøm: 0.4),
            introReplikk: "Vi anser disse sannheter for selvinnlysende: Du taper.",
            seierReplikk: "Det var selvinnlysende, som sagt.",
            tapReplikk: "Jeg skriver en erklæring om omkamp."
        )
    ]

    // MARK: Sølvligaen (Major Circuit)
    static let sølv: [Opponent] = [
        Opponent(
            id: "linkoln",
            navn: "Abraham Linkoln",
            tittel: "Den ærlige",
            emoji: "🎩",
            farge: "5C6B7A",
            hjemsted: "Tømmerhytta",
            agenda: "Splitter aldri laget sitt – et hus i strid med seg selv faller.",
            difficulty: .middels,
            personality: AIPersonality(aggresjon: 0.4, risiko: 0.35, bløff: 0.05, lojalitet: 1.0, storhetsdrøm: 0.2),
            introReplikk: "Du kan lure noen kortspillere hele tiden... men ikke meg.",
            seierReplikk: "Fire poeng og syv stikk siden...",
            tapReplikk: "Godt spilt. Det var ærlig vunnet."
        ),
        Opponent(
            id: "rosebilt",
            navn: "Teddy Rosebilt",
            tittel: "Bamsebjørnen",
            emoji: "🧸",
            farge: "8C6D46",
            hjemsted: "Villmarken",
            agenda: "Snakker lavt men byr høyt. Stormer San Juan-haugen i hver budrunde.",
            difficulty: .middels,
            personality: AIPersonality(aggresjon: 0.95, risiko: 0.7, bløff: 0.4, lojalitet: 0.6, storhetsdrøm: 0.5),
            introReplikk: "Snakk lavt – og bær et stort bud!",
            seierReplikk: "BULLY! For en runde!",
            tapReplikk: "Grrr. Bamsen er såret, ikke beseiret."
        ),
        Opponent(
            id: "rooseweldt",
            navn: "F.D. Rooseweldt",
            tittel: "New Deal-eren",
            emoji: "🃏",
            farge: "4E6E8E",
            hjemsted: "Kaminpraten",
            agenda: "Det eneste han frykter, er frykten selv – og din trumf-ess.",
            difficulty: .vanskelig,
            personality: AIPersonality(aggresjon: 0.6, risiko: 0.4, bløff: 0.3, lojalitet: 0.8, storhetsdrøm: 0.3),
            introReplikk: "Det eneste vi har å frykte... er min nye giv!",
            seierReplikk: "Det kaller jeg en New Deal.",
            tapReplikk: "Jeg trenger visst en nyere giv."
        )
    ]

    // MARK: Gulligaen (World Circuit)
    static let gull: [Opponent] = [
        Opponent(
            id: "kennedylund",
            navn: "J.F. Kennedylund",
            tittel: "Månefareren",
            emoji: "🚀",
            farge: "6E5C8E",
            hjemsted: "Hyannis-porten",
            agenda: "Byr Amerikaner ikke fordi det er lett, men fordi det er vanskelig.",
            difficulty: .vanskelig,
            personality: AIPersonality(aggresjon: 0.7, risiko: 0.8, bløff: 0.3, lojalitet: 0.6, storhetsdrøm: 0.9),
            introReplikk: "Spør ikke hva kortene kan gjøre for deg...",
            seierReplikk: "Vi valgte å vinne dette tiåret!",
            tapReplikk: "Houston... vi har et problem."
        ),
        Opponent(
            id: "reagansen",
            navn: "Ronny Reagansen",
            tittel: "Skuespilleren",
            emoji: "🎬",
            farge: "A15C5C",
            hjemsted: "Hollywood-åsen",
            agenda: "Stol på ham – men tell alltid kortene. Bløffer med et smil.",
            difficulty: .vanskelig,
            personality: AIPersonality(aggresjon: 0.6, risiko: 0.5, bløff: 0.9, lojalitet: 0.5, storhetsdrøm: 0.4),
            introReplikk: "Riv ned denne poengmuren!",
            seierReplikk: "Det er morgen igjen i Amerikaneren.",
            tapReplikk: "Vel... der har du meg igjen."
        ),
        Opponent(
            id: "eisenhauger",
            navn: "Dwight Eisenhauger",
            tittel: "Generalen",
            emoji: "⭐",
            farge: "5C7A5C",
            hjemsted: "Hovedkvarteret",
            agenda: "Planlegger hvert stikk som en landgang. Ingenting overlates til flaks.",
            difficulty: .vanskelig,
            personality: AIPersonality(aggresjon: 0.5, risiko: 0.2, bløff: 0.1, lojalitet: 0.9, storhetsdrøm: 0.2),
            introReplikk: "Planer er ingenting. Kortplanlegging er alt.",
            seierReplikk: "Operasjonen var en suksess.",
            tapReplikk: "Jeg tar det fulle ansvar. Omgruppering!"
        )
    ]

    // MARK: Mesteren (Mr. Dream-parodien)
    static let mester = Opponent(
        id: "onkelsam",
        navn: "Onkel Sam",
        tittel: "Selveste Amerikaneren",
        emoji: "🇺🇸",
        farge: "3D3D6B",
        hjemsted: "Overalt og ingensteds",
        agenda: "VIL HA DEG – til å tape. Spiller perfekt, byr perfekt, ER spillet.",
        difficulty: .president,
        personality: AIPersonality(aggresjon: 0.8, risiko: 0.6, bløff: 0.5, lojalitet: 0.8, storhetsdrøm: 0.7),
        introReplikk: "JEG VIL HA DEG... til å prøve lykken!",
        seierReplikk: "Spillet heter Amerikaneren. Jeg ER Amerikaneren.",
        tapReplikk: "Utrolig... Tittelen er din, mester!"
    )

    static func medId(_ id: String) -> Opponent? {
        alle.first { $0.id == id }
    }

    /// Tre tilfeldige motstandere til hurtigspill med gitt vanskelighetsgrad.
    static func tilfeldigBord(difficulty: AIDifficulty) -> [Opponent] {
        let kandidater = alle.filter { $0.id != mester.id }
        return Array(kandidater.shuffled().prefix(3)).map { motstander in
            Opponent(
                id: motstander.id, navn: motstander.navn, tittel: motstander.tittel,
                emoji: motstander.emoji, farge: motstander.farge, hjemsted: motstander.hjemsted,
                agenda: motstander.agenda, difficulty: difficulty,
                personality: motstander.personality,
                introReplikk: motstander.introReplikk,
                seierReplikk: motstander.seierReplikk, tapReplikk: motstander.tapReplikk
            )
        }
    }
}
