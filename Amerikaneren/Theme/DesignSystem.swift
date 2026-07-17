import SwiftUI

/// Designsystemet for Amerikaneren – alle tokens samlet ett sted.
///
/// Identitet: «Brain Training møter americana». Kremhvitt papir, mørkeblått
/// blekk, rød aksent, runde vennlige former – med stjerner og striper som
/// krydder, aldri som tapet.
///
/// Prinsipper (se docs/DESIGN.md):
/// - Bestemor-testen: alle gester har en synlig knapp-ekvivalent,
///   trykkflater er minst 48 pt, én tydelig primærhandling per skjerm.
/// - Tommelsonen: all interaksjon i spill skjer i nederste tredjedel.
/// - Motion skal føles fjærende og aldri blokkere input.
enum DS {

    // MARK: - Farger

    enum Farge {
        static let papir = Color(hex: "F7F1E1")        // hovedbakgrunn
        static let papirMørk = Color(hex: "EFE6CE")    // spillebord-bakgrunn
        static let flate = Color.white.opacity(0.8)    // paneler/kort-flater
        static let blekk = Color(hex: "1D3557")        // primærtekst
        static let blekkSvak = Color(hex: "1D3557").opacity(0.55)
        static let linje = Color(hex: "1D3557").opacity(0.14)

        static let rød = Color(hex: "E63946")          // aksent / primærhandling
        static let blå = Color(hex: "457B9D")          // sekundærhandling
        static let grønn = Color(hex: "2A9D8F")        // suksess / «din tur»
        static let gul = Color(hex: "E9C46A")          // fremheving / bobler
        static let bordfilt = Color(hex: "2A9D8F").opacity(0.12) // stikk-området
    }

    // MARK: - Typografi
    // Semantiske stiler bygget på tekststiler, så Dynamic Type («større
    // skrift» i iOS-innstillingene) skalerer alt automatisk – viktig for
    // bestemor. Avrundet design hele veien.

    enum Tekst {
        static var display: Font { .system(.largeTitle, design: .rounded).weight(.black) }
        static var tittel: Font { .system(.title2, design: .rounded).weight(.heavy) }
        static var overskrift: Font { .system(.headline, design: .rounded).weight(.bold) }
        static var brød: Font { .system(.body, design: .rounded).weight(.medium) }
        static var etikett: Font { .system(.footnote, design: .rounded).weight(.semibold) }
        static var liten: Font { .system(.caption, design: .rounded).weight(.medium) }
        static var tall: Font { .system(.title, design: .rounded).weight(.black).monospacedDigit() }
        static var tallLiten: Font { .system(.headline, design: .rounded).weight(.heavy).monospacedDigit() }
    }

    // MARK: - Avstand og form

    enum Avstand {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 10
        static let m: CGFloat = 14
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
    }

    enum Mål {
        /// Minste trykkflate (Apple anbefaler 44 – vi legger oss høyere).
        static let minTrykk: CGFloat = 48
        /// Standard knappehøyde for primærhandlinger.
        static let knappHøyde: CGFloat = 54
        /// Kortbredde i hånden (normal / «store kort»-innstillingen).
        static let kortBredde: CGFloat = 64
        static let kortBreddeStor: CGFloat = 78
    }

    // MARK: - Motion

    enum Bevegelse {
        /// Trykk-respons: umiddelbar og sprett.
        static let rask = Animation.spring(response: 0.22, dampingFraction: 0.8)
        /// Standard for det meste: kort inn på bordet, valg, paneler.
        static let standard = Animation.spring(response: 0.32, dampingFraction: 0.78)
        /// Store sceneskift: rundeslutt, seier.
        static let myk = Animation.spring(response: 0.45, dampingFraction: 0.85)

        static let kortInn = AnyTransition.scale(scale: 0.6).combined(with: .opacity)
        static let panelInn = AnyTransition.move(edge: .bottom).combined(with: .opacity)
        static let bannerInn = AnyTransition.move(edge: .top).combined(with: .opacity)
    }
}
