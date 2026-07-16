import SwiftUI
import GameKit

/// Online-lobbyen: Game Center-innlogging, matchmaking og oppstart.
/// Verten (lavest gamePlayerID) starter partiet; tomme seter fylles med
/// CPU-er. Selve spillet foregår i OnlineTableView.
struct OnlineView: View {
    @EnvironmentObject private var appState: AppState
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
            vm.minRating = appState.eloRating
            vm.mineRankedKamper = appState.antallRankedKamper
            gc.loggInn()
        }
        .onChange(of: gc.match == nil) { _, ingenMatch in
            // Presenter deg med rating så verten kan sette opp ranked riktig.
            if !ingenMatch { vm.sendHello() }
        }
        .fullScreenCover(isPresented: $vm.spillAktivt) {
            OnlineTableView(vm: vm)
        }
    }

    @ViewBuilder
    private var innloggetInnhold: some View {
        SnakkeBoble(tekst: "Innlogget som \(gc.lokaltNavn). Finn et bord med venner eller tilfeldige motstandere!", farge: Theme.grønn.opacity(0.2))

        if gc.match == nil {
            PapirPanel {
                VStack(spacing: 10) {
                    HStack {
                        Text(appState.rankTier.emoji).font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(appState.rankTier.navn) • \(appState.eloRating)")
                                .font(Theme.kroppFont(17).weight(.heavy))
                                .foregroundStyle(Theme.blekk)
                            Text("Divisjon: \(appState.rankTier.intervall) rating")
                                .font(Theme.kroppFont(12))
                                .foregroundStyle(Theme.blekkSvak)
                        }
                        Spacer()
                    }
                    Button {
                        vm.rankedØnsket = true
                        gc.finnMatch(playerGroup: appState.rankTier.rawValue)
                    } label: {
                        Label("Ranked – finn motstandere i din divisjon", systemImage: "trophy.fill")
                    }
                    .buttonStyle(BTButtonStyle(farge: Theme.rød))
                    Text("Du matches kun mot spillere i samme divisjon. Rating oppdateres etter hvert parti (Elo).")
                        .font(Theme.kroppFont(12))
                        .foregroundStyle(Theme.blekkSvak)
                }
            }
            Button {
                vm.rankedØnsket = false
                gc.finnMatch()
            } label: {
                Label("Vennskapelig bord", systemImage: "person.3.fill")
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
