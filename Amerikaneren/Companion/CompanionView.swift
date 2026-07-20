import SwiftUI

/// Companion-modus i bordmodus: mobilen ligger flatt på bordet som
/// poengtavle hele kvelden, og hver runde føres med en håndfull store
/// trykk i de tre øyeblikkene bordet naturlig har – budrunden avgjort
/// (hvem + hva), ønskekortet lagt (makkeren) og runden ferdig
/// (motstandernes stikk, rett på tallet). Resten regnes ut. Skjermen
/// holdes våken så lenge partiet pågår.
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
        .onAppear {
            vm.mittNavn = appState.spillerNavn
            UIApplication.shared.isIdleTimerDisabled = vm.partiPågår
        }
        .onChange(of: vm.partiPågår) { _, pågår in
            // Poengtavla skal ligge våken på bordet hele kvelden.
            UIApplication.shared.isIdleTimerDisabled = pågår
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Oppsett

    private var oppsett: some View {
        ScrollView {
            VStack(spacing: 18) {
                SnakkeBoble(tekst: "Spiller dere med ekte kort? Legg mobilen på bordet, så fører jeg poengene! Legg inn spillerne rundt bordet – deg selv inkludert.")
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

    // MARK: - Aktivt parti (bordmodus)

    private var aktivtParti: some View {
        ScrollView {
            VStack(spacing: 16) {
                poengtavle
                if vm.ferdig {
                    ferdigPanel
                } else {
                    switch vm.steg {
                    case .velgBudgiver: budgiverSpørsmål
                    case .velgBud: budSpørsmål
                    case .spilles: spillesPanel
                    }
                }
                if !vm.runder.isEmpty {
                    historikk
                }
                bunnKnapper
            }
            .padding(16)
        }
    }

    private var poengtavle: some View {
        PapirPanel {
            VStack(spacing: 8) {
                Text(vm.aktivtMål.map { "FØRST TIL \($0)" } ?? "ÅPENT PARTI")
                    .font(Theme.kroppFont(13).weight(.heavy))
                    .foregroundStyle(Theme.blekkSvak)
                    .tracking(1.5)
                ForEach(vm.spillere.indices, id: \.self) { i in
                    HStack {
                        Text(vm.spillere[vm.sortert[i]])
                            .font(Theme.kroppFont(20).weight(.bold))
                            .foregroundStyle(Theme.blekk)
                        Spacer()
                        Text("\(vm.poeng[vm.sortert[i]])")
                            .font(Theme.tallFont(30))
                            .foregroundStyle(vm.aktivtMål.map { vm.poeng[vm.sortert[i]] >= $0 } == true ? Theme.grønn : Theme.blekk)
                    }
                }
            }
        }
    }

    // Steg 1: «Hvem vant budrunden?» – ett trykk på et stort navn.
    private var budgiverSpørsmål: some View {
        PapirPanel {
            VStack(spacing: 12) {
                Text("Runde \(vm.runder.count + 1)")
                    .font(Theme.kroppFont(13).weight(.heavy))
                    .foregroundStyle(Theme.blekkSvak)
                    .tracking(1.5)
                Text("Hvem vant budrunden?")
                    .font(Theme.kroppFont(19).weight(.heavy))
                    .foregroundStyle(Theme.blekk)
                navneRutenett { sete in
                    vm.velgBudgiver(sete)
                }
            }
        }
    }

    // Steg 2: «Hva byr X?» – ett trykk rett på tallet (eller meldingen).
    private var budSpørsmål: some View {
        PapirPanel {
            VStack(spacing: 12) {
                Text("Hva byr \(vm.spillere[vm.budgiver])?")
                    .font(Theme.kroppFont(19).weight(.heavy))
                    .foregroundStyle(Theme.blekk)
                tallRutenett(tall: Array(5...vm.totalStikk), valgt: nil) { tall in
                    vm.velgBud(tall)
                }
                HStack(spacing: 10) {
                    storKnapp("AMERIKANER", farge: Theme.rød) { vm.velgAmerikaner() }
                    storKnapp("SOLO", farge: Theme.blekk) { vm.velgSolo() }
                }
                tilbakeChip("Feil navn? Tilbake") { vm.tilbakeTilBudrunde() }
            }
        }
    }

    // Steg 3: hvileskjerm mens runden spilles – makker når ønskekortet
    // legges, stikk når runden er ferdig, alt med ett trykk per svar.
    private var spillesPanel: some View {
        VStack(spacing: 16) {
            PapirPanel {
                VStack(spacing: 10) {
                    Text(budBanner)
                        .font(Theme.kroppFont(17).weight(.heavy))
                        .foregroundStyle(Theme.blekk)
                        .multilineTextAlignment(.center)
                    if vm.budtype != .solo && vm.makkerIndex == nil {
                        Text("Hvem la ønskekortet?")
                            .font(Theme.kroppFont(14))
                            .foregroundStyle(Theme.blekkSvak)
                        navneRutenett(unntatt: [vm.budgiver]) { sete in
                            vm.velgMakker(sete)
                        }
                    } else if let makker = vm.makkerIndex {
                        Text("Makker: \(vm.spillere[makker])")
                            .font(Theme.kroppFont(14).weight(.semibold))
                            .foregroundStyle(Theme.blekkSvak)
                    }
                    tilbakeChip("Endre budet") { vm.tilbakeTilBudrunde() }
                }
            }

            PapirPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Når runden er ferdig: stikkene til motstanderne")
                        .font(Theme.kroppFont(14).weight(.semibold))
                        .foregroundStyle(Theme.blekkSvak)
                    ForEach(vm.motstandere, id: \.self) { sete in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vm.spillere[sete])
                                .font(Theme.kroppFont(15).weight(.bold))
                                .foregroundStyle(Theme.blekk)
                            tallRutenett(tall: Array(0...vm.totalStikk),
                                         valgt: vm.motstanderStikk[sete],
                                         kompakt: true) { antall in
                                vm.settStikk(antall, for: sete)
                            }
                        }
                    }
                    utfallslinje
                    Button("Før runden") { vm.førRunde() }
                        .buttonStyle(BTButtonStyle(farge: Theme.blå))
                        .disabled(!vm.kanFøreRunde)
                }
            }
        }
    }

    private var budBanner: String {
        switch vm.budtype {
        case .solo: return "\(vm.spillere[vm.budgiver]) har meldt SOLO-AMERIKANER!"
        case .amerikaner: return "\(vm.spillere[vm.budgiver]) har meldt AMERIKANER!"
        case .vanlig: return "\(vm.spillere[vm.budgiver]) spiller \(vm.bud) stikk"
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
                Text("Trykk på makkeren over når ønskekortet er lagt.")
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

    // MARK: - Byggeklosser: store trykkflater

    private func navneRutenett(unntatt: Set<Int> = [], handling: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            ForEach(vm.spillere.indices.filter { !unntatt.contains($0) }, id: \.self) { sete in
                Button {
                    handling(sete)
                } label: {
                    Text(vm.spillere[sete])
                        .font(Theme.kroppFont(18).weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(TrykkflateStil())
            }
        }
    }

    private func tallRutenett(tall: [Int], valgt: Int?, kompakt: Bool = false,
                              handling: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: kompakt ? 44 : 56), spacing: 8)], spacing: 8) {
            ForEach(tall, id: \.self) { verdi in
                Button {
                    handling(verdi)
                } label: {
                    Text("\(verdi)")
                        .font(Theme.tallFont(kompakt ? 17 : 22))
                        .frame(maxWidth: .infinity, minHeight: kompakt ? 44 : 54)
                }
                .buttonStyle(TrykkflateStil(valgt: valgt == verdi))
            }
        }
    }

    private func storKnapp(_ tittel: String, farge: Color, handling: @escaping () -> Void) -> some View {
        Button(action: handling) {
            Text(tittel)
                .font(Theme.kroppFont(15).weight(.heavy))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(TrykkflateStil(tekstFarge: farge))
    }

    private func tilbakeChip(_ tittel: String, handling: @escaping () -> Void) -> some View {
        Button(action: handling) {
            Label(tittel, systemImage: "arrow.uturn.backward")
                .font(Theme.kroppFont(13).weight(.semibold))
        }
        .foregroundStyle(Theme.blekkSvak)
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

    private var bunnKnapper: some View {
        VStack(spacing: 8) {
            if !vm.ferdig && vm.aktivtMål == nil && !vm.runder.isEmpty {
                Button("Avslutt og lagre partiet") { vm.avsluttOgLagre(i: appState) }
                    .buttonStyle(BTButtonStyle(farge: Theme.grønn, stor: false))
            }
            Button("Avbryt partiet (uten å lagre)", role: .destructive) { vm.avbryt() }
                .font(Theme.kroppFont(14))
                .foregroundStyle(Theme.rød)
        }
    }
}

/// Stor, tydelig trykkflate for bordmodus: hvit kortbakgrunn, ramme og
/// tydelig markering av valgt verdi – store nok til å treffes på tvers
/// av bordet uten å løfte mobilen.
private struct TrykkflateStil: ButtonStyle {
    var valgt: Bool = false
    var tekstFarge: Color = Theme.blekk

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(valgt ? .white : tekstFarge)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(valgt ? Theme.blå : .white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(valgt ? Theme.blå : Theme.linje, lineWidth: 1.5)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
