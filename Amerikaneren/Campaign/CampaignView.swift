import SwiftUI

/// Kampanjekartet i Punch-Out-stil: kretser med motstandere som låses opp
/// én etter én, frem til tittelkampen mot Onkel Sam.
struct CampaignView: View {
    @EnvironmentObject private var appState: AppState
    @State private var valgtStage: CampaignStage?

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    if appState.kampanje.erMester {
                        SnakkeBoble(tekst: "🏆 Du er MESTEREN! Tittelen «Amerikaneren» er din. Kretsene kan spilles på nytt når du vil.", farge: Theme.gul.opacity(0.4))
                    } else {
                        SnakkeBoble(tekst: "Slå deg gjennom ligaene, én motstander av gangen. Bare tittelkampen mot Onkel Sam gjenstår til slutt!")
                    }
                    ForEach(CampaignData.kretser) { krets in
                        kretsPanel(krets)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Kampanje")
        .sheet(item: $valgtStage) { stage in
            StageIntroView(stage: stage)
        }
    }

    private func kretsPanel(_ krets: CampaignCircuit) -> some View {
        PapirPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(krets.emoji) \(krets.navn)")
                        .font(Theme.kroppFont(18).weight(.heavy))
                        .foregroundStyle(Theme.blekk)
                    Spacer()
                    let fullførte = krets.stages.filter { appState.kampanje.fullførteStages.contains($0.id) }.count
                    Text("\(fullførte)/\(krets.stages.count)")
                        .font(Theme.kroppFont(14).weight(.bold))
                        .foregroundStyle(Theme.blekkSvak)
                }
                ForEach(krets.stages) { stage in
                    stageRad(stage, i: krets)
                }
            }
        }
    }

    private func stageRad(_ stage: CampaignStage, i krets: CampaignCircuit) -> some View {
        let låstOpp = appState.kampanje.erLåstOpp(stage, i: krets)
        let fullført = appState.kampanje.fullførteStages.contains(stage.id)
        let motstander = stage.hovedmotstander

        return Button {
            if låstOpp { valgtStage = stage }
        } label: {
            HStack(spacing: 12) {
                if låstOpp {
                    OpponentPortrett(opponent: motstander, størrelse: 46)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Theme.linje)
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Theme.blekkSvak)
                    }
                    .frame(width: 46, height: 46)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(låstOpp ? motstander.navn : "???")
                        .font(Theme.kroppFont(15).weight(.bold))
                        .foregroundStyle(Theme.blekk)
                    Text(låstOpp ? stage.scenarioTittel : "Lås opp forrige kamp først")
                        .font(Theme.kroppFont(12))
                        .foregroundStyle(Theme.blekkSvak)
                }
                Spacer()
                if fullført {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.grønn)
                } else if låstOpp {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.blekkSvak)
                }
            }
            .opacity(låstOpp ? 1 : 0.55)
        }
        .disabled(!låstOpp)
    }
}

/// Pre-kamp-skjerm i Punch-Out-stil: motstanderprofil, scenario og fight-knapp.
struct StageIntroView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let stage: CampaignStage
    @State private var starter = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.papir.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        Text("NESTE KAMP")
                            .font(Theme.kroppFont(13).weight(.heavy))
                            .foregroundStyle(Theme.rød)
                            .tracking(3)
                        OpponentPortrett(opponent: stage.hovedmotstander, størrelse: 110)
                        Text(stage.hovedmotstander.navn)
                            .font(Theme.tittelFont(28))
                            .foregroundStyle(Theme.blekk)
                        Text("«\(stage.hovedmotstander.tittel)» • \(stage.hovedmotstander.difficulty.rawValue)")
                            .font(Theme.kroppFont(14))
                            .foregroundStyle(Theme.blekkSvak)

                        SnakkeBoble(tekst: "«\(stage.hovedmotstander.introReplikk)»", farge: Theme.gul.opacity(0.35))

                        PapirPanel {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("📋 \(stage.scenarioTittel)")
                                    .font(Theme.kroppFont(16).weight(.heavy))
                                    .foregroundStyle(Theme.blekk)
                                Text(stage.scenarioTekst)
                                    .font(Theme.kroppFont(14))
                                    .foregroundStyle(Theme.blekkSvak)
                                Divider()
                                ForEach(scenarioPunkter, id: \.self) { punkt in
                                    Label(punkt, systemImage: "flag.fill")
                                        .font(Theme.kroppFont(13))
                                        .foregroundStyle(Theme.blekk)
                                }
                                Divider()
                                ForEach(stage.hovedmotstander.personality.trekk, id: \.navn) { trekk in
                                    TrekkLinje(navn: trekk.navn, verdi: trekk.verdi)
                                }
                            }
                        }

                        NavigationLink {
                            GameTableView(
                                vm: GameViewModel(
                                    motstandere: CampaignData.bordFor(stage: stage),
                                    spillerNavn: appState.spillerNavn,
                                    stage: stage
                                )
                            ) { bestått in
                                if bestått {
                                    appState.kampanje.fullførteStages.insert(stage.id)
                                } else {
                                    appState.kampanje.forsøk[stage.id, default: 0] += 1
                                }
                                dismiss()
                            }
                        } label: {
                            Text("FIGHT! 🥊")
                        }
                        .buttonStyle(BTButtonStyle(farge: Theme.rød))
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
        }
    }

    private var scenarioPunkter: [String] {
        var punkter = ["Først til \(stage.målPoeng) poeng"]
        if stage.motstanderStartPoeng > 0 {
            punkter.append("\(stage.hovedmotstander.navn) starter med \(stage.motstanderStartPoeng) poeng")
        }
        if stage.spillerStartPoeng > 0 {
            punkter.append("Du starter med \(stage.spillerStartPoeng) poeng")
        }
        if let krav = stage.kravMinsteBud {
            punkter.append("Du må vinne minst én budrunde med bud på \(krav) eller mer")
        }
        return punkter
    }
}
