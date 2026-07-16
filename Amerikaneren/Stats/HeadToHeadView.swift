import SwiftUI

/// Dypdykk i rivaloppgjøret mot én bestemt motstander.
struct HeadToHeadView: View {
    @EnvironmentObject private var appState: AppState
    let h2h: HeadToHead

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    tallene
                    formkurve
                    if let opponent = h2h.opponent {
                        PapirPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("LEDERPROFIL")
                                    .font(Theme.kroppFont(13).weight(.heavy))
                                    .foregroundStyle(Theme.blekkSvak)
                                    .tracking(2)
                                Text(opponent.agenda)
                                    .font(Theme.kroppFont(14))
                                    .foregroundStyle(Theme.blekk)
                                ForEach(opponent.personality.trekk, id: \.navn) { trekk in
                                    TrekkLinje(navn: trekk.navn, verdi: trekk.verdi)
                                }
                            }
                        }
                    }
                    møteHistorikk
                }
                .padding(20)
            }
        }
        .navigationTitle("Rivaloppgjør")
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                VStack {
                    ZStack {
                        Circle().fill(Theme.blå.opacity(0.15))
                        Text("🧑").font(.system(size: 34))
                    }
                    .frame(width: 70, height: 70)
                    Text(appState.spillerNavn)
                        .font(Theme.kroppFont(14).weight(.bold))
                        .foregroundStyle(Theme.blekk)
                }
                Text("\(h2h.mineSeire) – \(h2h.deresSeire)")
                    .font(Theme.tallFont(40))
                    .foregroundStyle(h2h.mineSeire >= h2h.deresSeire ? Theme.grønn : Theme.rød)
                VStack {
                    if let opponent = h2h.opponent {
                        OpponentPortrett(opponent: opponent, størrelse: 70)
                    } else {
                        ZStack {
                            Circle().fill(Theme.rød.opacity(0.15))
                            Text("👤").font(.system(size: 34))
                        }
                        .frame(width: 70, height: 70)
                    }
                    Text(h2h.motstanderNavn)
                        .font(Theme.kroppFont(14).weight(.bold))
                        .foregroundStyle(Theme.blekk)
                }
            }
            if h2h.mineSeire > h2h.deresSeire {
                Text("Du eier dette oppgjøret! 💪")
                    .font(Theme.kroppFont(14))
                    .foregroundStyle(Theme.grønn)
            } else if h2h.mineSeire < h2h.deresSeire {
                Text("Rivalen leder – på tide med revansj!")
                    .font(Theme.kroppFont(14))
                    .foregroundStyle(Theme.rød)
            } else {
                Text("Helt jevnt – neste parti avgjør!")
                    .font(Theme.kroppFont(14))
                    .foregroundStyle(Theme.blekkSvak)
            }
        }
    }

    private var tallene: some View {
        PapirPanel {
            VStack(spacing: 8) {
                rad("Partier spilt", "\(h2h.partier)")
                rad("Min snittmargin", String(format: "%+.1f poeng", h2h.minSnittMargin))
                rad("Største seier", h2h.størsteSeierMargin == Int.min ? "–" : "+\(h2h.størsteSeierMargin) poeng")
                rad("Budrunder jeg vant", "\(h2h.budDuellMine)")
                rad("Budrunder de vant", "\(h2h.budDuellDeres)")
                if let siste = h2h.sisteMøte {
                    rad("Sist møtt", siste.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    private var formkurve: some View {
        PapirPanel {
            VStack(spacing: 10) {
                Text("SISTE FEM MØTER")
                    .font(Theme.kroppFont(13).weight(.heavy))
                    .foregroundStyle(Theme.blekkSvak)
                    .tracking(2)
                HStack(spacing: 10) {
                    ForEach(h2h.sisteFem.indices, id: \.self) { i in
                        Text(h2h.sisteFem[i] ? "S" : "T")
                            .font(Theme.kroppFont(16).weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(h2h.sisteFem[i] ? Theme.grønn : Theme.rød))
                    }
                }
            }
        }
    }

    private var møteHistorikk: some View {
        let partier = appState.partier
            .filter { parti in parti.deltakere.contains { $0.id == h2h.motstanderId } }
            .sorted { $0.dato > $1.dato }

        return PapirPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("ALLE MØTER")
                    .font(Theme.kroppFont(13).weight(.heavy))
                    .foregroundStyle(Theme.blekkSvak)
                    .tracking(2)
                ForEach(partier) { parti in
                    if let meg = parti.deltakere.first(where: { $0.erMeg }),
                       let dem = parti.deltakere.first(where: { $0.id == h2h.motstanderId }) {
                        HStack {
                            Text(meg.vantPartiet ? "✅" : dem.vantPartiet ? "❌" : "➖")
                            Text(parti.dato.formatted(date: .numeric, time: .omitted))
                                .font(Theme.kroppFont(13))
                                .foregroundStyle(Theme.blekkSvak)
                            Spacer()
                            Text("\(meg.sluttPoeng) – \(dem.sluttPoeng)")
                                .font(Theme.kroppFont(15).weight(.bold))
                                .foregroundStyle(Theme.blekk)
                        }
                    }
                }
            }
        }
    }

    private func rad(_ navn: String, _ verdi: String) -> some View {
        HStack {
            Text(navn).font(Theme.kroppFont(14)).foregroundStyle(Theme.blekkSvak)
            Spacer()
            Text(verdi).font(Theme.kroppFont(15).weight(.bold)).foregroundStyle(Theme.blekk)
        }
    }
}
