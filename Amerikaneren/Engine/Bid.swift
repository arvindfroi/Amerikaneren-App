import Foundation

/// En melding i budrunden.
enum BidAction: Hashable, Codable {
    case pass
    case bud(Int)
    /// «Amerikaner»: ta alle stikk alene, uten trumf og uten makker.
    case amerikaner

    /// Rangverdi for å sammenlikne bud. Amerikaner slår alle tallbud.
    var rang: Int {
        switch self {
        case .pass: return -1
        case .bud(let n): return n
        case .amerikaner: return 1000
        }
    }

    var beskrivelse: String {
        switch self {
        case .pass: return "Pass"
        case .bud(let n): return "\(n) stikk"
        case .amerikaner: return "AMERIKANER!"
        }
    }
}

struct PlacedBid: Hashable, Codable, Identifiable {
    let seat: Int
    let action: BidAction
    var id: String { "\(seat)-\(action.rang)" }
}
