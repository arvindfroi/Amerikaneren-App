import SwiftUI

/// Et spillkort i Brain Training-aktig strek: hvitt, runde hjørner, tydelig blekk.
struct CardView: View {
    let kort: Card
    var bredde: CGFloat = 64
    var valgbar: Bool = false
    var dimmet: Bool = false

    var body: some View {
        VStack {
            HStack {
                VStack(spacing: -2) {
                    Text(kort.rank.symbol)
                        .font(.system(size: bredde * 0.28, weight: .heavy, design: .rounded))
                    Text(kort.suit.rawValue)
                        .font(.system(size: bredde * 0.26))
                }
                Spacer()
            }
            Spacer()
            Text(kort.suit.rawValue)
                .font(.system(size: bredde * 0.44))
            Spacer()
        }
        .padding(bredde * 0.1)
        .foregroundStyle(kort.suit.erRød ? Theme.rød : Theme.blekk)
        .frame(width: bredde, height: bredde * 1.45)
        .background(
            RoundedRectangle(cornerRadius: bredde * 0.13, style: .continuous)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: bredde * 0.13, style: .continuous)
                        .strokeBorder(valgbar ? Theme.grønn : Theme.linje, lineWidth: valgbar ? 3 : 1.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        )
        .opacity(dimmet ? 0.45 : 1)
    }
}

/// Baksiden av et kort (skjulte CPU-hender).
struct CardBackView: View {
    var bredde: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: bredde * 0.13, style: .continuous)
            .fill(Theme.blå)
            .overlay(
                RoundedRectangle(cornerRadius: bredde * 0.13, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 2)
                    .padding(3)
            )
            .overlay(Text("★").font(.system(size: bredde * 0.4)).foregroundStyle(.white.opacity(0.8)))
            .frame(width: bredde, height: bredde * 1.45)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}
