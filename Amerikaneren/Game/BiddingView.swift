import SwiftUI

/// Budpanelet når det er menneskets tur i budrunden.
struct BiddingView: View {
    @ObservedObject var vm: GameViewModel

    var body: some View {
        let lovlige = vm.engine.lovligeBud(for: 0)
        let tallbud = lovlige.compactMap { action -> Int? in
            if case .bud(let n) = action { return n }
            return nil
        }

        return PapirPanel {
            VStack(spacing: 12) {
                Text("Din tur til å by!")
                    .font(Theme.kroppFont(17).weight(.bold))
                    .foregroundStyle(Theme.blekk)
                if let høyeste = vm.engine.høyesteBud {
                    Text("Høyeste bud: \(høyeste.action.beskrivelse) (\(vm.navn(for: høyeste.seat)))")
                        .font(Theme.kroppFont(13))
                        .foregroundStyle(Theme.blekkSvak)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tallbud, id: \.self) { n in
                            Button("\(n)") { vm.menneskeByr(.bud(n)) }
                                .font(Theme.tallFont(20))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(Theme.blå))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                HStack(spacing: 10) {
                    Button("Pass") { vm.menneskeByr(.pass) }
                        .buttonStyle(BTButtonStyle(farge: Theme.blekkSvak.opacity(0.9), stor: false))
                    if lovlige.contains(.amerikaner) {
                        Button("AMERIKANER! 🇺🇸") { vm.menneskeByr(.amerikaner) }
                            .buttonStyle(BTButtonStyle(farge: Theme.rød, stor: false))
                    }
                }
            }
        }
    }
}

/// Trumf- og makkervalg når mennesket vant budrunden.
struct TrumfvalgView: View {
    @ObservedObject var vm: GameViewModel
    @State private var valgtTrumf: Suit = .spar

    var body: some View {
        PapirPanel {
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
                        ForEach(vm.engine.kortSomKanØnskes(trumf: valgtTrumf)) { kort in
                            Button {
                                vm.menneskeVelgerTrumf(suit: valgtTrumf, ønsket: kort)
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
}
