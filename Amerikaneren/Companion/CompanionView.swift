import SwiftUI

/// Companion-modus: digital poengblokk når dere spiller med ekte kort.
/// 3–6 spillere. Per runde registreres bare budvinner, bud, makker og
/// motstandernes stikk – resten (lagets stikk, om budet holdt, poengene)
/// regnes ut automatisk. Partiet lagres fortløpende, så appen kan lukkes
/// midt i kvelden og fortsette senere.
struct CompanionView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = CompanionViewModel()

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            if vm.partiPågår {
                aktivtParti
            } else {
                oppsett
            }
        }
        .navigationTitle("Companion")
        .onAppear { vm.mittNavn = appState.spillerNavn }
    }

    // MARK: - Oppsett

    private var oppsett: some View {
        ScrollView {
            VStack(spacing: 18) {
                SnakkeBoble(tekst: "Spiller dere med ekte kort? Jeg fører poengene! Legg inn spillerne rundt bordet – deg selv inkludert.")
                PapirPanel {
                    VStack(spacing: 10) {
                        ForEach($vm.oppføringer) { $oppføring in
                            spillerRad($oppføring)
                        }
                        if vm.oppføringer.count < 6 {
                            Button {
                                vm.leggTilSpiller()
                            } label: {
                                Label("Legg til spiller", systemImage: "plus.circle.fill")
                                    .font(Theme.kroppFont(14).weight(.semibold))
                            }
                            .foregroundStyle(Theme.blå)
                        }
                    }
                }
                PapirPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Spill til et poengmål", isOn: $vm.harMål)
                            .font(Theme.kroppFont(15).weight(.semibold))
                            .foregroundStyle(Theme.blekk)
                        if vm.harMål {
                            Stepper("Første til \(vm.målPoeng) poeng", value: $vm.målPoeng, in: 20...150, step: 1)
                                .font(Theme.kroppFont(15))
                                .foregroundStyle(Theme.blekk)
                        } else {
                            Text("Åpent parti – dere spiller så lenge dere vil og avslutter når som helst.")
                                .font(Theme.kroppFont(13))
                                .foregroundStyle(Theme.blekkSvak)
                        }
                    }
                }
                Button("Start poengføring") { vm.startParti(appState: appState) }
                    .buttonStyle(BTButtonStyle(farge: Theme.grønn))
                    .disabled(!vm.kanStarte)
            }
            .padding(20)
        }
    }

    private func spillerRad(_ oppføring: Binding<CompanionViewModel.Oppføring>) -> some View {
        let index = vm.oppføringer.firstIndex { $0.id == oppføring.wrappedValue.id } ?? 0
        return HStack {
            TextField("Spiller \(index + 1)", text: oppføring.navn)
                .font(Theme.kroppFont(16))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.linje, lineWidth: 1.5))
                )
            if index == 0 {
                Text("(deg)")
                    .font(Theme.kroppFont(13))
                    .foregroundStyle(Theme.blekkSvak)
            } else {
                koblingsMeny(oppføring)
                if vm.oppføringer.count > 3 {
                    Button {
                        vm.fjernSpiller(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Theme.rød)
                    }
                }
            }
        }
    }

    /// Kobler spilleren til en bruker vi kjenner fra online-partier, slik
    /// at fysiske og digitale partier mot samme person telles sammen.
    @ViewBuilder
    private func koblingsMeny(_ oppføring: Binding<CompanionViewModel.Oppføring>) -> some View {
        let kjente = appState.kjenteOnlineBrukere
        let alleredeKoblet = registrertKobling(for: oppføring.wrappedValue.navn)
        let erKoblet = oppføring.wrappedValue.gameCenterId != nil || alleredeKoblet != nil
        if !kjente.isEmpty || erKoblet {
            Menu {
                ForEach(kjente, id: \.gameCenterId) { bruker in
                    Button(bruker.navn) { oppføring.wrappedValue.gameCenterId = bruker.gameCenterId }
                }
                if oppføring.wrappedValue.gameCenterId != nil {
                    Button("Fjern kobling", role: .destructive) {
                        oppføring.wrappedValue.gameCenterId = nil
                    }
                }
            } label: {
                Image(systemName: erKoblet ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                    .foregroundStyle(erKoblet ? Theme.grønn : Theme.blekkSvak)
            }
        }
    }

    /// Er navnet allerede en registrert spiller med brukerkobling?
    private func registrertKobling(for navn: String) -> String? {
        let ryddet = navn.trimmingCharacters(in: .whitespaces)
        guard !ryddet.isEmpty else { return nil }
        return appState.registrerteSpillere
            .first { $0.navn.compare(ryddet, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?
            .gameCenterId
    }

    // MARK: - Aktivt parti

    private var aktivtParti: some View {
        ScrollView {
            VStack(spacing: 18) {
                poengtavle
                if vm.ferdig {
                    ferdigPanel
                } else {
                    rundeSkjema
                }
                if !vm.runder.isEmpty {
                    historikk
                }
                if !vm.ferdig && vm.aktivtMål == nil && !vm.runder.isEmpty {
                    Button("Avslutt og lagre partiet") { vm.avsluttOgLagre(i: appState) }
                        .buttonStyle(BTButtonStyle(farge: Theme.grønn, stor: false))
                }
                Button("Avbryt partiet (uten å lagre)", role: .destructive) { vm.avbryt() }
                    .font(Theme.kroppFont(14))
                    .foregroundStyle(Theme.rød)
            }
            .padding(20)
        }
    }

    private var poengtavle: some View {
        PapirPanel {
            VStack(spacing: 8) {
                Text(vm.aktivtMål.map { "POENGTAVLE – først til \($0)" } ?? "POENGTAVLE – åpent parti")
                    .font(Theme.kroppFont(13).weight(.heavy))
                    .foregroundStyle(Theme.blekkSvak)
                    .tracking(1.5)
                ForEach(vm.spillere.indices, id: \.self) { i in
                    HStack {
                        Text("\(i + 1).")
                            .font(Theme.kroppFont(14))
                            .foregroundStyle(Theme.blekkSvak)
                        Text(vm.spillere[vm.sortert[i]])
                            .font(Theme.kroppFont(17).weight(.bold))
                            .foregroundStyle(Theme.blekk)
                        Spacer()
                        Text("\(vm.poeng[vm.sortert[i]])")
                            .font(Theme.tallFont(24))
                            .foregroundStyle(vm.aktivtMål.map { vm.poeng[vm.sortert[i]] >= $0 } == true ? Theme.grønn : Theme.blekk)
                    }
                }
            }
        }
    }

    private var rundeSkjema: some View {
        PapirPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Runde \(vm.runder.count + 1)")
                    .font(Theme.kroppFont(17).weight(.heavy))
                    .foregroundStyle(Theme.blekk)

                velger("Hvem vant budrunden?", valg: $vm.budgiver)

                Picker("Budtype", selection: $vm.budtype) {
                    ForEach(CompanionViewModel.Budtype.allCases) { type in
                        Text(type.navn).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                if vm.budtype == .vanlig {
                    Stepper("Bud: \(vm.bud) stikk", value: $vm.bud, in: 5...vm.kortPerSpiller)
                        .font(Theme.kroppFont(15))
                        .foregroundStyle(Theme.blekk)
                }
                if vm.budtype != .solo {
                    velger("Hvem ble makkeren?", valg: $vm.makker, tillatIngen: true)
                }

                Text("Hvor mange stikk fikk motstanderne?")
                    .font(Theme.kroppFont(13))
                    .foregroundStyle(Theme.blekkSvak)
                ForEach(vm.motstandere, id: \.self) { i in
                    Stepper("\(vm.spillere[i]): \(vm.motstanderStikk[i]) stikk", value: $vm.motstanderStikk[i], in: 0...vm.totalStikk)
                        .font(Theme.kroppFont(14))
                        .foregroundStyle(Theme.blekk)
                }

                utfallslinje

                Button("Før runden") { vm.førRunde() }
                    .buttonStyle(BTButtonStyle(farge: Theme.blå))
                    .disabled(!vm.kanFøreRunde)
            }
        }
    }

    /// Utledet resultat – vises så bordet kan kontrollere før runden føres.
    private var utfallslinje: some View {
        Group {
            if !vm.stikkGyldige {
                Text("⚠️ Motstanderne kan ikke ha mer enn \(vm.totalStikk) stikk til sammen.")
                    .font(Theme.kroppFont(13).weight(.semibold))
                    .foregroundStyle(Theme.rød)
            } else if !vm.makkerValgt {
                Text("Velg hvem som ble makkeren – bare solo-amerikaneren spilles alene.")
                    .font(Theme.kroppFont(13).weight(.semibold))
                    .foregroundStyle(Theme.blekkSvak)
            } else {
                switch vm.budtype {
                case .solo:
                    Text(vm.klarte
                         ? "✓ \(vm.spillere[vm.budgiver]) tok alle \(vm.totalStikk) stikkene alene – solo-amerikaner!"
                         : "✗ Soloen røk – motstanderne fikk \(vm.motstandernesStikk) stikk.")
                        .font(Theme.kroppFont(13).weight(.semibold))
                        .foregroundStyle(vm.klarte ? Theme.grønn : Theme.rød)
                case .amerikaner:
                    Text(vm.klarte
                         ? "✓ Laget tok alle \(vm.totalStikk) stikkene – Amerikaner!"
                         : "✗ Amerikaneren røk – motstanderne fikk \(vm.motstandernesStikk) stikk.")
                        .font(Theme.kroppFont(13).weight(.semibold))
                        .foregroundStyle(vm.klarte ? Theme.grønn : Theme.rød)
                case .vanlig:
                    Text(vm.klarte
                         ? "✓ Laget fikk \(vm.lagetsStikk) stikk – budet på \(vm.bud) holdt."
                         : "✗ Laget fikk bare \(vm.lagetsStikk) stikk – budet på \(vm.bud) røk.")
                        .font(Theme.kroppFont(13).weight(.semibold))
                        .foregroundStyle(vm.klarte ? Theme.grønn : Theme.rød)
                }
            }
        }
    }

    private func velger(_ tittel: String, valg: Binding<Int>, tillatIngen: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tittel)
                .font(Theme.kroppFont(13))
                .foregroundStyle(Theme.blekkSvak)
            Picker(tittel, selection: valg) {
                if tillatIngen {
                    Text("– velg –").tag(-1)
                }
                ForEach(vm.spillere.indices, id: \.self) { i in
                    Text(vm.spillere[i]).tag(i)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.blekk)
        }
    }

    private var ferdigPanel: some View {
        PapirPanel {
            VStack(spacing: 12) {
                Text("🏆 \(vm.vinnerIndex.map { vm.spillere[$0] } ?? "?") vant!")
                    .font(Theme.tittelFont(24))
                    .foregroundStyle(Theme.grønn)
                Button("Lagre i statistikken") { vm.avsluttOgLagre(i: appState) }
                    .buttonStyle(BTButtonStyle(farge: Theme.grønn))
            }
        }
    }

    private var historikk: some View {
        PapirPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text("Runde for runde")
                    .font(Theme.kroppFont(15).weight(.heavy))
                    .foregroundStyle(Theme.blekk)
                ForEach(vm.runder.indices, id: \.self) { i in
                    let runde = vm.runder[i]
                    HStack {
                        Text("\(i + 1).")
                            .foregroundStyle(Theme.blekkSvak)
                        Text(runde.beskrivelse(spillere: vm.spillere))
                            .foregroundStyle(Theme.blekk)
                        Spacer()
                        Text(runde.klarte ? "✓" : "✗")
                            .foregroundStyle(runde.klarte ? Theme.grønn : Theme.rød)
                    }
                    .font(Theme.kroppFont(13))
                }
                Button {
                    vm.angreSisteRunde()
                } label: {
                    Label("Angre siste runde", systemImage: "arrow.uturn.backward")
                        .font(Theme.kroppFont(13).weight(.semibold))
                }
                .foregroundStyle(Theme.blå)
                .padding(.top, 4)
            }
        }
    }
}
