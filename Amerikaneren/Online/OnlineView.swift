import SwiftUI
import GameKit

/// Online-lobbyen: Game Center-innlogging og matchmaking.
/// Fullt onlinespill krever Game Center-oppsett i App Store Connect;
/// meldingsprotokollen ligger klar i GameCenterManager.
struct OnlineView: View {
    @StateObject private var gc = GameCenterManager.delt

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text("🌍").font(.system(size: 64))
                    Text("Spill online")
                        .font(Theme.tittelFont())
                        .foregroundStyle(Theme.blekk)

                    if gc.erInnlogget {
                        SnakkeBoble(tekst: "Innlogget som \(gcNavn). Finn et bord med venner eller tilfeldige motstandere via Game Center!", farge: Theme.grønn.opacity(0.2))
                        Button {
                            gc.finnMatch()
                        } label: {
                            Label("Finn et bord", systemImage: "person.3.fill")
                        }
                        .buttonStyle(BTButtonStyle(farge: Theme.grønn))

                        if gc.match != nil {
                            PapirPanel {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Ved bordet nå:")
                                        .font(Theme.kroppFont(15).weight(.bold))
                                        .foregroundStyle(Theme.blekk)
                                    ForEach(gc.spillereIMatch, id: \.self) { navn in
                                        Label(navn, systemImage: "person.fill")
                                            .font(Theme.kroppFont(14))
                                            .foregroundStyle(Theme.blekk)
                                    }
                                    Text("Venter på at bordet fylles… Partiet starter automatisk med 4 spillere.")
                                        .font(Theme.kroppFont(12))
                                        .foregroundStyle(Theme.blekkSvak)
                                    Button("Forlat bordet") { gc.forlatMatch() }
                                        .buttonStyle(BTButtonStyle(farge: Theme.rød, stor: false))
                                }
                            }
                        }
                    } else {
                        SnakkeBoble(tekst: "Onlinespill går gjennom Game Center. Logg inn, så finner vi motstandere til deg!")
                        Button {
                            gc.loggInn()
                        } label: {
                            Label("Logg inn med Game Center", systemImage: "gamecontroller.fill")
                        }
                        .buttonStyle(BTButtonStyle(farge: Theme.blå))
                        if let feil = gc.innloggingsFeil {
                            Text(feil)
                                .font(Theme.kroppFont(13))
                                .foregroundStyle(Theme.rød)
                        }
                    }

                    PapirPanel {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Slik virker det", systemImage: "info.circle.fill")
                                .font(Theme.kroppFont(14).weight(.bold))
                                .foregroundStyle(Theme.blekk)
                            Text("Online-partier spilles med samme regler som offline: 4 spillere, hemmelig makker, først til 52. Resultater teller i statistikken og H2H-oversikten din.")
                                .font(Theme.kroppFont(13))
                                .foregroundStyle(Theme.blekkSvak)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Online")
        .onAppear { gc.loggInn() }
    }

    private var gcNavn: String {
        GKLocalPlayer.local.displayName
    }
}
