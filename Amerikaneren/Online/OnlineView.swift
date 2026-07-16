import SwiftUI
import GameKit

/// Online-lobbyen: Game Center-innlogging, matchmaking og oppstart.
/// Verten (lavest gamePlayerID) starter partiet; tomme seter fylles med
/// CPU-er. Selve spillet foregår i OnlineTableView.
struct OnlineView: View {
    @StateObject private var gc = GameCenterManager.delt
    @StateObject private var vm = OnlineGameViewModel()

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
                        innloggetInnhold
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
                            Text("Samme regler som offline: 4 ved bordet, hemmelig makker, først til 52. Er dere færre enn fire, fyller CPU-er de tomme setene. Faller noen fra, tar en CPU over. Resultatene teller i statistikken og H2H-oversikten din.")
                                .font(Theme.kroppFont(13))
                                .foregroundStyle(Theme.blekkSvak)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Online")
        .onAppear {
            vm.kobleTil()
            gc.loggInn()
        }
        .fullScreenCover(isPresented: $vm.spillAktivt) {
            OnlineTableView(vm: vm)
        }
    }

    @ViewBuilder
    private var innloggetInnhold: some View {
        SnakkeBoble(tekst: "Innlogget som \(gc.lokaltNavn). Finn et bord med venner eller tilfeldige motstandere!", farge: Theme.grønn.opacity(0.2))

        if gc.match == nil {
            Button {
                gc.finnMatch()
            } label: {
                Label("Finn et bord", systemImage: "person.3.fill")
            }
            .buttonStyle(BTButtonStyle(farge: Theme.grønn))
        } else {
            PapirPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ved bordet nå:")
                        .font(Theme.kroppFont(15).weight(.bold))
                        .foregroundStyle(Theme.blekk)
                    ForEach(gc.spillereIMatch, id: \.self) { navn in
                        Label(navn, systemImage: "person.fill")
                            .font(Theme.kroppFont(14))
                            .foregroundStyle(Theme.blekk)
                    }
                    if gc.spillereIMatch.count < 4 {
                        Label("\(4 - gc.spillereIMatch.count) CPU-utfyller(e)", systemImage: "cpu")
                            .font(Theme.kroppFont(14))
                            .foregroundStyle(Theme.blekkSvak)
                    }
                    if gc.erVert {
                        Button("Start partiet!") { vm.startSomVert() }
                            .buttonStyle(BTButtonStyle(farge: Theme.rød))
                    } else {
                        Text("Venter på at verten starter partiet…")
                            .font(Theme.kroppFont(13))
                            .foregroundStyle(Theme.blekkSvak)
                    }
                    Button("Forlat bordet") { vm.forlat() }
                        .buttonStyle(BTButtonStyle(farge: Theme.blekkSvak.opacity(0.9), stor: false))
                }
            }
        }
    }
}
