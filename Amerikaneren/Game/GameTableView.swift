import SwiftUI

/// Selve spillebordet: motstandere øverst, stikket i midten, hånden nederst.
struct GameTableView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject var vm: GameViewModel
    var vedKampanjeSlutt: ((Bool) -> Void)? = nil

    var body: some View {
        ZStack {
            Theme.papirMørk.ignoresSafeArea()
            VStack(spacing: DS.Avstand.s) {
                motstanderRad
                toppLinje
                Spacer(minLength: 0)
                midten
                Spacer(minLength: 0)
                // Tommelsonen: alle handlinger nederst, innen rekkevidde.
                if vm.engine.phase == .budrunde && vm.engine.aktivBudgiver == 0 {
                    BiddingView(vm: vm)
                        .transition(DS.Bevegelse.panelInn)
                } else if vm.engine.phase == .byttekort && vm.engine.budgiverSeat == 0 {
                    ByttekortPanel(
                        hånd: vm.engine.hands.first ?? [],
                        antall: vm.engine.rules.antallByttekort
                    ) { vrak in
                        vm.menneskeVraker(vrak)
                    }
                    .transition(DS.Bevegelse.panelInn)
                } else if vm.engine.phase == .velgTrumf && vm.engine.budgiverSeat == 0 {
                    TrumfvalgView(vm: vm)
                        .transition(DS.Bevegelse.panelInn)
                }
                bunn
            }
            .padding(.horizontal, DS.Avstand.m)
            .animation(DS.Bevegelse.standard, value: vm.oppdatering)
        }
        .onAppear { if vm.engine.phase == .venterPåStart { vm.startSpill() } }
        .sheet(isPresented: $vm.visRundeOppsummering) {
            RundeOppsummeringView(vm: vm)
                .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $vm.visSpillFerdig) {
            GameOverView(vm: vm) { fullførtOgVunnet in
                appState.registrerParti(vm.lagMatchRecord())
                vedKampanjeSlutt?(fullførtOgVunnet)
                dismiss()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Gi opp") { dismiss() }
                    .foregroundStyle(Theme.rød)
            }
        }
    }

    // MARK: - Topp

    private var toppLinje: some View {
        HStack {
            if let trumf = vm.engine.trumf {
                Label {
                    Text("Trumf: \(trumf.navn)")
                } icon: {
                    Text(trumf.rawValue).foregroundStyle(trumf.erRød ? Theme.rød : Theme.blekk)
                }
                .font(Theme.kroppFont(15).weight(.bold))
            } else if vm.engine.erAmerikaner {
                Text("AMERIKANER – uten trumf!")
                    .font(Theme.kroppFont(15).weight(.bold))
                    .foregroundStyle(Theme.rød)
            } else {
                Text("Budrunde")
                    .font(Theme.kroppFont(15).weight(.bold))
            }
            Spacer()
            if let ønsket = vm.engine.ønsketKort, !vm.engine.makkerAvslørt {
                Text("Etterlyst: \(ønsket.kortSymbol)")
                    .font(Theme.kroppFont(14))
                    .foregroundStyle(Theme.blekkSvak)
            }
            if let fremdrift = budlagFremdrift {
                Text(fremdrift)
                    .font(Theme.kroppFont(14).weight(.bold))
                    .foregroundStyle(Theme.rød)
            }
            Text("Stikk \(min(vm.engine.trickNummer + 1, vm.engine.rules.kortPerSpiller))/\(vm.engine.rules.kortPerSpiller)")
                .font(Theme.kroppFont(14))
                .foregroundStyle(Theme.blekkSvak)
        }
        .foregroundStyle(Theme.blekk)
        .padding(.top, 4)
        .id(vm.oppdatering)
    }

    // MARK: - Motstandere

    private var motstanderRad: some View {
        HStack(spacing: 10) {
            ForEach(1..<4, id: \.self) { seat in
                spillerBrikke(seat: seat)
            }
        }
        .id(vm.oppdatering)
    }

    private func spillerBrikke(seat: Int) -> some View {
        let motstander = vm.opponent(for: seat)
        let erAktiv = (vm.engine.phase == .spill && vm.engine.aktivSpiller == seat)
            || (vm.engine.phase == .budrunde && vm.engine.aktivBudgiver == seat)
        let erBudgiver = vm.engine.budgiverSeat == seat
        let erKjentMakker = vm.engine.makkerAvslørt && vm.engine.makkerSeat == seat

        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let motstander {
                    OpponentPortrett(opponent: motstander, størrelse: 52)
                }
                if erBudgiver {
                    Text("🎯").font(.system(size: 16)).offset(x: 6, y: -6)
                } else if erKjentMakker {
                    Text("🤝").font(.system(size: 16)).offset(x: 6, y: -6)
                }
            }
            Text(motstander?.navn ?? "")
                .font(Theme.kroppFont(11).weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("\(vm.poeng(for: seat)) p")
                    .font(Theme.kroppFont(12).weight(.bold))
                    .foregroundStyle(Theme.blekk)
                Text("\(vm.engine.stikkTatt[seat]) stikk")
                    .font(Theme.kroppFont(11))
                    .foregroundStyle(Theme.blekkSvak)
            }
            if let bud = sisteBud(for: seat), vm.engine.phase == .budrunde || vm.engine.phase == .velgTrumf {
                Text(bud)
                    .font(Theme.kroppFont(11).weight(.bold))
                    .foregroundStyle(bud == "Pass" ? Theme.blekkSvak : Theme.rød)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(erAktiv ? 0.95 : 0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(erAktiv ? Theme.grønn : Theme.linje, lineWidth: erAktiv ? 3 : 1.5)
                )
        )
    }

    private func sisteBud(for seat: Int) -> String? {
        vm.engine.bids.last { $0.seat == seat }.map { $0.action.beskrivelse }
    }

    /// Budlagets fremdrift mot budet, basert på det som er offentlig kjent
    /// (uavslørt makkers stikk telles ikke med).
    private var budlagFremdrift: String? {
        guard vm.engine.phase == .spill, !vm.engine.erAmerikaner,
              let budgiver = vm.engine.budgiverSeat,
              case .bud(let mål)? = vm.engine.høyesteBud?.action else { return nil }
        var lagStikk = vm.engine.stikkTatt[budgiver]
        if vm.engine.makkerAvslørt, let makker = vm.engine.makkerSeat {
            lagStikk += vm.engine.stikkTatt[makker]
        }
        return "Budlaget: \(lagStikk)/\(mål)"
    }

    // MARK: - Midten

    @ViewBuilder
    private var midten: some View {
        VStack(spacing: DS.Avstand.m) {
            if let replikk = vm.sisteReplikk {
                SnakkeBoble(tekst: "\(replikk.navn): «\(replikk.tekst)»", farge: Theme.gul.opacity(0.35))
                    .font(DS.Tekst.etikett)
                    .transition(.scale.combined(with: .opacity))
            }
            stikkVisning
        }
        .id(vm.oppdatering)
    }

    private var stikkVisning: some View {
        let stikk = vm.engine.currentTrick.isEmpty && vm.engine.phase == .spill
            ? vm.engine.sisteStikk
            : vm.engine.currentTrick
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.grønn.opacity(0.12))
                .frame(height: 150)
            if stikk.isEmpty {
                Text(vm.engine.phase == .budrunde ? "Venter på bud…" : "Ingen kort på bordet")
                    .font(Theme.kroppFont(14))
                    .foregroundStyle(Theme.blekkSvak)
            }
            HStack(spacing: 14) {
                ForEach(stikk) { spill in
                    VStack(spacing: 4) {
                        CardView(kort: spill.card, bredde: 54)
                        Text(vm.navn(for: spill.seat))
                            .font(Theme.kroppFont(10))
                            .foregroundStyle(Theme.blekkSvak)
                            .lineLimit(1)
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            if let banner = vm.stikkBanner {
                VStack {
                    Text(banner)
                        .font(Theme.kroppFont(15).weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.grønn))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, 6)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: vm.oppdatering)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: vm.stikkBanner != nil)
    }

    // MARK: - Bunn (spillerens hånd)

    private var bunn: some View {
        HandActionArea(
            kort: vm.engine.hands.first ?? [],
            lovlige: Set(vm.engine.lovligeKort(for: 0)),
            minTur: vm.engine.phase == .spill && vm.engine.aktivSpiller == 0,
            tittel: "\(vm.spillerNavn) – \(vm.poeng(for: 0)) poeng, \(vm.engine.stikkTatt[0]) stikk",
            storeKort: appState.storeKort
        ) { kort in
            vm.menneskeSpiller(kort)
        }
    }
}
