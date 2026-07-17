import SwiftUI

/// Designspråk inspirert av Brain Training / Dr. Kawashima:
/// kremhvit «papir»-bakgrunn, mørkeblått blekk, rød aksent,
/// runde, håndskrift-aktige former og store vennlige knapper.
enum Theme {
    // Fasade over designsystemets tokens (DS.Farge) – behold navnene her
    // så eksisterende views slipper å endres; nye views bør bruke DS direkte.
    static let papir = DS.Farge.papir
    static let papirMørk = DS.Farge.papirMørk
    static let blekk = DS.Farge.blekk
    static let blekkSvak = DS.Farge.blekkSvak
    static let rød = DS.Farge.rød
    static let blå = DS.Farge.blå
    static let grønn = DS.Farge.grønn
    static let gul = DS.Farge.gul
    static let linje = DS.Farge.linje

    static func tittelFont(_ størrelse: CGFloat = 28) -> Font {
        .system(size: størrelse, weight: .heavy, design: .rounded)
    }
    static func kroppFont(_ størrelse: CGFloat = 17) -> Font {
        .system(size: størrelse, weight: .medium, design: .rounded)
    }
    static func tallFont(_ størrelse: CGFloat = 34) -> Font {
        .system(size: størrelse, weight: .black, design: .rounded)
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Stor, rund «Brain Training»-knapp.
struct BTButtonStyle: ButtonStyle {
    var farge: Color = Theme.blå
    var stor: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.kroppFont(stor ? 20 : 16).weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, stor ? 14 : 10)
            .padding(.horizontal, stor ? 24 : 16)
            .frame(maxWidth: stor ? .infinity : nil)
            .frame(minHeight: stor ? DS.Mål.knappHøyde : DS.Mål.minTrykk)
            .background(
                RoundedRectangle(cornerRadius: stor ? DS.Radius.l : DS.Radius.m, style: .continuous)
                    .fill(farge)
                    .shadow(color: .black.opacity(configuration.isPressed ? 0.05 : 0.18),
                            radius: configuration.isPressed ? 1 : 4,
                            y: configuration.isPressed ? 1 : 4)
            )
            .contentShape(RoundedRectangle(cornerRadius: stor ? DS.Radius.l : DS.Radius.m))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.Bevegelse.rask, value: configuration.isPressed)
    }
}

/// Papirkort-panel med blekk-kant, som sidene i Brain Training.
struct PapirPanel<Content: View>: View {
    var innhold: Content
    init(@ViewBuilder innhold: () -> Content) { self.innhold = innhold() }

    var body: some View {
        innhold
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Theme.linje, lineWidth: 2)
                    )
            )
    }
}

/// Snakkeboble til læremesteren Benjamin Franklin (og Punch-Out-replikker).
struct SnakkeBoble: View {
    let tekst: String
    var farge: Color = .white

    var body: some View {
        Text(tekst)
            .font(Theme.kroppFont(17))
            .foregroundStyle(Theme.blekk)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(farge)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.blekk.opacity(0.25), lineWidth: 2)
                    )
            )
    }
}

/// Læremesteren: Benjamin Franklin – oppfinner, forfatter og kortfilosof –
/// guider spilleren gjennom tutorialen, vår Dr. Kawashima.
struct MaskotView: View {
    var størrelse: CGFloat = 64
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.gul.opacity(0.8))
            Text("👴")
                .font(.system(size: størrelse * 0.55))
            Text("👓")
                .font(.system(size: størrelse * 0.32))
                .offset(y: -størrelse * 0.06)
            Text("🪁")
                .font(.system(size: størrelse * 0.3))
                .offset(x: størrelse * 0.32, y: -størrelse * 0.32)
        }
        .frame(width: størrelse, height: størrelse)
    }
}

/// Civ-stil egenskapslinje i lederprofilen.
struct TrekkLinje: View {
    let navn: String
    let verdi: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(navn)
                .font(Theme.kroppFont(13))
                .foregroundStyle(Theme.blekkSvak)
                .frame(width: 100, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.linje)
                    Capsule()
                        .fill(verdi > 0.66 ? Theme.rød : verdi > 0.33 ? Theme.gul : Theme.grønn)
                        .frame(width: max(8, geo.size.width * verdi))
                }
            }
            .frame(height: 10)
        }
    }
}

/// Portrett av en motstander.
struct OpponentPortrett: View {
    let opponent: Opponent
    var størrelse: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: størrelse * 0.28, style: .continuous)
                .fill(opponent.portrettFarge)
            Text(opponent.emoji)
                .font(.system(size: størrelse * 0.5))
        }
        .frame(width: størrelse, height: størrelse)
        .overlay(
            RoundedRectangle(cornerRadius: størrelse * 0.28, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 2)
        )
    }
}
