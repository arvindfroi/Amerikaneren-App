import Foundation

/// Meldingsprotokollen for onlinespill over GKMatch.
///
/// Modellen er vert/klient: spilleren med lavest gamePlayerID er vert og
/// kjører `GameEngine` som eneste autoritet. Klientene får personaliserte
/// øyeblikksbilder (kun egen hånd og egne lovlige trekk) og sender
/// handlinger tilbake. Verten validerer alt mot motoren, så en klient kan
/// aldri spille ulovlig – og ser aldri andres kort.
enum OnlineMessage: Codable {
    case setup(OnlineSetup)
    case snapshot(OnlineSnapshot)
    case action(OnlineAction)
}

/// Sendes én gang fra verten til hver spiller når partiet starter.
struct OnlineSetup: Codable {
    /// Visningsnavn per sete (0–3).
    var seatNavn: [String]
    /// Identitet per sete: "gc:<gamePlayerID>" for mennesker,
    /// "ai:<opponentId>" for CPU-utfyllere. Brukes til statistikk.
    var seatIdentitet: [String]
    /// Mottakerens eget sete.
    var dittSete: Int
    var målPoeng: Int
}

/// Handling fra en klient (eller vertens eget UI). Setet utledes av
/// avsenderen på vertssiden – aldri av meldingen.
enum OnlineAction: Codable {
    case bud(BidAction)
    case trumf(Suit, Card)
    case kort(Card)
}

/// Personalisert øyeblikksbilde av spillet, bygget av verten per sete.
struct OnlineSnapshot: Codable {
    var scores: [Int]
    var phase: GamePhase
    var aktivSeat: Int
    var bids: [PlacedBid]
    var høyesteBud: PlacedBid?
    var trumf: Suit?
    var ønsketKort: Card?
    var makkerAvslørt: Bool
    /// Kun satt når makkeren er avslørt – ellers hemmelig.
    var makkerSeat: Int?
    var erAmerikaner: Bool
    var budgiverSeat: Int?
    var currentTrick: [TrickPlay]
    var sisteStikk: [TrickPlay]
    var stikkTatt: [Int]
    var trickNummer: Int

    // Personlig del
    var dinHånd: [Card]
    var lovligeKort: [Card]
    var lovligeBud: [BidAction]

    // Rundeslutt/partislutt
    var sisteRunde: RoundResult?
    var vinnerSeat: Int?
    /// Full rundehistorikk – sendes kun ved partislutt, til statistikken.
    var rundeHistorikk: [RoundResult]?
}
