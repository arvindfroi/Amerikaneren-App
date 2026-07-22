import Foundation

/// Heuristisk AI-spiller. Vurderer hånden for bud, velger trumf/makkerkort
/// og spiller stikk med enkel kortteling. Personlighet og vanskelighetsgrad
/// justerer beslutningene. På President-nivå overtar søkeboten `MesterAI`;
/// heuristikken under fungerer da som sikkerhetsnett.
struct AIPlayer {
    let seat: Int
    let difficulty: AIDifficulty
    let personality: AIPersonality
    private let mester: MesterAI?
    private let nevro: NevroSpiller?

    init(seat: Int, difficulty: AIDifficulty, personality: AIPersonality) {
        self.seat = seat
        self.difficulty = difficulty
        self.personality = personality
        self.mester = difficulty.spillerPerfekt
            ? MesterAI(sete: seat, konfig: MesterAI.overstyrKonfig ?? .automatisk())
            : nil
        self.nevro = difficulty.spillerPerfekt
            ? NevroHjerne.delt.map { NevroSpiller(sete: seat, hjerne: $0) }
            : nil
    }

    // MARK: - Håndvurdering

    /// Estimerer antall stikk med gitt farge som trumf. Vektene kan byttes
    /// ut per kall (evolusjonssøket); standard er de håndsatte verdiene.
    static func estimerStikk(hånd: [Card], trumf: Suit,
                             vekter v: MesterVekter = MesterVekter()) -> Double {
        var estimat = 0.0
        let trumfKort = hånd.filter { $0.suit == trumf }
        // Trumflengde er konge: hvert trumfkort over 3 er nesten et stikk.
        estimat += Double(trumfKort.count) * v.trumfPerKort
        if trumfKort.count > 3 { estimat += Double(trumfKort.count - 3) * v.trumfLengdeBonus }

        for kort in hånd {
            let iFarge = hånd.filter { $0.suit == kort.suit }.count
            switch kort.rank {
            case .ace: estimat += kort.suit == trumf ? v.essTrumf : v.essSide
            case .king: estimat += iFarge >= 2 ? v.kongeStøttet : v.kongeSingel
            case .queen: estimat += iFarge >= 3 ? v.dameStøttet : v.dameSingel
            default: break
            }
        }
        // Renons og singelton gir stjålne stikk med trumf på hånden.
        for suit in Suit.allCases where suit != trumf {
            let antall = hånd.filter { $0.suit == suit }.count
            if antall == 0 { estimat += min(2.0, Double(trumfKort.count)) * v.renonsFaktor }
            if antall == 1 { estimat += v.singeltonBonus }
        }
        return estimat
    }

    static func besteTrumf(hånd: [Card],
                           vekter: MesterVekter = MesterVekter()) -> (suit: Suit, estimat: Double) {
        var beste: (Suit, Double) = (.spar, -1)
        for suit in Suit.allCases {
            let e = estimerStikk(hånd: hånd, trumf: suit, vekter: vekter)
            if e > beste.1 { beste = (suit, e) }
        }
        return beste
    }

    // MARK: - Budgivning

    func velgBud(engine: GameEngine) -> BidAction {
        let lovlige = engine.lovligeBud(for: seat)
        guard !lovlige.isEmpty else { return .pass }
        if let mester {
            let bud = mester.velgBud(engine: engine)
            if lovlige.contains(bud) { return bud }
        }
        if let nevro {
            let bud = nevro.velgBud(engine: engine)
            if lovlige.contains(bud) { return bud }
        }
        let hånd = engine.hands[seat]
        let (_, råEstimat) = Self.besteTrumf(hånd: hånd)

        // Makkeren bidrar typisk med noen stikk.
        var estimat = råEstimat + 2.0
        if !difficulty.spillerPerfekt {
            // Personligheten farger budet – på President-nivå bys det rent.
            estimat += (personality.aggresjon - 0.5) * 2.5
            estimat += Double.random(in: -difficulty.budStøy...difficulty.budStøy)
        }

        // Amerikaner: laget må ta ALLE stikkene (med trumf og makker).
        // Solo-amerikaner: alle stikkene helt alene – ekstremt sjelden.
        let alleStikk = Double(engine.rules.maksBud)
        let solostikk = Self.estimerStikk(hånd: hånd, trumf: Self.besteTrumf(hånd: hånd).suit)
        if lovlige.contains(.soloAmerikaner), solostikk >= alleStikk + 0.5 {
            return .soloAmerikaner
        }
        if lovlige.contains(.amerikaner) {
            if difficulty.spillerPerfekt {
                // Perfekt spiller melder bare når laget faktisk bærer det.
                if solostikk + 2.0 >= alleStikk + 1.0 { return .amerikaner }
            } else if solostikk + 2.0 >= alleStikk,
                      Double.random(in: 0...1) < personality.storhetsdrøm {
                return .amerikaner
            }
        }

        let mittBud = Int(estimat.rounded())
        let tallbud = lovlige.compactMap { action -> Int? in
            if case .bud(let n) = action { return n }
            return nil
        }
        // Man bløffer sjelden i Amerikaner: bare de frekkeste presser
        // budet ett hakk over dekning, og bare unntaksvis.
        let bløffer = !difficulty.spillerPerfekt
            && Double.random(in: 0...1) < personality.bløff * 0.15
        let grense = bløffer ? mittBud + 1 : mittBud
        if let laveste = tallbud.min(), laveste <= grense {
            return .bud(laveste)
        }
        return .pass
    }

    /// Byttekort: hvilke kort vrakes når budvinneren har tatt opp talongen.
    /// Heuristikken beholder trumf, ess og lange farger – og kaster lave
    /// kort fra korte sidefarger (skaper renons for stjeling).
    func velgByttekort(engine: GameEngine) -> [Card] {
        let hånd = engine.hands[seat]
        let antall = engine.rules.antallByttekort
        if let mester {
            let valg = mester.velgByttekort(engine: engine)
            if valg.count == antall, valg.allSatisfy({ hånd.contains($0) }) {
                return valg
            }
        }
        if let nevro {
            let valg = nevro.velgByttekort(engine: engine)
            if valg.count == antall, valg.allSatisfy({ hånd.contains($0) }) {
                return valg
            }
        }
        let (trumf, _) = Self.besteTrumf(hånd: hånd)
        func beholdVerdi(_ kort: Card) -> Int {
            let lengde = hånd.filter { $0.suit == kort.suit }.count
            return (kort.suit == trumf ? 1000 : 0)
                + (kort.rank == .ace ? 500 : 0)
                + kort.rank.rawValue
                + lengde * 3
        }
        return Array(hånd.sorted { beholdVerdi($0) < beholdVerdi($1) }.prefix(antall))
    }

    /// Trumf- og etterlysningsvalg. Ved tallbud og Amerikaner er kortet
    /// makkeren; ved solo-amerikaner er etterlysningen valgfri (nil = ingen)
    /// og brukes bare til å tvinge fram en trumf man selv kan stikke over.
    func velgTrumfOgMakker(engine: GameEngine) -> (Suit, Card?)? {
        if let mester, let valg = mester.velgTrumfOgMakker(engine: engine),
           valg.1 == nil || engine.kortSomKanØnskes(trumf: valg.0).contains(valg.1!) {
            return valg
        }
        let hånd = engine.hands[seat]
        let (suit, _) = Self.besteTrumf(hånd: hånd)
        if engine.erSolo {
            // Etterlys bare et trumfkort vi kan slå med vårt eget toppkort.
            let minTopp = hånd.filter { $0.suit == suit }.map(\.rank).max()
            let uttrekk = engine.kortSomKanØnskes(trumf: suit).first { kort in
                minTopp.map { kort.rank < $0 } ?? false
            }
            return (suit, uttrekk)
        }
        let kandidater = engine.kortSomKanØnskes(trumf: suit)
        // Be om høyeste trumf man ikke har selv – da får laget beste kort.
        guard let ønsket = kandidater.first else {
            // Har alle tilgjengelige trumfene: prøv nest beste farge.
            for annen in Suit.allCases where annen != suit {
                if let alternativ = engine.kortSomKanØnskes(trumf: annen).first {
                    return (annen, alternativ)
                }
            }
            return nil
        }
        return (suit, ønsket)
    }

    // MARK: - Kortspill

    func velgKort(engine: GameEngine) -> Card? {
        let lovlige = engine.lovligeKort(for: seat)
        guard !lovlige.isEmpty else { return nil }
        if lovlige.count == 1 { return lovlige[0] }
        if let mester, let kort = mester.velgKort(engine: engine), lovlige.contains(kort) {
            return kort
        }
        if let nevro, let kort = nevro.velgKort(engine: engine), lovlige.contains(kort) {
            return kort
        }
        if Double.random(in: 0...1) < difficulty.feilspillSjanse {
            return lovlige.randomElement()
        }

        let trumf = engine.trumf
        let stikk = engine.currentTrick

        if stikk.isEmpty {
            return velgUtspill(engine: engine, lovlige: lovlige)
        }

        let vinnerNå = GameEngine.vinnerAvStikk(stikk, trumf: trumf)
        let makkerVinner = erPåMittLag(vinnerNå, engine: engine)

        let vinnende = lovlige.filter { kort in
            GameEngine.vinnerAvStikk(stikk + [TrickPlay(seat: seat, card: kort)], trumf: trumf) == seat
        }

        // Makkeren har stikket: legg lavest. Bare illojale spillere (og
        // aldri en perfekt spiller som er sistemann) overstyrer dette.
        let lojal = difficulty.spillerPerfekt || personality.lojalitet > 0.35
        if makkerVinner, stikk.count == engine.rules.antallSpillere - 1 || lojal {
            return lavest(lovlige, trumf: trumf)
        }

        if let billigsteVinner = vinnende.min(by: { kortStyrke($0, trumf: trumf) < kortStyrke($1, trumf: trumf) }) {
            // Risikovillige sparer storkortene tidlig – perfekte spillere
            // tar alltid stikket billigst mulig i stedet.
            if !difficulty.spillerPerfekt,
               personality.risiko > 0.7, engine.trickNummer < 3,
               billigsteVinner.rank == .ace, Bool.random() {
                return lavest(lovlige, trumf: trumf)
            }
            return billigsteVinner
        }
        return lavest(lovlige, trumf: trumf)
    }

    private func velgUtspill(engine: GameEngine, lovlige: [Card]) -> Card {
        let trumf = engine.trumf
        let spilte = Set(engine.spilteKort)

        // Budgiver: trekk ut trumfene til motstanderne først. Hvor lenge
        // laget maser på trumf styres av risikoviljen; perfekte spillere
        // trekker trumf så lenge det lønner seg.
        if seat == engine.budgiverSeat || erPåMittLag(engine.budgiverSeat ?? -1, engine: engine) {
            let trumfRunder = difficulty.spillerPerfekt ? 5
                : personality.risiko > 0.6 ? 5
                : personality.risiko > 0.3 ? 4 : 3
            if let trumf, engine.trickNummer < trumfRunder {
                let mineTrumf = lovlige.filter { $0.suit == trumf }
                let trumfIgjenUte = 13 - spilte.filter { $0.suit == trumf }.count - mineTrumf.count
                if trumfIgjenUte > 0,
                   let høyeste = mineTrumf.max(by: { $0.rank < $1.rank }),
                   mineTrumf.count >= 2 || høyeste.rank >= .king {
                    return høyeste
                }
            }
        }
        // Spill sikre vinnere: ess (eller kort som er blitt høyest) i sidefarger.
        for kort in lovlige where kort.suit != trumf {
            let høyereUte = Rank.allCases
                .filter { $0 > kort.rank }
                .map { Card(suit: kort.suit, rank: $0) }
                .allSatisfy { spilte.contains($0) }
            if kort.rank == .ace || høyereUte { return kort }
        }
        return lavest(lovlige, trumf: trumf)
    }

    /// Lagvurdering sett fra dette setet, med den informasjonen setet
    /// faktisk har: budgiveren og en avslørt makker er kjent for alle,
    /// mens en uavslørt makker bare kjenner laget sitt selv.
    private func erPåMittLag(_ annenSeat: Int, engine: GameEngine) -> Bool {
        guard annenSeat != seat else { return true }
        // Ved solo-amerikaner finnes ikke noe lag – alle spiller mot solisten.
        guard !engine.erSolo, let budgiver = engine.budgiverSeat else { return false }

        let jegErBudgiverlag = seat == budgiver || engine.makkerSeat == seat
        let annenErBudgiverlag: Bool
        if annenSeat == budgiver {
            annenErBudgiverlag = true
        } else if engine.makkerSeat == annenSeat {
            // Ingen vet hvem makkeren er før det etterlyste kortet er lagt –
            // heller ikke budgiveren, som bare kjenner kortet, ikke hånden
            // det ligger på. Makkeren selv treffer aldri denne grenen (den
            // krever annenSeat != seat), så avsløringen er eneste kilde.
            annenErBudgiverlag = engine.makkerAvslørt
        } else {
            annenErBudgiverlag = false
        }
        return jegErBudgiverlag == annenErBudgiverlag
    }

    private func kortStyrke(_ kort: Card, trumf: Suit?) -> Int {
        (kort.suit == trumf ? 100 : 0) + kort.rank.rawValue
    }

    private func lavest(_ kort: [Card], trumf: Suit?) -> Card {
        kort.min { kortStyrke($0, trumf: trumf) < kortStyrke($1, trumf: trumf) }!
    }
}
