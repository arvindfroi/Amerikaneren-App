import SwiftUI

/// Grundig, skippbar tutorial med eksempelkort – Benjamin Franklin forklarer
/// steg for steg, i Brain Training-ånd.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var steg = 0

    private let antallSteg = 6

    var body: some View {
        ZStack {
            Theme.papir.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Leksjon \(steg + 1) av \(antallSteg)")
                        .font(Theme.kroppFont(14))
                        .foregroundStyle(Theme.blekkSvak)
                    Spacer()
                    Button("Lukk") { dismiss() }
                        .font(Theme.kroppFont(15).weight(.semibold))
                        .foregroundStyle(Theme.rød)
                }
                .padding()

                TabView(selection: $steg) {
                    leksjon1.tag(0)
                    leksjon2.tag(1)
                    leksjon3.tag(2)
                    leksjon4.tag(3)
                    leksjon5.tag(4)
                    leksjon6.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                HStack(spacing: 12) {
                    if steg > 0 {
                        Button("Tilbake") { withAnimation { steg -= 1 } }
                            .buttonStyle(BTButtonStyle(farge: Theme.blekkSvak.opacity(0.85)))
                    }
                    Button(steg == antallSteg - 1 ? "Ferdig!" : "Neste") {
                        if steg == antallSteg - 1 { dismiss() } else { withAnimation { steg += 1 } }
                    }
                    .buttonStyle(BTButtonStyle(farge: Theme.rød))
                }
                .padding(20)
            }
        }
    }

    private func leksjon<Innhold: View>(_ tekst: String, @ViewBuilder innhold: () -> Innhold) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    MaskotView(størrelse: 56)
                    SnakkeBoble(tekst: tekst)
                }
                innhold()
            }
            .padding(20)
        }
    }

    private var leksjon1: some View {
        leksjon("Amerikaner spilles med hele kortstokken. Med fire spillere får alle 13 kort. Ess er høyest, to er lavest.") {
            PapirPanel {
                VStack(spacing: 12) {
                    Text("Kortenes rangering").font(Theme.kroppFont(16).weight(.bold)).foregroundStyle(Theme.blekk)
                    HStack(spacing: 6) {
                        MiniKort(kort: Card(suit: .spar, rank: .ace), fremhevet: true)
                        MiniKort(kort: Card(suit: .spar, rank: .king))
                        MiniKort(kort: Card(suit: .spar, rank: .queen))
                        MiniKort(kort: Card(suit: .spar, rank: .jack))
                        Text("…").foregroundStyle(Theme.blekkSvak)
                        MiniKort(kort: Card(suit: .spar, rank: .three))
                        MiniKort(kort: Card(suit: .spar, rank: .two))
                    }
                    Text("Sterkest → svakest").font(Theme.kroppFont(12)).foregroundStyle(Theme.blekkSvak)
                }
            }
        }
    }

    private var leksjon2: some View {
        leksjon("Budrunden! Se på hånden din og gjett hvor mange stikk du og en makker kan ta sammen. Minste bud er 5. Du kan alltid passe.") {
            PapirPanel {
                VStack(alignment: .leading, spacing: 10) {
                    budEksempel(navn: "George", bud: "6 stikk")
                    budEksempel(navn: "Du", bud: "7 stikk")
                    budEksempel(navn: "Teddy", bud: "Pass")
                    budEksempel(navn: "Abraham", bud: "8 stikk")
                    Text("Abraham vant budrunden med 8.")
                        .font(Theme.kroppFont(13)).foregroundStyle(Theme.blekkSvak)
                }
            }
        }
    }

    private var leksjon3: some View {
        leksjon("Budvinneren velger trumf og ber om ett kort – ofte det høyeste trumfkortet de mangler. Den som har kortet er hemmelig makker!") {
            PapirPanel {
                VStack(spacing: 12) {
                    Text("«Hjerter er trumf. Jeg vil ha hjerter ess!»")
                        .font(Theme.kroppFont(16).weight(.semibold)).foregroundStyle(Theme.blekk)
                    MiniKort(kort: Card(suit: .hjerter, rank: .ace), fremhevet: true, størrelse: 72)
                    Text("Den som sitter med hjerter ess er nå på lag med budvinneren – men ingen andre vet hvem det er før kortet dukker opp på bordet!")
                        .font(Theme.kroppFont(14)).foregroundStyle(Theme.blekkSvak)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var leksjon4: some View {
        leksjon("Stikkspillet: du MÅ følge fargen som spilles ut hvis du kan. Har du ikke fargen, kan du trumfe eller kaste. Høyeste trumf vinner – ellers høyeste kort i utspillsfargen.") {
            PapirPanel {
                VStack(spacing: 12) {
                    Text("Hjerter er trumf. Kløver spilles ut:")
                        .font(Theme.kroppFont(14)).foregroundStyle(Theme.blekkSvak)
                    HStack(spacing: 10) {
                        MiniKort(kort: Card(suit: .kløver, rank: .king), størrelse: 60)
                        MiniKort(kort: Card(suit: .kløver, rank: .ace), størrelse: 60)
                        MiniKort(kort: Card(suit: .hjerter, rank: .two), fremhevet: true, størrelse: 60)
                        MiniKort(kort: Card(suit: .ruter, rank: .ace), størrelse: 60)
                    }
                    Text("Hjerter 2 vinner stikket – liten trumf slår store kort!")
                        .font(Theme.kroppFont(14).weight(.semibold)).foregroundStyle(Theme.rød)
                }
            }
        }
    }

    private var leksjon5: some View {
        leksjon("Poeng: Klarer budlaget budet, får BEGGE så mange poeng som budet. Feiler de, MISTER begge like mange. Alle andre får ett poeng per stikk de tar selv.") {
            PapirPanel {
                VStack(alignment: .leading, spacing: 8) {
                    poengRad("Abraham (bud 8, laget tok 9)", "+8", Theme.grønn)
                    poengRad("Makkeren hans", "+8", Theme.grønn)
                    poengRad("Du (tok 3 stikk)", "+3", Theme.blekk)
                    poengRad("Teddy (tok 1 stikk)", "+1", Theme.blekk)
                    Divider()
                    Text("Hadde laget bare tatt 7 stikk, hadde begge fått −8.")
                        .font(Theme.kroppFont(13)).foregroundStyle(Theme.blekkSvak)
                }
            }
        }
    }

    private var leksjon6: some View {
        leksjon("Til slutt: meldingen «AMERIKANER!» betyr at du tar alle 13 stikkene helt alene – uten trumf og uten makker. Klarer du det, får du 52 poeng og vinner på flekken. Feiler du… −52. Lykke til!") {
            PapirPanel {
                VStack(spacing: 10) {
                    Text("🇺🇸").font(.system(size: 64))
                    Text("Førstemann til 52 poeng vinner spillet!")
                        .font(Theme.kroppFont(17).weight(.bold)).foregroundStyle(Theme.blekk)
                    Text("Ved lik poengsum vinner budlaget fra siste runde.")
                        .font(Theme.kroppFont(13)).foregroundStyle(Theme.blekkSvak)
                }
            }
        }
    }

    private func budEksempel(navn: String, bud: String) -> some View {
        HStack {
            Text(navn).font(Theme.kroppFont(15)).foregroundStyle(Theme.blekk)
            Spacer()
            Text(bud)
                .font(Theme.kroppFont(15).weight(.bold))
                .foregroundStyle(bud == "Pass" ? Theme.blekkSvak : Theme.rød)
        }
    }

    private func poengRad(_ tekst: String, _ poeng: String, _ farge: Color) -> some View {
        HStack {
            Text(tekst).font(Theme.kroppFont(14)).foregroundStyle(Theme.blekk)
            Spacer()
            Text(poeng).font(Theme.kroppFont(15).weight(.bold)).foregroundStyle(farge)
        }
    }
}

/// Lite eksempelkort brukt i tutorial.
struct MiniKort: View {
    let kort: Card
    var fremhevet: Bool = false
    var størrelse: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            Text(kort.rank.symbol)
                .font(.system(size: størrelse * 0.34, weight: .bold, design: .rounded))
            Text(kort.suit.rawValue)
                .font(.system(size: størrelse * 0.32))
        }
        .foregroundStyle(kort.suit.erRød ? Theme.rød : Theme.blekk)
        .frame(width: størrelse, height: størrelse * 1.4)
        .background(
            RoundedRectangle(cornerRadius: størrelse * 0.14, style: .continuous)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: størrelse * 0.14, style: .continuous)
                        .strokeBorder(fremhevet ? Theme.rød : Theme.linje, lineWidth: fremhevet ? 3 : 1.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 2, y: 2)
        )
    }
}
