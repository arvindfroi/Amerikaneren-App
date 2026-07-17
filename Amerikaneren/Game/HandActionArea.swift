import SwiftUI

/// Tommelsonen: hånden + primærhandlingen, delt mellom offline- og
/// online-bordet. All kortinteraksjon skjer her, nederst på skjermen.
///
/// Interaksjonsmodell («bestemor-testen» – gest og knapp er likestilt):
/// 1. Trykk på et kort → kortet velges og løftes.
/// 2. Trykk på samme kort igjen, ELLER på den store «Spill kortet»-knappen,
///    ELLER dra kortet oppover → kortet spilles.
/// Ulovlige kort er nedtonet og reagerer ikke.
struct HandActionArea: View {
    let kort: [Card]
    let lovlige: Set<Card>
    let minTur: Bool
    let tittel: String
    var storeKort: Bool = false
    let spill: (Card) -> Void

    @State private var valgt: Card?

    private var kortBredde: CGFloat {
        storeKort ? DS.Mål.kortBreddeStor : DS.Mål.kortBredde
    }

    var body: some View {
        VStack(spacing: DS.Avstand.s) {
            statuslinje
            hånden
            if minTur {
                spillKnapp
                    .transition(DS.Bevegelse.panelInn)
            }
        }
        .padding(.bottom, DS.Avstand.xs)
        .animation(DS.Bevegelse.standard, value: valgt)
        .animation(DS.Bevegelse.standard, value: minTur)
        .onChange(of: kort) { _, _ in valgt = nil }
        .onChange(of: minTur) { _, nå in if !nå { valgt = nil } }
    }

    private var statuslinje: some View {
        HStack {
            Text(tittel)
                .font(DS.Tekst.etikett)
                .foregroundStyle(DS.Farge.blekk)
            Spacer()
            if minTur {
                Label("Din tur", systemImage: "hand.point.up.left.fill")
                    .font(DS.Tekst.etikett)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Avstand.m)
                    .padding(.vertical, DS.Avstand.xs)
                    .background(Capsule().fill(DS.Farge.grønn))
            }
        }
    }

    private var hånden: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: -kortBredde * 0.3) {
                ForEach(kort) { k in
                    kortVisning(k)
                }
            }
            .padding(.vertical, DS.Avstand.m)
            .padding(.horizontal, DS.Avstand.s)
        }
    }

    private func kortVisning(_ k: Card) -> some View {
        let erLovlig = lovlige.contains(k)
        let erValgt = valgt == k
        return CardView(
            kort: k,
            bredde: kortBredde,
            valgbar: minTur && erLovlig,
            dimmet: minTur && !erLovlig
        )
        .scaleEffect(erValgt ? 1.08 : 1)
        .offset(y: erValgt ? -22 : (minTur && erLovlig ? -6 : 0))
        .zIndex(erValgt ? 1 : 0)
        .onTapGesture {
            guard minTur, erLovlig else { return }
            if erValgt {
                spillValgt()
            } else {
                valgt = k
                Feedback.budGitt()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { verdi in
                    guard minTur, erLovlig, verdi.translation.height < -50 else { return }
                    valgt = k
                    spillValgt()
                }
        )
        .accessibilityLabel(k.beskrivelse)
        .accessibilityHint(erLovlig ? "Trykk to ganger for å velge" : "Kan ikke spilles nå")
    }

    private var spillKnapp: some View {
        VStack(spacing: DS.Avstand.xs) {
            Button {
                spillValgt()
            } label: {
                Label(
                    valgt.map { "Spill \($0.kortSymbol)" } ?? "Velg et kort",
                    systemImage: "arrow.up.circle.fill"
                )
            }
            .buttonStyle(BTButtonStyle(farge: valgt == nil ? DS.Farge.blekkSvak : DS.Farge.rød))
            .disabled(valgt == nil)
            Text("Trykk på et kort for å velge det – trykk igjen, dra opp eller bruk knappen for å spille")
                .font(DS.Tekst.liten)
                .foregroundStyle(DS.Farge.blekkSvak)
                .multilineTextAlignment(.center)
        }
    }

    private func spillValgt() {
        guard let k = valgt else { return }
        valgt = nil
        spill(k)
    }
}
