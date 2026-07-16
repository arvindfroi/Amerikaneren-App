import Foundation
import UIKit
import AudioToolbox

/// Haptikk og lyd for spillhendelser. Respekterer brukerens innstillinger
/// (lagres i UserDefaults, styres fra innstillingsarket).
///
/// Lydene er systemlyder som midlertidige plassholdere – egne lydfiler
/// kommer sammen med de øvrige visuelle ressursene.
@MainActor
enum Feedback {
    static var lydPå: Bool {
        UserDefaults.standard.object(forKey: "lydPå") as? Bool ?? true
    }
    static var haptikkPå: Bool {
        UserDefaults.standard.object(forKey: "haptikkPå") as? Bool ?? true
    }

    private static let lett = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let kraftig = UIImpactFeedbackGenerator(style: .heavy)
    private static let varsel = UINotificationFeedbackGenerator()
    private static let valg = UISelectionFeedbackGenerator()

    /// Et kort legges på bordet.
    static func kortSpilt() {
        if haptikkPå { lett.impactOccurred() }
        spillLyd(1104)
    }

    /// Et stikk er avgjort.
    static func stikkAvgjort(mitt: Bool) {
        if haptikkPå { mitt ? medium.impactOccurred() : lett.impactOccurred(intensity: 0.6) }
        spillLyd(mitt ? 1054 : 1053)
    }

    /// Det er din tur.
    static func dinTur() {
        if haptikkPå { valg.selectionChanged() }
        spillLyd(1057)
    }

    /// Noen ga et bud.
    static func budGitt() {
        if haptikkPå { valg.selectionChanged() }
    }

    /// Noen meldte Amerikaner!
    static func amerikanerMeldt() {
        if haptikkPå { kraftig.impactOccurred() }
        spillLyd(1005)
    }

    /// Runden er over – budet holdt eller røk (sett fra spilleren).
    static func rundeSlutt(bra: Bool) {
        if haptikkPå { varsel.notificationOccurred(bra ? .success : .warning) }
        spillLyd(bra ? 1054 : 1073)
    }

    /// Partiet er over.
    static func spillSlutt(vant: Bool) {
        if haptikkPå { varsel.notificationOccurred(vant ? .success : .error) }
        spillLyd(vant ? 1025 : 1073)
    }

    private static func spillLyd(_ id: SystemSoundID) {
        guard lydPå else { return }
        AudioServicesPlaySystemSound(id)
    }
}
