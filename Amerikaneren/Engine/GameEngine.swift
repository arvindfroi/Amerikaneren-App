import Foundation

/// Regeloppsett for et parti. Standard er 4 spillere, byttekort-varianten
/// (kortregler.no) og først til 100 poeng.
struct GameRules: Codable, Hashable {
    var antallSpillere: Int = 4
    var målPoeng: Int = 100
    var minsteBud: Int = 5
    /// Byttekort-varianten: fire kort legges i en talong som budvinneren
    /// tar opp – og bytter ut fire valgfrie kort mot, skjult for de andre.
    var medByttekort: Bool = true
    /// Alternativt partiformat: spill nøyaktig så mange runder og kår
    /// vinneren på høyest sluttsum (nil = først til målPoeng vinner).
    /// målPoeng styrer fortsatt Amerikaner-satsene.
    var maksRunder: Int?

    /// Husregel med 4 spillere: 12 kort hver og 4 byttekort. Andre
    /// spillertall (companion-modus) får resten av stokken som byttekort:
    /// 3 sp: 17 kort/1 byttekort, 5 sp: 10/2, 6 sp: 8/4. Uten
    /// byttekort-varianten deles hele stokken (13 hver med 4 spillere).
    var kortPerSpiller: Int {
        if antallSpillere == 4 { return medByttekort ? 12 : 13 }
        return 52 / antallSpillere
    }
    var antallByttekort: Int { 52 - antallSpillere * kortPerSpiller }
    var maksBud: Int { kortPerSpiller }

    // Poengsatser (husreglene): budgiveren får alltid dobbelt av makkeren.
    /// Tallbud n gir ±n·budgiverFaktor til budgiver og ±n til makker.
    var budgiverFaktor: Int { 2 }
    /// Amerikaner (alle stikk med makker): budgiver ±dette, makker halvparten.
    var amerikanerPoeng: Int { målPoeng / 2 }
    /// Solo-amerikaner (alle stikk helt alene): ±dette, ingen makker.
    var soloAmerikanerPoeng: Int { målPoeng }
}

/// Fasene i en runde. String/Codable slik at online-protokollen kan
/// sende fasen direkte.
enum GamePhase: String, Codable, Equatable {
    case venterPåStart
    case budrunde
    case byttekort        // budvinner har tatt opp talongen og velger vrak
    case velgTrumf        // budvinner velger trumf og ber om et kort (makker)
    case spill            // stikkspill
    case rundeFerdig
    case spillFerdig
}

struct TrickPlay: Hashable, Identifiable, Codable {
    let seat: Int
    let card: Card
    var id: String { "\(seat)-\(card.id)" }
}

/// Resultatet av en ferdigspilt runde, brukt til poeng og statistikk.
struct RoundResult: Codable, Hashable {
    var budgiver: Int
    var makker: Int?          // nil ved Amerikaner-melding
    var bud: BidAction
    var trumf: Suit?          // nil ved Amerikaner-melding
    var stikkPerSpiller: [Int]
    var klarte: Bool
    var poengEndring: [Int]
}

/// Selve spillmotoren for Amerikaner. Ren tilstandsmaskin uten UI-avhengigheter.
final class GameEngine {
    let rules: GameRules

    private(set) var phase: GamePhase = .venterPåStart
    private(set) var hands: [[Card]] = []
    private(set) var scores: [Int]
    private(set) var dealer: Int = 0

    // Budrunde
    private(set) var bids: [PlacedBid] = []
    private(set) var aktivBudgiver: Int = 0
    private(set) var harPasset: Set<Int> = []
    private(set) var høyesteBud: PlacedBid?

    // Byttekort (talong)
    private(set) var talon: [Card] = []        // skjult til budvinneren tar dem opp
    private(set) var kastet: [Card] = []       // vraket – kjent kun for budvinneren

    // Trumf og makker
    private(set) var trumf: Suit?
    private(set) var ønsketKort: Card?
    private(set) var ønsketLagt: Bool = false  // det etterlyste kortet er spilt
    private(set) var makkerSeat: Int?          // kjent for motoren, skjult i UI
    private(set) var makkerAvslørt: Bool = false
    /// Amerikaner-melding: laget (budvinner + makker) må ta alle stikkene.
    /// Spilles med trumf og hemmelig makker som vanlig.
    private(set) var erAmerikaner: Bool = false
    /// Solo-amerikaner: budvinneren må ta alle stikkene helt alene. Fortsatt
    /// trumf, og et kort kan etterlyses i første stikk – men ingen makker.
    private(set) var erSolo: Bool = false

    // Stikkspill
    private(set) var currentTrick: [TrickPlay] = []
    private(set) var aktivSpiller: Int = 0
    private(set) var stikkTatt: [Int]
    private(set) var trickNummer: Int = 0
    private(set) var spilteKort: [Card] = []
    private(set) var sisteStikk: [TrickPlay] = []
    private(set) var sisteStikkVinner: Int?

    private(set) var rundeResultater: [RoundResult] = []
    private(set) var sisteRunde: RoundResult?

    // Opptak: den utdelte starttilstanden beholdes gjennom runden, slik at
    // en ferdigspilt runde kan lagres og spilles av på nytt (treningsdata).
    private(set) var utdelteHender: [[Card]] = []
    private(set) var utdeltTalon: [Card] = []
    private(set) var førsteBudgiverIRunden: Int = 0

    init(rules: GameRules = GameRules()) {
        self.rules = rules
        self.scores = Array(repeating: 0, count: rules.antallSpillere)
        self.stikkTatt = Array(repeating: 0, count: rules.antallSpillere)
    }

    var budgiverSeat: Int? { høyesteBud?.seat }

    // MARK: - Runde-oppsett

    func startRunde(seed: UInt64? = nil) {
        let stokk = Deck.stokket(seed: seed)
        let n = rules.antallSpillere
        let iSpill = stokk.count - rules.antallByttekort
        let hender = (0..<n).map { s in
            stride(from: s, to: iSpill, by: n).map { stokk[$0] }.sortertForHånd()
        }
        startRunde(hender: hender, talon: Array(stokk.suffix(rules.antallByttekort)),
                   førsteBudgiver: (dealer + 1) % n)
    }

    /// Setter poengstillingen direkte – for trening/simulering som skal
    /// dekke hele spekteret av partisituasjoner (desperasjon, trygghet,
    /// målstrek) uten å spille seg dit. Kun mellom runder.
    func settPoengstilling(_ poeng: [Int]) {
        precondition(phase == .venterPåStart || phase == .rundeFerdig)
        precondition(poeng.count == rules.antallSpillere)
        precondition(poeng.allSatisfy { $0 < rules.målPoeng })
        scores = poeng
    }

    /// Starter en runde med en forhåndsbestemt utdeling – brukes av tester
    /// og av avspilling av opptak (`Rundeopptak.spillAv`).
    func startRunde(hender: [[Card]], talon nyTalon: [Card], førsteBudgiver: Int) {
        precondition(phase == .venterPåStart || phase == .rundeFerdig)
        precondition(hender.count == rules.antallSpillere)
        precondition(hender.allSatisfy { $0.count == rules.kortPerSpiller })
        precondition(nyTalon.count == rules.antallByttekort)
        let n = rules.antallSpillere
        hands = hender
        talon = nyTalon
        utdelteHender = hender
        utdeltTalon = nyTalon
        førsteBudgiverIRunden = førsteBudgiver
        kastet = []
        bids = []
        harPasset = []
        høyesteBud = nil
        trumf = nil
        ønsketKort = nil
        ønsketLagt = false
        makkerSeat = nil
        makkerAvslørt = false
        erAmerikaner = false
        erSolo = false
        currentTrick = []
        sisteStikk = []
        sisteStikkVinner = nil
        stikkTatt = Array(repeating: 0, count: n)
        trickNummer = 0
        spilteKort = []
        aktivBudgiver = førsteBudgiver
        phase = .budrunde
    }

    // MARK: - Budrunde

    /// Lovlige bud for setet som er i tur. Tallbud må overby hverandre,
    /// Amerikaner slår alle tallbud, og solo-amerikaner slår alt.
    func lovligeBud(for seat: Int) -> [BidAction] {
        guard phase == .budrunde, seat == aktivBudgiver, !harPasset.contains(seat) else { return [] }
        var handlinger: [BidAction] = [.pass]
        let høyesteRang = høyesteBud?.action.rang ?? -1
        let gulv = max(rules.minsteBud, høyesteRang + 1)
        if gulv <= rules.maksBud {
            handlinger += (gulv...rules.maksBud).map { BidAction.bud($0) }
        }
        if høyesteRang < BidAction.amerikaner.rang {
            handlinger.append(.amerikaner)
        }
        if høyesteRang < BidAction.soloAmerikaner.rang {
            handlinger.append(.soloAmerikaner)
        }
        return handlinger
    }

    @discardableResult
    func giBud(seat: Int, action: BidAction) -> Bool {
        guard lovligeBud(for: seat).contains(action) else { return false }
        bids.append(PlacedBid(seat: seat, action: action))
        if action == .pass {
            harPasset.insert(seat)
        } else {
            høyesteBud = PlacedBid(seat: seat, action: action)
        }
        avansérBudrunde()
        return true
    }

    private func avansérBudrunde() {
        let n = rules.antallSpillere
        let aktive = (0..<n).filter { !harPasset.contains($0) }

        // Alle passet: del ut på nytt.
        if aktive.isEmpty {
            phase = .venterPåStart
            dealer = (dealer + 1) % n
            startRunde()
            return
        }
        // Én igjen med høyeste bud: budrunden er over.
        if aktive.count == 1, let vinner = høyesteBud, aktive[0] == vinner.seat {
            avsluttBudrunde(vinner: vinner)
            return
        }
        // Solo-amerikaner kan ikke overbys – avslutt med en gang.
        // (Vanlig Amerikaner kan fortsatt overbys av solo.)
        if let vinner = høyesteBud, vinner.action == .soloAmerikaner {
            avsluttBudrunde(vinner: vinner)
            return
        }
        var neste = (aktivBudgiver + 1) % n
        while harPasset.contains(neste) { neste = (neste + 1) % n }
        aktivBudgiver = neste
    }

    /// Budrunden er avgjort: budvinneren tar eventuelt opp talongen og skal
    /// vrake, og deretter velges trumf – også ved Amerikaner-meldingene.
    private func avsluttBudrunde(vinner: PlacedBid) {
        aktivBudgiver = vinner.seat
        aktivSpiller = vinner.seat
        erAmerikaner = vinner.action == .amerikaner
        erSolo = vinner.action == .soloAmerikaner
        if rules.medByttekort {
            hands[vinner.seat] = (hands[vinner.seat] + talon).sortertForHånd()
            phase = .byttekort
        } else {
            phase = .velgTrumf
        }
    }

    // MARK: - Byttekort

    /// Budvinneren vraker like mange kort som talongen ga. Vrakede kort er
    /// ute av runden og forblir skjult for de andre spillerne.
    @discardableResult
    func kastByttekort(_ kort: [Card], seat: Int) -> Bool {
        guard phase == .byttekort, seat == budgiverSeat,
              kort.count == rules.antallByttekort,
              Set(kort).count == kort.count,
              kort.allSatisfy({ hands[seat].contains($0) }) else { return false }
        hands[seat].removeAll { kort.contains($0) }
        kastet = kort
        aktivSpiller = seat
        phase = .velgTrumf
        return true
    }

    // MARK: - Trumf og makker

    /// Kort budvinneren kan be om: trumfkort de verken har selv eller har
    /// vraket – det er ikke lov å etterlyse et dødt kort, så det etterlyste
    /// kortet sitter garantert hos en motspiller.
    func kortSomKanØnskes(trumf: Suit) -> [Card] {
        guard let budgiver = budgiverSeat else { return [] }
        let utilgjengelige = Set((hands[budgiver] + kastet).filter { $0.suit == trumf })
        return Rank.allCases.reversed()
            .map { Card(suit: trumf, rank: $0) }
            .filter { !utilgjengelige.contains($0) }
    }

    /// Budvinneren velger trumf og etterlyser et kort. Ved tallbud og
    /// Amerikaner er etterlysningen obligatorisk (den peker ut makkeren);
    /// ved solo-amerikaner er den valgfri og gir ingen makker – bare
    /// plikten til å legge kortet i første stikk.
    @discardableResult
    func velgTrumf(suit: Suit, ønsket: Card?) -> Bool {
        guard phase == .velgTrumf, let budgiver = budgiverSeat else { return false }
        if let ønsket {
            guard ønsket.suit == suit, kortSomKanØnskes(trumf: suit).contains(ønsket) else { return false }
        } else {
            guard erSolo else { return false }
        }
        trumf = suit
        ønsketKort = ønsket
        makkerSeat = erSolo ? nil : ønsket.flatMap { ø in hands.firstIndex { $0.contains(ø) } }
        if makkerSeat == budgiver { makkerSeat = nil }
        aktivSpiller = budgiver
        phase = .spill
        return true
    }

    // MARK: - Stikkspill

    /// Lovlige kort for setet som er i tur. Følg farge om mulig.
    /// I første stikk gjelder to plikter: budvinneren MÅ spille ut i
    /// trumffargen (utspillet «viser» trumfen, og etterlysningen er alltid
    /// i den fargen), og den som sitter med det ønskede kortet MÅ spille
    /// det første gang vedkommende lovlig kan.
    func lovligeKort(for seat: Int) -> [Card] {
        guard phase == .spill, seat == aktivSpiller else { return [] }
        let hånd = hands[seat]
        var lovlige: [Card]
        if let ledet = currentTrick.first?.card.suit {
            let samme = hånd.filter { $0.suit == ledet }
            lovlige = samme.isEmpty ? hånd : samme
        } else {
            lovlige = hånd
            // Utspillsplikt: budvinneren åpner første stikk i trumf, slik at
            // det etterlyste kortet tvinges fram med en gang og makkeren
            // avsløres i første stikk. Uten trumf på hånden spilles fritt.
            if trickNummer == 0, seat == budgiverSeat, let trumf {
                let trumfKort = hånd.filter { $0.suit == trumf }
                if !trumfKort.isEmpty { lovlige = trumfKort }
            }
        }
        // Makkerplikt: ønsket kort må legges i første stikk hvis det er lovlig.
        if trickNummer == 0, let ønsket = ønsketKort,
           seat != budgiverSeat, lovlige.contains(ønsket) {
            return [ønsket]
        }
        return lovlige
    }

    @discardableResult
    func spill(kort: Card, seat: Int) -> Bool {
        guard lovligeKort(for: seat).contains(kort) else { return false }
        hands[seat].removeAll { $0 == kort }
        currentTrick.append(TrickPlay(seat: seat, card: kort))
        spilteKort.append(kort)
        if kort == ønsketKort {
            ønsketLagt = true
            if makkerSeat != nil { makkerAvslørt = true }
        }

        if currentTrick.count == rules.antallSpillere {
            fullførStikk()
        } else {
            aktivSpiller = (aktivSpiller + 1) % rules.antallSpillere
        }
        return true
    }

    static func vinnerAvStikk(_ stikk: [TrickPlay], trumf: Suit?) -> Int {
        guard let første = stikk.first else { return 0 }
        var beste = første
        for spill in stikk.dropFirst() {
            let kort = spill.card
            if let trumf {
                let besteErTrumf = beste.card.suit == trumf
                let denneErTrumf = kort.suit == trumf
                if denneErTrumf && !besteErTrumf {
                    beste = spill
                    continue
                }
                if denneErTrumf == besteErTrumf,
                   kort.suit == beste.card.suit,
                   kort.rank > beste.card.rank {
                    beste = spill
                }
            } else if kort.suit == beste.card.suit, kort.rank > beste.card.rank {
                beste = spill
            }
        }
        return beste.seat
    }

    private func fullførStikk() {
        let vinner = Self.vinnerAvStikk(currentTrick, trumf: trumf)
        stikkTatt[vinner] += 1
        sisteStikk = currentTrick
        sisteStikkVinner = vinner
        currentTrick = []
        trickNummer += 1
        aktivSpiller = vinner

        if trickNummer == rules.kortPerSpiller {
            avsluttRunde()
        }
        // En tapt (solo-)amerikaner spilles likevel ferdig – stikkene gir
        // poeng til de andre spillerne.
    }

    // MARK: - Poeng

    /// Poengregler: budvinneren får alltid dobbelt av makkeren.
    /// Tallbud n: ±2n til budvinner, ±n til makker. Amerikaner (alle stikk
    /// med laget): ±målPoeng/2 og ±målPoeng/4. Solo-amerikaner (alle stikk
    /// alene): ±målPoeng. Øvrige spillere får +1 per eget stikk.
    private func avsluttRunde() {
        guard let budgiver = budgiverSeat, let bud = høyesteBud?.action else { return }
        let n = rules.antallSpillere
        var endring = Array(repeating: 0, count: n)
        let klarte: Bool

        let lag = erSolo ? [budgiver] : [budgiver, makkerSeat].compactMap { $0 }
        let lagStikk = lag.reduce(0) { $0 + stikkTatt[$1] }

        let budgiverPoeng: Int
        let makkerPoeng: Int
        switch bud {
        case .soloAmerikaner:
            klarte = stikkTatt[budgiver] == rules.kortPerSpiller
            budgiverPoeng = rules.soloAmerikanerPoeng
            makkerPoeng = 0
        case .amerikaner:
            klarte = lagStikk == rules.kortPerSpiller
            budgiverPoeng = rules.amerikanerPoeng
            makkerPoeng = rules.amerikanerPoeng / 2
        case .bud(let mål):
            klarte = lagStikk >= mål
            budgiverPoeng = mål * rules.budgiverFaktor
            makkerPoeng = mål
        case .pass:
            klarte = false
            budgiverPoeng = 0
            makkerPoeng = 0
        }

        for s in 0..<n {
            if s == budgiver {
                endring[s] = klarte ? budgiverPoeng : -budgiverPoeng
            } else if lag.contains(s) {
                endring[s] = klarte ? makkerPoeng : -makkerPoeng
            } else {
                endring[s] = stikkTatt[s]
            }
        }

        for s in 0..<n { scores[s] += endring[s] }

        let resultat = RoundResult(
            budgiver: budgiver,
            makker: makkerSeat,
            bud: bud,
            trumf: trumf,
            stikkPerSpiller: stikkTatt,
            klarte: klarte,
            poengEndring: endring
        )
        rundeResultater.append(resultat)
        sisteRunde = resultat

        let ferdig: Bool
        if let maksRunder = rules.maksRunder {
            ferdig = rundeResultater.count >= maksRunder
        } else {
            ferdig = scores.contains { $0 >= rules.målPoeng }
        }
        if ferdig {
            phase = .spillFerdig
        } else {
            phase = .rundeFerdig
            dealer = (dealer + 1) % n
        }
    }

    /// Vinneren når spillet er ferdig. Ved lik poengsum vinner budgiversiden
    /// fra siste runde, ellers høyest poengsum.
    var vinnerSeat: Int? {
        guard phase == .spillFerdig else { return nil }
        let maks = scores.max() ?? 0
        let kandidater = (0..<rules.antallSpillere).filter { scores[$0] == maks }
        if kandidater.count > 1, let siste = sisteRunde {
            let lag = [siste.budgiver, siste.makker].compactMap { $0 }
            if let prioritert = kandidater.first(where: { lag.contains($0) }) {
                return prioritert
            }
        }
        return kandidater.first
    }

    func nesteRunde() {
        guard phase == .rundeFerdig else { return }
        phase = .venterPåStart
        startRunde()
    }
}
