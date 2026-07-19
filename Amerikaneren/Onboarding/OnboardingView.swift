import SwiftUI

/// Skippbar onboarding: velkomst, navn, og en kjapp regeloversikt.
/// «Hopp over»-knappen er alltid synlig.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var side = 0
    @State private var navn = ""
    @State private var viserTutorial = false

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Hopp over") { fullfør() }
                        .font(Theme.kroppFont(15).weight(.semibold))
                        .foregroundStyle(Theme.blekkSvak)
                        .padding()
                }

                TabView(selection: $side) {
                    velkomst.tag(0)
                    navneside.tag(1)
                    regelkort(
                        emoji: "🎯", tittel: "Byd på stikk",
                        tekst: "Alle får 12 kort – fire ligger i talongen som budvinneren bytter med. I budrunden melder du hvor mange stikk laget ditt klarer – eller roper «AMERIKANER!» (alle stikk med makker) eller «SOLO!» (alle alene)."
                    ).tag(2)
                    regelkort(
                        emoji: "🤝", tittel: "Hemmelig makker",
                        tekst: "Budvinneren velger trumf og ber om et kort, f.eks. spar ess. Den som har kortet blir hemmelig makker – og avsløres først når kortet legges!"
                    ).tag(3)
                    regelkort(
                        emoji: "🏁", tittel: "Først til 100",
                        tekst: "Klarer laget budet, får budvinneren dobbelt bud og makkeren budet i poeng. Feiler dere, trekkes det samme. Alle andre får ett poeng per stikk. Førstemann til 100 vinner!"
                    ).tag(4)
                    sisteSide.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(side == 5 ? "Sett i gang!" : "Neste") {
                    if side == 5 { fullfør() } else { withAnimation { side += 1 } }
                }
                .buttonStyle(BTButtonStyle(farge: Theme.rød))
                .padding(20)
            }
        }
        .sheet(isPresented: $viserTutorial, onDismiss: { fullfør() }) {
            TutorialView()
        }
    }

    private var velkomst: some View {
        VStack(spacing: 24) {
            MaskotView(størrelse: 120)
            Text("Velkommen til\nAMERIKANEREN")
                .font(Theme.tittelFont(34))
                .foregroundStyle(Theme.blekk)
                .multilineTextAlignment(.center)
            SnakkeBoble(tekst: "God dag! Benjamin Franklin, til tjeneste. Jeg skal lære deg Norges morsomste stikkspill – på under ett minutt.")
                .padding(.horizontal, 24)
        }
        .padding()
    }

    private var navneside: some View {
        VStack(spacing: 24) {
            MaskotView(størrelse: 90)
            Text("Hva heter du?")
                .font(Theme.tittelFont())
                .foregroundStyle(Theme.blekk)
            TextField("Navnet ditt", text: $navn)
                .font(Theme.kroppFont(22))
                .multilineTextAlignment(.center)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.linje, lineWidth: 2))
                )
                .padding(.horizontal, 40)
            Text("Navnet brukes i statistikken og online.")
                .font(Theme.kroppFont(13))
                .foregroundStyle(Theme.blekkSvak)
        }
        .padding()
    }

    private func regelkort(emoji: String, tittel: String, tekst: String) -> some View {
        VStack(spacing: 20) {
            Text(emoji).font(.system(size: 72))
            Text(tittel)
                .font(Theme.tittelFont())
                .foregroundStyle(Theme.blekk)
            PapirPanel {
                Text(tekst)
                    .font(Theme.kroppFont(18))
                    .foregroundStyle(Theme.blekk)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .padding()
    }

    private var sisteSide: some View {
        VStack(spacing: 24) {
            MaskotView(størrelse: 90)
            Text("Klar, ferdig, spill!")
                .font(Theme.tittelFont())
                .foregroundStyle(Theme.blekk)
            SnakkeBoble(tekst: "Vil du ta en grundig gjennomgang med eksempler først, eller hoppe rett i det?")
                .padding(.horizontal, 24)
            Button {
                viserTutorial = true
            } label: {
                Label("Vis meg tutorialen", systemImage: "graduationcap.fill")
            }
            .buttonStyle(BTButtonStyle(farge: Theme.blå, stor: false))
        }
        .padding()
    }

    private func fullfør() {
        if !navn.trimmingCharacters(in: .whitespaces).isEmpty {
            appState.spillerNavn = navn.trimmingCharacters(in: .whitespaces)
        }
        withAnimation { appState.harFullførtOnboarding = true }
    }
}
