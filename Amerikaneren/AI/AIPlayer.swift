import Foundation

/// Heuristisk AI-spiller. Vurderer hånden for bud, velger trumf/makkerkort
/// og spiller stikk med enkel kortteling. Personlighet og vanskelighetsgrad
/// justerer beslutningene.
struct AIPlayer {
    let seat: Int
    let difficulty: AIDifficulty
    let personality: AIPersonality

    // MARK: - Håndvurdering

    /// Estimerer antall stikk med gitt farge som trumf.
    static func estimerStikk(hånd: [Card], trumf: Suit) -> Double {
        var estimat = 0.0
        let trumfKort = hånd.filter { $0.suit == trumf }
        // Trumflengde er konge: hvert trumfkort over 3 er nesten et stikk.
        estimat += Double(trumfKort.count) * 0.55
        if trumfKort.count > 3 { estimat += Double(trumfKort.count - 3) * 0.4 }

        for kort in hånd {
            let iFarge = hånd.filter { $0.suit == kort.suit }.count
            switch kort.rank {
            case .ace: estimat += kort.suit == trumf ? 1.0 : 0.9
            case .king: estimat += iFarge >= 2 ? 0.65 : 0.3
            case .queen: estimat += iFarge >= 3 ? 0.35 : 0.15
            default: break
            }
        }
        // Renons og singelton gir stjålne stikk med trumf på hånden.
        for suit in Suit.allCases where suit != trumf {
            let antall = hånd.filter { $0.suit == suit }.count
            if antall == 0 { estimat += min(2.0, Double(trumfKort.count)) * 0.45 }
            if antall == 1 { estimat += 0.3 }
        }
        return estimat
    }

    static func besteTrumf(hånd: [Card]) -> (suit: Suit, estimat: Double) {
        var beste: (Suit, Double) = (.spar, -1)
        for suit in Suit.allCases {
            let e = estimerStikk(hånd: hånd, trumf: suit)
            if e > beste.1 { beste = (suit, e) }
        }
        return beste
    }

    // MARK: - Budgivning

    func velgBud(engine: GameEngine) -> BidAction {
        let lovlige = engine.lovligeBud(for: seat)
        guard !lovlige.isEmpty else { return .pass }
        let hånd = engine.hands[seat]
        let (_, råEstimat) = Self.besteTrumf(hånd: hånd)

        // Makkeren bidrar typisk med noen stikk.
        var estimat = råEstimat + 2.0
        estimat += (personality.aggresjon - 0.5) * 2.5
        estimat += Double.random(in: -difficulty.budStøy...difficulty.budStøy)

        // Amerikaner-drøm: nesten alle stikk selv, uten trumf.
        let solostikk = Self.estimerStikk(hånd: hånd, trumf: Self.besteTrumf(hånd: hånd).suit)
        if solostikk >= 11.5, Double.random(in: 0...1) < personality.storhetsdrøm,
           lovlige.contains(.amerikaner) {
            return .amerikaner
        }

        let mittBud = Int(estimat.rounded())
        let tallbud = lovlige.compactMap { action -> Int? in
            if case .bud(let n) = action { return n }
            return nil
        }
        // Bløff: press budet opp ett hakk uten dekning.
        let bløffer = Double.random(in: 0...1) < personality.bløff * 0.5
        let grense = bløffer ? mittBud + 1 : mittBud
        if let laveste = tallbud.min(), laveste <= grense {
            return .bud(laveste)
        }
        return .pass
    }

    func velgTrumfOgMakker(engine: GameEngine) -> (Suit, Card)? {
        let hånd = engine.hands[seat]
        let (suit, _) = Self.besteTrumf(hånd: hånd)
        let kandidater = engine.kortSomKanØnskes(trumf: suit)
        // Be om høyeste trumf man ikke har selv – da får laget beste kort.
        guard let ønsket = kandidater.first else {
            // Har alle trumfene: be om høyeste kort i nest beste farge.
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

        // Makkeren har stikket: legg lavest, med mindre lojaliteten er lav
        // og vi kan sikre med et stort kort selv.
        if makkerVinner, stikk.count == engine.rules.antallSpillere - 1 || personality.lojalitet > 0.35 {
            return lavest(lovlige, trumf: trumf)
        }

        if let billigsteVinner = vinnende.min(by: { kortStyrke($0, trumf: trumf) < kortStyrke($1, trumf: trumf) }) {
            // Risikovillige sparer storkortene når stikket er lite verdt tidlig.
            if personality.risiko > 0.7, engine.trickNummer < 3,
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

        // Budgiver: trekk ut trumfene til motstanderne først.
        if seat == engine.budgiverSeat || erPåMittLag(engine.budgiverSeat ?? -1, engine: engine) {
            if let trumf, engine.trickNummer < 4 {
                let mineTrumf = lovlige.filter { $0.suit == trumf }
                if let høyeste = mineTrumf.max(by: { $0.rank < $1.rank }),
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

    private func erPåMittLag(_ annenSeat: Int, engine: GameEngine) -> Bool {
        guard annenSeat != seat else { return true }
        guard !engine.erAmerikaner else { return false }
        guard let budgiver = engine.budgiverSeat else { return false }
        let lag = [budgiver, engine.makkerAvslørt ? engine.makkerSeat : jegErMakker(engine: engine) ? engine.makkerSeat : nil]
            .compactMap { $0 }
        let jegPåLaget = lag.contains(seat)
        let hanPåLaget = lag.contains(annenSeat)
        // Uavslørt makker vet selv hvem den spiller med; andre antar motpart.
        return jegPåLaget == hanPåLaget && (jegPåLaget || engine.makkerAvslørt || !lag.contains(annenSeat))
    }

    private func jegErMakker(engine: GameEngine) -> Bool {
        engine.makkerSeat == seat
    }

    private func kortStyrke(_ kort: Card, trumf: Suit?) -> Int {
        (kort.suit == trumf ? 100 : 0) + kort.rank.rawValue
    }

    private func lavest(_ kort: [Card], trumf: Suit?) -> Card {
        kort.min { kortStyrke($0, trumf: trumf) < kortStyrke($1, trumf: trumf) }!
    }
}
