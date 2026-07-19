import SwiftUI

/// Innstillinger: navn, lyd og haptikk.
struct InnstillingerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var navn = ""

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Text("Innstillinger")
                        .font(Theme.tittelFont(24))
                        .foregroundStyle(Theme.blekk)
                    Spacer()
                    Button("Ferdig") {
                        lagreNavn()
                        dismiss()
                    }
                    .font(Theme.kroppFont(15).weight(.bold))
                    .foregroundStyle(Theme.rød)
                }

                PapirPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Navn")
                                .font(Theme.kroppFont(13))
                                .foregroundStyle(Theme.blekkSvak)
                            TextField("Navnet ditt", text: $navn)
                                .font(Theme.kroppFont(17))
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white)
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.linje, lineWidth: 1.5))
                                )
                        }
                        Toggle("Lyd", isOn: $appState.lydPå)
                            .font(Theme.kroppFont(16))
                            .foregroundStyle(Theme.blekk)
                        Toggle("Haptikk (vibrasjon)", isOn: $appState.haptikkPå)
                            .font(Theme.kroppFont(16))
                            .foregroundStyle(Theme.blekk)
                        Toggle("Store kort", isOn: $appState.storeKort)
                            .font(Theme.kroppFont(16))
                            .foregroundStyle(Theme.blekk)
                    }
                }

                PapirPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Bidra til smartere motstandere", isOn: $appState.datadelingPå)
                            .font(Theme.kroppFont(16))
                            .foregroundStyle(Theme.blekk)
                        Text("Deler anonyme partiopptak (kort, bud og trekk) som "
                             + "treningsdata for AI-en. Aldri navn, aldri identitet. "
                             + "Skrur du av, slettes alt som ligger klart til sending.")
                            .font(Theme.kroppFont(12))
                            .foregroundStyle(Theme.blekkSvak)
                    }
                }

                PapirPanel {
                    HStack(spacing: 12) {
                        Text(appState.rankTier.emoji).font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(appState.rankTier.navn) • \(appState.eloRating) rating")
                                .font(Theme.kroppFont(16).weight(.heavy))
                                .foregroundStyle(Theme.blekk)
                            Text("\(appState.antallRankedKamper) ranked-kamper spilt")
                                .font(Theme.kroppFont(12))
                                .foregroundStyle(Theme.blekkSvak)
                        }
                        Spacer()
                    }
                }
                Spacer()
            }
            .padding(20)
        }
        .onAppear { navn = appState.spillerNavn }
        .tint(Theme.grønn)
    }

    private func lagreNavn() {
        let nyttNavn = navn.trimmingCharacters(in: .whitespaces)
        if !nyttNavn.isEmpty { appState.spillerNavn = nyttNavn }
    }
}
