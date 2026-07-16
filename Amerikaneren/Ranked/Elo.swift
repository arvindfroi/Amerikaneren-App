import Foundation

/// Divisjonene i ranked – tematisert som en politisk karriere.
/// Divisjonen brukes som Game Center `playerGroup`, slik at man bare
/// matches mot spillere i samme kategori.
enum RankTier: Int, CaseIterable, Codable {
    case borger = 1        // < 1100
    case ordfører = 2      // 1100–1249
    case senator = 3       // 1250–1399
    case guvernør = 4      // 1400–1549
    case visepresident = 5 // 1550–1699
    case president = 6     // >= 1700

    static func forRating(_ rating: Int) -> RankTier {
        switch rating {
        case ..<1100: return .borger
        case ..<1250: return .ordfører
        case ..<1400: return .senator
        case ..<1550: return .guvernør
        case ..<1700: return .visepresident
        default: return .president
        }
    }

    var navn: String {
        switch self {
        case .borger: return "Borger"
        case .ordfører: return "Ordfører"
        case .senator: return "Senator"
        case .guvernør: return "Guvernør"
        case .visepresident: return "Visepresident"
        case .president: return "President"
        }
    }

    var emoji: String {
        switch self {
        case .borger: return "🗳️"
        case .ordfører: return "🏛️"
        case .senator: return "🦅"
        case .guvernør: return "⭐"
        case .visepresident: return "🎖️"
        case .president: return "🇺🇸"
        }
    }

    /// Ratingintervallet vist i UI.
    var intervall: String {
        switch self {
        case .borger: return "under 1100"
        case .ordfører: return "1100–1249"
        case .senator: return "1250–1399"
        case .guvernør: return "1400–1549"
        case .visepresident: return "1550–1699"
        case .president: return "1700+"
        }
    }
}

/// Én ranked-kamp i ratinghistorikken.
struct EloEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var dato: Date = Date()
    var rating: Int      // rating ETTER kampen
    var delta: Int
    var plassering: Int  // 1–4
}

/// Elo for firespillerspill: hver spiller møter de tre andre parvis.
/// Bedre plassering = 1 poeng, lik poengsum = 0.5, dårligere = 0.
enum EloCalculator {
    static let startRating = 1000

    /// K-faktor: høy de første ti ranked-kampene (rask kalibrering),
    /// deretter standard.
    static func kFaktor(antallRankedKamper: Int) -> Double {
        antallRankedKamper < 10 ? 64 : 32
    }

    /// Forventet score for spiller a mot spiller b.
    static func forventet(_ a: Int, mot b: Int) -> Double {
        1.0 / (1.0 + pow(10.0, Double(b - a) / 400.0))
    }

    /// Beregner ratingendringen for én spiller.
    /// - Parameters:
    ///   - rating: spillerens rating før kampen
    ///   - poeng: spillerens sluttpoeng i partiet
    ///   - motstandere: (rating, poeng) for de andre ved bordet
    ///   - k: spillerens K-faktor
    static func delta(rating: Int, poeng: Int, motstandere: [(rating: Int, poeng: Int)], k: Double) -> Int {
        guard !motstandere.isEmpty else { return 0 }
        var sum = 0.0
        for motstander in motstandere {
            let faktisk: Double = poeng > motstander.poeng ? 1.0
                : poeng == motstander.poeng ? 0.5 : 0.0
            sum += faktisk - forventet(rating, mot: motstander.rating)
        }
        return Int((k / Double(motstandere.count) * sum).rounded())
    }

    /// Fast rating for CPU-utfyllere i ranked, etter vanskelighetsgrad.
    static func cpuRating(_ difficulty: AIDifficulty) -> Int {
        switch difficulty {
        case .lett: return 900
        case .middels: return 1150
        case .vanskelig: return 1400
        case .president: return 1750
        }
    }
}
