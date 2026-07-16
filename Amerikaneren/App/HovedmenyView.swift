import SwiftUI

/// Hovedmenyen i Brain Training-stil: papirbakgrunn, maskot og store knapper.
struct HovedmenyView: View {
    @EnvironmentObject private var appState: AppState
    @State private var viserTutorial = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.papir.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        header

                        VStack(spacing: 14) {
                            NavigationLink {
                                OfflineOppsettView()
                            } label: {
                                menyRad(tittel: "Spill mot maskinen", undertekst: "Offline • velg vanskelighetsgrad", emoji: "🤖", farge: Theme.blå)
                            }
                            NavigationLink {
                                CampaignView()
                            } label: {
                                menyRad(tittel: "Kampanje", undertekst: appState.kampanje.erMester ? "MESTER 🏆 • spill igjen" : "Slå deg opp mot Onkel Sam", emoji: "🥊", farge: Theme.rød)
                            }
                            NavigationLink {
                                OnlineView()
                            } label: {
                                menyRad(tittel: "Spill online", undertekst: "Game Center-venner", emoji: "🌍", farge: Theme.grønn)
                            }
                            NavigationLink {
                                CompanionView()
                            } label: {
                                menyRad(tittel: "Companion-modus", undertekst: "Før poeng når dere spiller med ekte kort", emoji: "✏️", farge: Theme.gul)
                            }
                            NavigationLink {
                                StatsView()
                            } label: {
                                menyRad(tittel: "Statistikk & H2H", undertekst: "Alt om deg og rivalene dine", emoji: "📊", farge: Theme.blekk)
                            }
                        }

                        Button {
                            viserTutorial = true
                        } label: {
                            Label("Lær reglene på nytt", systemImage: "book.fill")
                        }
                        .buttonStyle(BTButtonStyle(farge: Theme.blekkSvak.opacity(0.9), stor: false))
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .sheet(isPresented: $viserTutorial) {
                TutorialView()
            }
        }
        .tint(Theme.blekk)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                MaskotView(størrelse: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AMERIKANEREN")
                        .font(Theme.tittelFont(32))
                        .foregroundStyle(Theme.blekk)
                    Text("Daglig kort-trening med Professor Duke")
                        .font(Theme.kroppFont(14))
                        .foregroundStyle(Theme.blekkSvak)
                }
                Spacer()
            }
            SnakkeBoble(tekst: hilsen)
        }
    }

    private var hilsen: String {
        let stats = appState.mineStats
        if stats.antallPartier == 0 {
            return "Velkommen, \(appState.spillerNavn)! Klar for ditt aller første parti?"
        }
        if stats.nåværendeRekke >= 3 {
            return "\(stats.nåværendeRekke) seire på rad! Hjernen din er i toppform i dag!"
        }
        return "Velkommen tilbake! Du har vunnet \(stats.seire) av \(stats.antallPartier) partier. Skal vi trene litt til?"
    }

    private func menyRad(tittel: String, undertekst: String, emoji: String, farge: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(farge.opacity(0.15))
                Text(emoji).font(.system(size: 28))
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(tittel)
                    .font(Theme.kroppFont(19).weight(.bold))
                    .foregroundStyle(Theme.blekk)
                Text(undertekst)
                    .font(Theme.kroppFont(13))
                    .foregroundStyle(Theme.blekkSvak)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.blekkSvak)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.linje, lineWidth: 2)
                )
        )
    }
}
