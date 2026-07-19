import Foundation

/// En melding i budrunden.
enum BidAction: Hashable, Codable {
    case pass
    case bud(Int)
    /// «Amerikaner»: ta alle stikkene – med trumf og hemmelig makker.
    /// Slår alle tallbud. Budvinner ±(målPoeng/2), makker ±(målPoeng/4).
    case amerikaner
    /// «Solo-amerikaner»: ta alle stikkene helt alene. Fortsatt trumf, og
    /// man KAN etterlyse ett kort i første stikk, men har ingen makker.
    /// Slår alt og kan ikke overbys. Budvinner ±målPoeng.
    case soloAmerikaner

    /// Rangverdi for å sammenlikne bud. Amerikaner slår alle tallbud,
    /// solo-amerikaner slår alt.
    var rang: Int {
        switch self {
        case .pass: return -1
        case .bud(let n): return n
        case .amerikaner: return 1000
        case .soloAmerikaner: return 2000
        }
    }

    var beskrivelse: String {
        switch self {
        case .pass: return "Pass"
        case .bud(let n): return "\(n) stikk"
        case .amerikaner: return "AMERIKANER!"
        case .soloAmerikaner: return "SOLO-AMERIKANER!"
        }
    }
}

struct PlacedBid: Hashable, Codable, Identifiable {
    let seat: Int
    let action: BidAction
    var id: String { "\(seat)-\(action.rang)" }
}
