import SwiftUI

/// Vrakpanelet når budvinneren har tatt opp talongen: velg nøyaktig
/// `antall` kort som legges bort – skjult for de andre spillerne.
/// Brukes både offline og online (callbacken avgjør hvor valget sendes).
struct ByttekortPanel: View {
    let hånd: [Card]
    let antall: Int
    let bekreft: ([Card]) -> Void

    @State private var valgte: Set<Card> = []

    var body: some View {
        PapirPanel {
            VStack(spacing: 10) {
                Text("Du tok talongen! Velg \(antall) kort å bytte ut:")
                    .font(Theme.kroppFont(16).weight(.bold))
                    .foregroundStyle(Theme.blekk)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(hånd) { kort in
                            kortKnapp(kort)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                Button {
                    guard valgte.count == antall else { return }
                    let vrak = Array(valgte)
                    valgte = []
                    bekreft(vrak)
                } label: {
                    Label("Legg bort \(valgte.count)/\(antall)", systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(BTButtonStyle(farge: valgte.count == antall ? Theme.rød : Theme.blekkSvak, stor: false))
                .disabled(valgte.count != antall)
                Text("Kortene du legger bort er ute av runden og forblir hemmelige.")
                    .font(Theme.kroppFont(12))
                    .foregroundStyle(Theme.blekkSvak)
                    .multilineTextAlignment(.center)
            }
        }
        .onChange(of: hånd) { _, _ in valgte = [] }
    }

    private func kortKnapp(_ kort: Card) -> some View {
        let erValgt = valgte.contains(kort)
        return Button {
            if erValgt {
                valgte.remove(kort)
            } else if valgte.count < antall {
                valgte.insert(kort)
                Feedback.budGitt()
            }
        } label: {
            CardView(kort: kort, bredde: 46, valgbar: true, dimmet: erValgt)
                .overlay(alignment: .topTrailing) {
                    if erValgt {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.rød)
                            .background(Circle().fill(.white))
                            .offset(x: 6, y: -6)
                    }
                }
                .offset(y: erValgt ? 6 : 0)
        }
        .accessibilityLabel(kort.beskrivelse)
        .accessibilityHint(erValgt ? "Valgt til å legges bort" : "Trykk for å legge bort")
    }
}
