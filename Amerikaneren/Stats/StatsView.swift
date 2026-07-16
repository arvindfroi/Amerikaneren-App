import SwiftUI

/// Detaljert statistikk i Brain Training-stil: store tall, papirpaneler,
/// og en «dagens resultat»-følelse. Med H2H-oversikt per rival.
struct StatsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var viserSlettAlert = false

    var body: some View {
        let stats = appState.mineStats

        ZStack {
            Theme.papir.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    if stats.antallPartier == 0 {
                        SnakkeBoble(tekst: "Ingen partier registrert ennå. Spill et parti – eller før et med companion-modus – så fyller jeg ut grafene dine!")
                    } else {
                        hovedtall(stats)
                        budStatistikk(stats)
                        moduser(stats)
                        h2hSeksjon
                        sisteKamper
                        Button("Slett all statistikk", role: .destructive) {
                            viserSlettAlert = true
                        }
                        .font(Theme.kroppFont(14))
                        .foregroundStyle(Theme.rød)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Statistikk")
        .alert("Slette alt?", isPresented: $viserSlettAlert) {
            Button("Slett", role: .destructive) { appState.slettAlleData() }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("All statistikk og kampanjefremdrift slettes. Dette kan ikke angres.")
        }
    }

    private func hovedtall(_ stats: AggregatedStats) -> some View {
        PapirPanel {
            VStack(spacing: 14) {
                Text("HOVEDTALL")
                    .font(Theme.kroppFont(13).weight(.heavy))
                    .foregroundStyle(Theme.blekkSvak)
                    .tracking(2)
                HStack(spacing: 12) {
                    statBoks(tall: "\(stats.antallPartier)", navn: "Partier")
                    statBoks(tall: "\(stats.seire)", navn: "Seire", farge: Theme.grønn)
                    statBoks(tall: String(format: "%.0f%%", stats.seiersprosent), navn: "Seiersprosent")
                }
                HStack(spacing: 12) {
                    statBoks(tall: "\(stats.lengsteSeiersrekke)", navn: "Beste rekke", farge: Theme.gul)
                    statBoks(tall: "\(stats.nåværendeRekke)", navn: "Rekke nå")
                    statBoks(tall: stats.besteScore == Int.min ? "–" : "\(stats.besteScore)", navn: "Beste score")
                }
            }
        }
    }

    private func budStatistikk(_ stats: AggregatedStats) -> some View {
        PapirPanel {
            VStack(spacing: 14) {
                Text("BUDGIVNING")
                    .font(Theme.kroppFont(13).weight(.heavy))
                    .foregroundStyle(Theme.blekkSvak)
                    .tracking(2)
                HStack(spacing: 12) {
                    statBoks(tall: "\(stats.budGitt)", navn: "Bud vunnet")
                    statBoks(tall: String(format: "%.0f%%", stats.budTreffprosent), navn: "Bud klart",
                             farge: stats.budTreffprosent >= 60 ? Theme.grønn : Theme.rød)
                    statBoks(tall: String(format: "%.1f", stats.snittBud), navn: "Snittbud")
                }
                HStack(spacing: 12) {
                    statBoks(tall: "\(stats.amerikanerMeldinger)", navn: "Amerikanere meldt", farge: Theme.rød)
                    statBoks(tall: "\(stats.amerikanerKlart)", navn: "Amerikanere klart", farge: Theme.gul)
                    statBoks(tall: String(format: "%.1f", stats.stikkPerRunde), navn: "Stikk/runde")
                }
                HStack(spacing: 12) {
                    statBoks(tall: stats.favorittTrumf ?? "–", navn: "Favorittrumf")
                    statBoks(tall: String(format: "%.1f", stats.snittPoeng), navn: "Snittpoeng/parti")
                }
            }
        }
    }

    private func moduser(_ stats: AggregatedStats) -> some View {
        PapirPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("PARTIER PER MODUS")
                    .font(Theme.kroppFont(13).weight(.heavy))
                    .foregroundStyle(Theme.blekkSvak)
                    .tracking(2)
                ForEach(MatchMode.allCases, id: \.self) { modus in
                    let antall = stats.partierPerModus[modus] ?? 0
                    if antall > 0 {
                        HStack {
                            Text(modus.rawValue).font(Theme.kroppFont(15))
                            Spacer()
                            Text("\(antall)").font(Theme.kroppFont(16).weight(.bold))
                        }
                        .foregroundStyle(Theme.blekk)
                    }
                }
            }
        }
    }

    private var h2hSeksjon: some View {
        PapirPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("HEAD-TO-HEAD")
                    .font(Theme.kroppFont(13).weight(.heavy))
                    .foregroundStyle(Theme.blekkSvak)
                    .tracking(2)
                ForEach(appState.headToHead) { h2h in
                    NavigationLink {
                        HeadToHeadView(h2h: h2h)
                    } label: {
                        HStack(spacing: 12) {
                            if let opponent = h2h.opponent {
                                OpponentPortrett(opponent: opponent, størrelse: 40)
                            } else {
                                ZStack {
                                    Circle().fill(Theme.blå.opacity(0.2))
                                    Text("👤")
                                }
                                .frame(width: 40, height: 40)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h2h.motstanderNavn)
                                    .font(Theme.kroppFont(15).weight(.bold))
                                    .foregroundStyle(Theme.blekk)
                                Text("\(h2h.partier) partier")
                                    .font(Theme.kroppFont(12))
                                    .foregroundStyle(Theme.blekkSvak)
                            }
                            Spacer()
                            Text("\(h2h.mineSeire)–\(h2h.deresSeire)")
                                .font(Theme.tallFont(20))
                                .foregroundStyle(h2h.mineSeire >= h2h.deresSeire ? Theme.grønn : Theme.rød)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.blekkSvak)
                        }
                    }
                }
            }
        }
    }

    private var sisteKamper: some View {
        PapirPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("SISTE PARTIER")
                    .font(Theme.kroppFont(13).weight(.heavy))
                    .foregroundStyle(Theme.blekkSvak)
                    .tracking(2)
                ForEach(appState.partier.sorted { $0.dato > $1.dato }.prefix(8)) { parti in
                    HStack {
                        Text(parti.jegVant ? "✅" : "❌")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(parti.mode.rawValue)
                                .font(Theme.kroppFont(14).weight(.semibold))
                                .foregroundStyle(Theme.blekk)
                            Text(parti.dato.formatted(date: .abbreviated, time: .shortened))
                                .font(Theme.kroppFont(11))
                                .foregroundStyle(Theme.blekkSvak)
                        }
                        Spacer()
                        if let meg = parti.deltakere.first(where: { $0.erMeg }) {
                            Text("\(meg.sluttPoeng) p")
                                .font(Theme.kroppFont(14).weight(.bold))
                                .foregroundStyle(Theme.blekk)
                        }
                    }
                }
            }
        }
    }

    private func statBoks(tall: String, navn: String, farge: Color = Theme.blekk) -> some View {
        VStack(spacing: 2) {
            Text(tall)
                .font(Theme.tallFont(26))
                .foregroundStyle(farge)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(navn)
                .font(Theme.kroppFont(11))
                .foregroundStyle(Theme.blekkSvak)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.papirMørk.opacity(0.7))
        )
    }
}
