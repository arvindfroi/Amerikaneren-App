import SwiftUI

/// Oppsummering etter hver runde: hvem bød, klarte de det, og poengendringene.
struct RundeOppsummeringView: View {
    @ObservedObject var vm: GameViewModel

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            VStack(spacing: 18) {
                if let runde = vm.engine.sisteRunde {
                    Text(runde.klarte ? "Budet holdt! 🎉" : "Budet røk! 💥")
                        .font(Theme.tittelFont(28))
                        .foregroundStyle(runde.klarte ? Theme.grønn : Theme.rød)

                    PapirPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(vm.navn(for: runde.budgiver)) bød \(runde.bud.beskrivelse.lowercased())")
                                .font(Theme.kroppFont(16).weight(.bold))
                                .foregroundStyle(Theme.blekk)
                            if let makker = runde.makker {
                                Text("Makker: \(vm.navn(for: makker))")
                                    .font(Theme.kroppFont(14))
                                    .foregroundStyle(Theme.blekkSvak)
                            }
                            if let trumf = runde.trumf {
                                Text("Trumf: \(trumf.navn) \(trumf.rawValue)")
                                    .font(Theme.kroppFont(14))
                                    .foregroundStyle(Theme.blekkSvak)
                            }
                            Divider()
                            ForEach(0..<4, id: \.self) { seat in
                                HStack {
                                    Text(vm.navn(for: seat))
                                        .font(Theme.kroppFont(15))
                                    Text("(\(runde.stikkPerSpiller[seat]) stikk)")
                                        .font(Theme.kroppFont(12)).foregroundStyle(Theme.blekkSvak)
                                    Spacer()
                                    Text(runde.poengEndring[seat] >= 0 ? "+\(runde.poengEndring[seat])" : "\(runde.poengEndring[seat])")
                                        .font(Theme.kroppFont(16).weight(.heavy))
                                        .foregroundStyle(runde.poengEndring[seat] >= 0 ? Theme.grønn : Theme.rød)
                                    Text("= \(vm.poeng(for: seat))")
                                        .font(Theme.kroppFont(14).weight(.bold))
                                        .foregroundStyle(Theme.blekk)
                                        .frame(width: 52, alignment: .trailing)
                                }
                                .foregroundStyle(Theme.blekk)
                            }
                        }
                    }
                }
                Button("Neste runde") { vm.nesteRunde() }
                    .buttonStyle(BTButtonStyle(farge: Theme.blå))
            }
            .padding(24)
        }
    }
}

/// Sluttskjerm for hele partiet, med Punch-Out-replikk fra hovedmotstanderen.
struct GameOverView: View {
    @ObservedObject var vm: GameViewModel
    let vedLukk: (Bool) -> Void

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            VStack(spacing: 20) {
                Text(vm.jegVant ? "🏆" : "😵").font(.system(size: 80))
                Text(vm.jegVant ? "DU VANT!" : "\(vm.vinnerSeat.map { vm.navn(for: $0) } ?? "Noen andre") vant…")
                    .font(Theme.tittelFont(32))
                    .foregroundStyle(vm.jegVant ? Theme.grønn : Theme.rød)

                if let stage = vm.stage, vm.jegVant, !vm.kampanjeBestått, let krav = stage.kravMinsteBud {
                    SnakkeBoble(tekst: "Du vant partiet, men klarte aldri et bud på \(krav)+. Scenarioet krever det – prøv igjen!", farge: Theme.gul.opacity(0.4))
                }
                if let replikk = vm.sisteReplikk {
                    HStack(alignment: .top, spacing: 10) {
                        if let hoved = vm.motstandere.first {
                            OpponentPortrett(opponent: hoved, størrelse: 52)
                        }
                        SnakkeBoble(tekst: "«\(replikk.tekst)»")
                    }
                    .padding(.horizontal)
                }

                PapirPanel {
                    VStack(spacing: 8) {
                        ForEach(sortertePlasser, id: \.self) { seat in
                            HStack {
                                Text(plassEmoji(for: seat))
                                Text(vm.navn(for: seat))
                                    .font(Theme.kroppFont(16).weight(seat == vm.vinnerSeat ? .heavy : .medium))
                                Spacer()
                                Text("\(vm.poeng(for: seat)) poeng")
                                    .font(Theme.kroppFont(16).weight(.bold))
                            }
                            .foregroundStyle(Theme.blekk)
                        }
                    }
                }

                Button("Ferdig") { vedLukk(vm.kampanjeBestått) }
                    .buttonStyle(BTButtonStyle(farge: Theme.blå))
            }
            .padding(24)
        }
    }

    private var sortertePlasser: [Int] {
        (0..<4).sorted { vm.poeng(for: $0) > vm.poeng(for: $1) }
    }

    private func plassEmoji(for seat: Int) -> String {
        let plass = sortertePlasser.firstIndex(of: seat) ?? 3
        return ["🥇", "🥈", "🥉", "  "][plass]
    }
}
