import SwiftUI

/// Oppsett for hurtigspill mot maskinen: velg vanskelighetsgrad og se
/// hvem som møter deg ved bordet (Civ-stil lederprofiler).
struct OfflineOppsettView: View {
    @EnvironmentObject private var appState: AppState
    @State private var difficulty: AIDifficulty = .middels
    @State private var bord: [Opponent] = OpponentRoster.tilfeldigBord(difficulty: .middels)
    @State private var valgtOpponent: Opponent?

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    PapirPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Vanskelighetsgrad")
                                .font(Theme.kroppFont(17).weight(.bold))
                                .foregroundStyle(Theme.blekk)
                            Picker("Vanskelighetsgrad", selection: $difficulty) {
                                ForEach([AIDifficulty.lett, .middels, .vanskelig]) { grad in
                                    Text(grad.rawValue).tag(grad)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(difficulty.beskrivelse)
                                .font(Theme.kroppFont(13))
                                .foregroundStyle(Theme.blekkSvak)
                        }
                    }

                    PapirPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Ved bordet")
                                    .font(Theme.kroppFont(17).weight(.bold))
                                    .foregroundStyle(Theme.blekk)
                                Spacer()
                                Button {
                                    bord = OpponentRoster.tilfeldigBord(difficulty: difficulty)
                                } label: {
                                    Label("Bytt bord", systemImage: "arrow.triangle.2.circlepath")
                                        .font(Theme.kroppFont(13).weight(.semibold))
                                }
                                .foregroundStyle(Theme.blå)
                            }
                            ForEach(bord) { motstander in
                                Button {
                                    valgtOpponent = motstander
                                } label: {
                                    HStack(spacing: 12) {
                                        OpponentPortrett(opponent: motstander, størrelse: 46)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(motstander.navn)
                                                .font(Theme.kroppFont(15).weight(.bold))
                                                .foregroundStyle(Theme.blekk)
                                            Text(motstander.tittel)
                                                .font(Theme.kroppFont(12))
                                                .foregroundStyle(Theme.blekkSvak)
                                        }
                                        Spacer()
                                        Image(systemName: "info.circle")
                                            .foregroundStyle(Theme.blekkSvak)
                                    }
                                }
                            }
                        }
                    }

                    NavigationLink {
                        GameTableView(vm: GameViewModel(motstandere: bord, spillerNavn: appState.spillerNavn))
                    } label: {
                        Text("Del ut kortene!")
                    }
                    .buttonStyle(BTButtonStyle(farge: Theme.rød))
                }
                .padding(20)
            }
        }
        .navigationTitle("Mot maskinen")
        .onChange(of: difficulty) { _, ny in
            bord = OpponentRoster.tilfeldigBord(difficulty: ny)
        }
        .sheet(item: $valgtOpponent) { motstander in
            OpponentProfilView(opponent: motstander)
                .presentationDetents([.medium])
        }
    }
}

/// Civ-stil lederprofil: portrett, agenda og egenskapslinjer.
struct OpponentProfilView: View {
    let opponent: Opponent

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    OpponentPortrett(opponent: opponent, størrelse: 84)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(opponent.navn)
                            .font(Theme.tittelFont(24))
                            .foregroundStyle(Theme.blekk)
                        Text("«\(opponent.tittel)»")
                            .font(Theme.kroppFont(15))
                            .foregroundStyle(Theme.rød)
                        Text(opponent.hjemsted)
                            .font(Theme.kroppFont(13))
                            .foregroundStyle(Theme.blekkSvak)
                    }
                    Spacer()
                }
                PapirPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Agenda")
                            .font(Theme.kroppFont(14).weight(.heavy))
                            .foregroundStyle(Theme.blekk)
                        Text(opponent.agenda)
                            .font(Theme.kroppFont(14))
                            .foregroundStyle(Theme.blekkSvak)
                        Divider()
                        ForEach(opponent.personality.trekk, id: \.navn) { trekk in
                            TrekkLinje(navn: trekk.navn, verdi: trekk.verdi)
                        }
                    }
                }
                SnakkeBoble(tekst: "«\(opponent.introReplikk)»", farge: Theme.gul.opacity(0.35))
                Spacer()
            }
            .padding(20)
        }
    }
}
