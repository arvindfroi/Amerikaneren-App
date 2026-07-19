import SwiftUI

/// Companion-modus: digital poengblokk når dere spiller med ekte kort.
/// Støtter 3–6 spillere, regner ut poengene automatisk og lagrer partiet
/// i statistikken (spilleren «Du» kobles til H2H).
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
                        ForEach(vm.navneliste.indices, id: \.self) { i in
                            HStack {
                                TextField("Spiller \(i + 1)", text: $vm.navneliste[i])
                                    .font(Theme.kroppFont(16))
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.white)
                                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.linje, lineWidth: 1.5))
                                    )
                                if i == 0 {
                                    Text("(deg)")
                                        .font(Theme.kroppFont(13))
                                        .foregroundStyle(Theme.blekkSvak)
                                } else if vm.navneliste.count > 3 {
                                    Button {
                                        vm.navneliste.remove(at: i)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(Theme.rød)
                                    }
                                }
                            }
                        }
                        if vm.navneliste.count < 6 {
                            Button {
                                vm.navneliste.append("")
                            } label: {
                                Label("Legg til spiller", systemImage: "plus.circle.fill")
                                    .font(Theme.kroppFont(14).weight(.semibold))
                            }
                            .foregroundStyle(Theme.blå)
                        }
                        Stepper("Spill til \(vm.målPoeng) poeng", value: $vm.målPoeng, in: 20...150, step: 1)
                            .font(Theme.kroppFont(15))
                            .foregroundStyle(Theme.blekk)
                    }
                }
                Button("Start poengføring") { vm.startParti() }
                    .buttonStyle(BTButtonStyle(farge: Theme.grønn))
                    .disabled(!vm.kanStarte)
            }
            .padding(20)
        }
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
                Button("Avbryt partiet", role: .destructive) { vm.avbryt() }
                    .font(Theme.kroppFont(14))
                    .foregroundStyle(Theme.rød)
            }
            .padding(20)
        }
    }

    private var poengtavle: some View {
        PapirPanel {
            VStack(spacing: 8) {
                Text("POENGTAVLE – først til \(vm.målPoeng)")
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
                            .foregroundStyle(vm.poeng[vm.sortert[i]] >= vm.målPoeng ? Theme.grønn : Theme.blekk)
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

                velger("Budgiver", valg: $vm.budgiver)
                Toggle("Amerikaner (alle stikk, med makker)", isOn: $vm.erAmerikaner)
                    .onChange(of: vm.erAmerikaner) { _, nå in if nå { vm.erSolo = false } }
                Toggle("Solo-amerikaner (alle stikk alene)", isOn: $vm.erSolo)
                    .onChange(of: vm.erSolo) { _, nå in if nå { vm.erAmerikaner = false } }
                    .font(Theme.kroppFont(14))
                    .foregroundStyle(Theme.blekk)

                if !vm.erAmerikaner && !vm.erSolo {
                    Stepper("Bud: \(vm.bud) stikk", value: $vm.bud, in: 1...vm.kortPerSpiller)
                        .font(Theme.kroppFont(15))
                        .foregroundStyle(Theme.blekk)
                }
                if !vm.erSolo {
                    velger("Makker (ingen = spiller alene)", valg: $vm.makker, tillatIngen: true)
                }

                Toggle(vm.erAmerikaner || vm.erSolo ? "Tok alle stikkene" : "Laget klarte budet", isOn: $vm.klarte)
                    .font(Theme.kroppFont(15).weight(.semibold))
                    .foregroundStyle(Theme.blekk)

                Text("Stikk til de andre spillerne:")
                    .font(Theme.kroppFont(13))
                    .foregroundStyle(Theme.blekkSvak)
                ForEach(vm.spillere.indices, id: \.self) { i in
                    if i != vm.budgiver && i != vm.makker {
                        Stepper("\(vm.spillere[i]): \(vm.stikk[i]) stikk", value: $vm.stikk[i], in: 0...vm.kortPerSpiller)
                            .font(Theme.kroppFont(14))
                            .foregroundStyle(Theme.blekk)
                    }
                }

                Button("Før runden") { vm.førRunde() }
                    .buttonStyle(BTButtonStyle(farge: Theme.blå))
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
                    Text("Ingen").tag(-1)
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
                Text("🏆 \(vm.spillere[vm.sortert[0]]) vant!")
                    .font(Theme.tittelFont(24))
                    .foregroundStyle(Theme.grønn)
                Button("Lagre i statistikken") {
                    appState.registrerParti(vm.lagMatchRecord())
                    vm.avbryt()
                }
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
            }
        }
    }
}
