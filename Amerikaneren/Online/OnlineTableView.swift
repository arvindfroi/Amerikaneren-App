import SwiftUI

/// Spillebordet for online-partier. Samme visuelle språk som offline-bordet,
/// men tegner fra `OnlineSnapshot` i stedet for direkte fra motoren.
struct OnlineTableView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var vm: OnlineGameViewModel

    var body: some View {
        ZStack {
            Theme.papirMørk.ignoresSafeArea()
            if let snap = vm.snap {
                bord(snap)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Deler ut kortene…")
                        .font(Theme.kroppFont(16))
                        .foregroundStyle(Theme.blekkSvak)
                }
            }
            if let info = vm.infoTekst {
                VStack {
                    SnakkeBoble(tekst: info, farge: Theme.gul.opacity(0.5))
                        .padding()
                    Spacer()
                }
            }
        }
    }

    // MARK: - Bordet

    private func bord(_ snap: OnlineSnapshot) -> some View {
        VStack(spacing: 8) {
            toppLinje(snap)
            HStack(spacing: 10) {
                ForEach(andreSeter, id: \.self) { sete in
                    brikke(sete: sete, snap: snap)
                }
            }
            Spacer(minLength: 0)
            midten(snap)
            Spacer(minLength: 0)
            bunn(snap)
        }
        .padding(.horizontal, 12)
        .overlay {
            if snap.phase == .rundeFerdig || snap.phase == .spillFerdig {
                sluttPanel(snap)
            }
        }
    }

    private var andreSeter: [Int] {
        (1...3).map { (vm.mittSete + $0) % 4 }
    }

    private func toppLinje(_ snap: OnlineSnapshot) -> some View {
        HStack {
            if let trumf = snap.trumf {
                Text("Trumf: \(trumf.navn) \(trumf.rawValue)")
                    .font(Theme.kroppFont(15).weight(.bold))
            } else if snap.erAmerikaner {
                Text("AMERIKANER – uten trumf!")
                    .font(Theme.kroppFont(15).weight(.bold))
                    .foregroundStyle(Theme.rød)
            } else {
                Text("Budrunde")
                    .font(Theme.kroppFont(15).weight(.bold))
            }
            Spacer()
            if let ønsket = snap.ønsketKort, !snap.makkerAvslørt {
                Text("Etterlyst: \(ønsket.kortSymbol)")
                    .font(Theme.kroppFont(14))
                    .foregroundStyle(Theme.blekkSvak)
            }
            Text("Stikk \(min(snap.trickNummer + 1, 13))/13")
                .font(Theme.kroppFont(14))
                .foregroundStyle(Theme.blekkSvak)
        }
        .foregroundStyle(Theme.blekk)
        .padding(.top, 4)
    }

    private func brikke(sete: Int, snap: OnlineSnapshot) -> some View {
        let erAktiv = snap.aktivSeat == sete && snap.phase != .rundeFerdig && snap.phase != .spillFerdig
        let sisteBud = snap.bids.last { $0.seat == sete }?.action.beskrivelse

        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.blå.opacity(0.2))
                    Text("👤").font(.system(size: 26))
                }
                .frame(width: 52, height: 52)
                if snap.budgiverSeat == sete {
                    Text("🎯").font(.system(size: 16)).offset(x: 6, y: -6)
                } else if snap.makkerSeat == sete {
                    Text("🤝").font(.system(size: 16)).offset(x: 6, y: -6)
                }
            }
            Text(vm.navn(for: sete))
                .font(Theme.kroppFont(11).weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("\(snap.scores[sete]) p")
                    .font(Theme.kroppFont(12).weight(.bold))
                    .foregroundStyle(Theme.blekk)
                Text("\(snap.stikkTatt[sete]) stikk")
                    .font(Theme.kroppFont(11))
                    .foregroundStyle(Theme.blekkSvak)
            }
            if let sisteBud, snap.phase == .budrunde || snap.phase == .velgTrumf {
                Text(sisteBud)
                    .font(Theme.kroppFont(11).weight(.bold))
                    .foregroundStyle(sisteBud == "Pass" ? Theme.blekkSvak : Theme.rød)
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

    // MARK: - Midten

    @ViewBuilder
    private func midten(_ snap: OnlineSnapshot) -> some View {
        if snap.phase == .budrunde, snap.aktivSeat == vm.mittSete {
            budPanel(snap)
        } else if snap.phase == .velgTrumf, snap.budgiverSeat == vm.mittSete {
            trumfPanel(snap)
        } else {
            stikkVisning(snap)
        }
    }

    private func stikkVisning(_ snap: OnlineSnapshot) -> some View {
        let stikk = snap.currentTrick.isEmpty && snap.phase == .spill
            ? snap.sisteStikk : snap.currentTrick
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.grønn.opacity(0.12))
                .frame(height: 150)
            if stikk.isEmpty {
                Text(snap.phase == .budrunde ? "Venter på bud…" : "Ingen kort på bordet")
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
                }
            }
        }
    }

    private func budPanel(_ snap: OnlineSnapshot) -> some View {
        let tallbud = snap.lovligeBud.compactMap { action -> Int? in
            if case .bud(let n) = action { return n }
            return nil
        }
        return PapirPanel {
            VStack(spacing: 12) {
                Text("Din tur til å by!")
                    .font(Theme.kroppFont(17).weight(.bold))
                    .foregroundStyle(Theme.blekk)
                if let høyeste = snap.høyesteBud {
                    Text("Høyeste bud: \(høyeste.action.beskrivelse) (\(vm.navn(for: høyeste.seat)))")
                        .font(Theme.kroppFont(13))
                        .foregroundStyle(Theme.blekkSvak)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tallbud, id: \.self) { n in
                            Button("\(n)") { vm.byr(.bud(n)) }
                                .font(Theme.tallFont(20))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(Theme.blå))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                HStack(spacing: 10) {
                    Button("Pass") { vm.byr(.pass) }
                        .buttonStyle(BTButtonStyle(farge: Theme.blekkSvak.opacity(0.9), stor: false))
                    if snap.lovligeBud.contains(.amerikaner) {
                        Button("AMERIKANER! 🇺🇸") { vm.byr(.amerikaner) }
                            .buttonStyle(BTButtonStyle(farge: Theme.rød, stor: false))
                    }
                }
            }
        }
    }

    @State private var valgtTrumf: Suit = .spar

    private func trumfPanel(_ snap: OnlineSnapshot) -> some View {
        // Ønskbare kort kan regnes ut lokalt: alle kort i fargen man ikke har selv.
        let ønskbare = Rank.allCases.reversed()
            .map { Card(suit: valgtTrumf, rank: $0) }
            .filter { !snap.dinHånd.contains($0) }

        return PapirPanel {
            VStack(spacing: 12) {
                Text("Du vant budrunden! Velg trumf:")
                    .font(Theme.kroppFont(16).weight(.bold))
                    .foregroundStyle(Theme.blekk)
                HStack(spacing: 10) {
                    ForEach(Suit.allCases) { suit in
                        Button {
                            valgtTrumf = suit
                        } label: {
                            Text(suit.rawValue)
                                .font(.system(size: 30))
                                .foregroundStyle(suit.erRød ? Theme.rød : Theme.blekk)
                                .frame(width: 52, height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(valgtTrumf == suit ? Theme.grønn : Theme.linje,
                                                              lineWidth: valgtTrumf == suit ? 3 : 1.5)
                                        )
                                )
                        }
                    }
                }
                Text("Be om et kort – eieren blir din hemmelige makker:")
                    .font(Theme.kroppFont(13))
                    .foregroundStyle(Theme.blekkSvak)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ønskbare) { kort in
                            Button {
                                vm.velgerTrumf(suit: valgtTrumf, kort: kort)
                            } label: {
                                CardView(kort: kort, bredde: 48, valgbar: true)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Hånden

    private func bunn(_ snap: OnlineSnapshot) -> some View {
        let lovlige = Set(snap.lovligeKort)
        let minTur = snap.phase == .spill && snap.aktivSeat == vm.mittSete

        return VStack(spacing: 6) {
            HStack {
                Text("\(vm.navn(for: vm.mittSete)) – \(snap.scores[vm.mittSete]) poeng, \(snap.stikkTatt[vm.mittSete]) stikk")
                    .font(Theme.kroppFont(14).weight(.bold))
                    .foregroundStyle(Theme.blekk)
                Spacer()
                if minTur {
                    Text("Din tur!")
                        .font(Theme.kroppFont(13).weight(.heavy))
                        .foregroundStyle(Theme.grønn)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -18) {
                    ForEach(snap.dinHånd) { kort in
                        Button {
                            vm.spiller(kort)
                        } label: {
                            CardView(
                                kort: kort, bredde: 62,
                                valgbar: minTur && lovlige.contains(kort),
                                dimmet: minTur && !lovlige.contains(kort)
                            )
                        }
                        .disabled(!minTur || !lovlige.contains(kort))
                        .offset(y: minTur && lovlige.contains(kort) ? -8 : 0)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Runde-/partislutt

    private func sluttPanel(_ snap: OnlineSnapshot) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            PapirPanel {
                VStack(spacing: 14) {
                    if snap.phase == .spillFerdig {
                        Text(snap.vinnerSeat == vm.mittSete ? "🏆 DU VANT!" : "🏁 \(vm.navn(for: snap.vinnerSeat ?? 0)) vant!")
                            .font(Theme.tittelFont(26))
                            .foregroundStyle(snap.vinnerSeat == vm.mittSete ? Theme.grønn : Theme.blekk)
                    } else if let runde = snap.sisteRunde {
                        Text(runde.klarte ? "Budet holdt! 🎉" : "Budet røk! 💥")
                            .font(Theme.tittelFont(24))
                            .foregroundStyle(runde.klarte ? Theme.grønn : Theme.rød)
                    }
                    if let runde = snap.sisteRunde {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(vm.navn(for: runde.budgiver)) bød \(runde.bud.beskrivelse.lowercased())")
                                .font(Theme.kroppFont(15).weight(.bold))
                                .foregroundStyle(Theme.blekk)
                            ForEach(0..<4, id: \.self) { sete in
                                HStack {
                                    Text(vm.navn(for: sete)).font(Theme.kroppFont(14))
                                    Spacer()
                                    Text(runde.poengEndring[sete] >= 0 ? "+\(runde.poengEndring[sete])" : "\(runde.poengEndring[sete])")
                                        .font(Theme.kroppFont(15).weight(.heavy))
                                        .foregroundStyle(runde.poengEndring[sete] >= 0 ? Theme.grønn : Theme.rød)
                                    Text("= \(snap.scores[sete])")
                                        .font(Theme.kroppFont(14).weight(.bold))
                                        .frame(width: 48, alignment: .trailing)
                                }
                                .foregroundStyle(Theme.blekk)
                            }
                        }
                    }
                    if snap.phase == .spillFerdig {
                        Button("Ferdig") {
                            vm.lagreStatistikk(i: appState)
                            vm.forlat()
                        }
                        .buttonStyle(BTButtonStyle(farge: Theme.blå))
                    } else if vm.erVert {
                        Button("Neste runde") { vm.nesteRunde() }
                            .buttonStyle(BTButtonStyle(farge: Theme.blå))
                    } else {
                        Text("Venter på verten…")
                            .font(Theme.kroppFont(14))
                            .foregroundStyle(Theme.blekkSvak)
                    }
                }
            }
            .padding(28)
        }
    }
}
