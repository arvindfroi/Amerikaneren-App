import Foundation

/// Kortfarge. Rekkefølgen brukes kun til sortering i hånden.
enum Suit: String, CaseIterable, Codable, Hashable, Identifiable {
    case spar = "♠"
    case hjerter = "♥"
    case ruter = "♦"
    case kløver = "♣"

    var id: String { rawValue }

    var navn: String {
        switch self {
        case .spar: return "Spar"
        case .hjerter: return "Hjerter"
        case .ruter: return "Ruter"
        case .kløver: return "Kløver"
        }
    }

    var erRød: Bool { self == .hjerter || self == .ruter }
}

/// Kortverdi. Ess er høyest (14), to er lavest (2).
enum Rank: Int, CaseIterable, Codable, Hashable, Comparable {
    case two = 2, three, four, five, six, seven, eight, nine, ten
    case jack = 11, queen = 12, king = 13, ace = 14

    static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

    var symbol: String {
        switch self {
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .ace: return "A"
        default: return String(rawValue)
        }
    }

    var navn: String {
        switch self {
        case .jack: return "Knekt"
        case .queen: return "Dame"
        case .king: return "Konge"
        case .ace: return "Ess"
        default: return String(rawValue)
        }
    }
}

struct Card: Hashable, Codable, Identifiable {
    let suit: Suit
    let rank: Rank

    var id: String { "\(suit.rawValue)\(rank.rawValue)" }
    var beskrivelse: String { "\(suit.navn) \(rank.navn)" }
    var kortSymbol: String { "\(rank.symbol)\(suit.rawValue)" }
}

enum Deck {
    /// Full kortstokk på 52 kort.
    static func full() -> [Card] {
        Suit.allCases.flatMap { suit in
            Rank.allCases.map { Card(suit: suit, rank: $0) }
        }
    }

    static func stokket(seed: UInt64? = nil) -> [Card] {
        var kort = full()
        if let seed {
            var generator = SeededGenerator(seed: seed)
            kort.shuffle(using: &generator)
        } else {
            kort.shuffle()
        }
        return kort
    }
}

/// Deterministisk generator for testbare utdelinger.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

extension Array where Element == Card {
    /// Sorterer hånden for visning: farge for farge, høyeste først.
    func sortertForHånd() -> [Card] {
        let suitOrder: [Suit] = [.spar, .hjerter, .kløver, .ruter]
        return sorted { a, b in
            let ia = suitOrder.firstIndex(of: a.suit) ?? 0
            let ib = suitOrder.firstIndex(of: b.suit) ?? 0
            if ia != ib { return ia < ib }
            return a.rank > b.rank
        }
    }
}
