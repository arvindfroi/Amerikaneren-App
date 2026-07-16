import Foundation

enum AIDifficulty: String, CaseIterable, Codable, Identifiable {
    case lett = "Lett"
    case middels = "Middels"
    case vanskelig = "Vanskelig"
    case president = "President"   // toppnivå for kampanjens sluttmotstandere

    var id: String { rawValue }

    /// Hvor mye tilfeldig støy som legges på budvurderingen.
    var budStøy: Double {
        switch self {
        case .lett: return 2.2
        case .middels: return 1.2
        case .vanskelig: return 0.5
        case .president: return 0.15
        }
    }

    /// Sannsynlighet for å spille et tilfeldig lovlig kort i stedet for det beste.
    var feilspillSjanse: Double {
        switch self {
        case .lett: return 0.35
        case .middels: return 0.15
        case .vanskelig: return 0.04
        case .president: return 0.0
        }
    }

    var beskrivelse: String {
        switch self {
        case .lett: return "Byr vilt og glemmer hvilke kort som er spilt."
        case .middels: return "Solid motstand med noen feilskjær."
        case .vanskelig: return "Teller kort og byr presist."
        case .president: return "Nådeløs. Feiler aldri med vilje."
        }
    }
}

/// Civilization-inspirerte lederegenskaper (0...1) som farger AI-ens stil.
struct AIPersonality: Codable, Hashable {
    /// Hvor aggressivt det bys – høyt = byr over evne.
    var aggresjon: Double
    /// Vilje til å ta sjanser i spillet (trumfe tidlig, spare høye kort).
    var risiko: Double
    /// Hvor ofte den byr for å presse andre opp, uten å mene det.
    var bløff: Double
    /// Hvor godt den beskytter makkeren sin.
    var lojalitet: Double
    /// Sjansen for å rope «AMERIKANER!» med en kanonhånd.
    var storhetsdrøm: Double

    static let balansert = AIPersonality(aggresjon: 0.5, risiko: 0.5, bløff: 0.2, lojalitet: 0.6, storhetsdrøm: 0.2)

    /// Egenskaper vist i lederprofilen (Civ-stil).
    var trekk: [(navn: String, verdi: Double)] {
        [("Aggresjon", aggresjon), ("Risiko", risiko), ("Bløff", bløff),
         ("Lojalitet", lojalitet), ("Storhetsdrøm", storhetsdrøm)]
    }
}
