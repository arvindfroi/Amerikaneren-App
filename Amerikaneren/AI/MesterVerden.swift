import Foundation

/// Bitmaske-representasjon av kort for søkemotoren i MesterAI.
/// Indeks = farge × 13 + (valør − 2), så én UInt64 rommer hele stokken.
enum Kortmaske {
    static let farger: [Suit] = [.spar, .hjerter, .ruter, .kløver]
    static let alle: UInt64 = (1 << 52) - 1

    static func fargeIndeks(_ suit: Suit) -> Int {
        switch suit {
        case .spar: return 0
        case .hjerter: return 1
        case .ruter: return 2
        case .kløver: return 3
        }
    }

    static func indeks(_ kort: Card) -> Int {
        fargeIndeks(kort.suit) * 13 + (kort.rank.rawValue - 2)
    }

    static func kort(_ indeks: Int) -> Card {
        Card(suit: farger[indeks / 13], rank: Rank(rawValue: indeks % 13 + 2)!)
    }

    static func maske(_ kort: [Card]) -> UInt64 {
        kort.reduce(0) { $0 | (1 << UInt64(indeks($1))) }
    }

    static func kortliste(_ maske: UInt64) -> [Card] {
        indekser(maske).map { kort($0) }
    }

    static func indekser(_ maske: UInt64) -> [Int] {
        var m = maske
        var resultat: [Int] = []
        while m != 0 {
            resultat.append(m.trailingZeroBitCount)
            m &= m - 1
        }
        return resultat
    }

    static func fargeMaske(_ farge: Int) -> UInt64 {
        0x1FFF << (UInt64(farge) * 13)
    }

    static func høyeste(_ maske: UInt64) -> Int {
        63 - maske.leadingZeroBitCount
    }

    static func laveste(_ maske: UInt64) -> Int {
        maske.trailingZeroBitCount
    }

    /// Hvor «dyrt» kortet er å gi fra seg: lav valør er billig, trumf er dyrt.
    static func kostnad(_ indeks: Int, trumfFarge: Int?) -> Int {
        (indeks / 13 == trumfFarge ? 100 : 0) + indeks % 13
    }
}

/// Alt et sete lovlig vet om stikkspillet: egen hånd, spilte kort, avslørte
/// renonser og hvor det etterlyste kortet kan befinne seg. MesterAI ser aldri
/// motstandernes hender – bare dette – og trekker slutninger på samme grunnlag
/// som et menneske i setet kunne gjort.
struct Spillinnsikt {
    let sete: Int
    let budgiver: Int
    let bud: BidAction
    let erAmerikaner: Bool
    let trumfFarge: Int?
    let minHånd: UInt64
    let antallKort: [Int]        // kort igjen per sete (åpen informasjon)
    let ukjente: UInt64          // kort setet ikke vet hvor er
    let forbudt: [UInt64]        // per sete: kort setet beviselig ikke har (renons)
    let ønsketIndeks: Int?       // uavslørt etterlyst kort som ikke er på egen hånd
    let ønsketKandidater: [Int]  // seter som fortsatt kan ha det
    let pliktkort: Int?          // etterlyst kort som ennå må håndheves i første stikk
    let kjentMakker: Int?        // avslørt makker – eller meg selv om jeg har kortet
    let jegErBudgiverlag: Bool
    let stikkTatt: [Int]
    let trickNummer: Int
    let leder: Int
    let pågående: [(sete: Int, indeks: Int)]

    init?(engine: GameEngine, sete: Int) {
        guard engine.phase == .spill,
              engine.rules.antallSpillere == 4,
              let budgiver = engine.budgiverSeat,
              let budAction = engine.høyesteBud?.action else { return nil }

        self.sete = sete
        self.budgiver = budgiver
        self.bud = budAction
        self.erAmerikaner = engine.erAmerikaner
        self.trumfFarge = engine.trumf.map(Kortmaske.fargeIndeks)
        let minMaske = Kortmaske.maske(engine.hands[sete])
        self.minHånd = minMaske
        self.antallKort = engine.hands.map(\.count)
        self.stikkTatt = engine.stikkTatt
        self.trickNummer = engine.trickNummer
        self.leder = engine.currentTrick.first?.seat ?? engine.aktivSpiller
        self.pågående = engine.currentTrick.map { ($0.seat, Kortmaske.indeks($0.card)) }

        let spilteMaske = Kortmaske.maske(engine.spilteKort)
        self.ukjente = Kortmaske.alle & ~spilteMaske & ~minMaske

        // Gjenspill de ferdige stikkene for å finne renonser og – i første
        // stikk – hvem som beviselig ikke kan ha det etterlyste kortet
        // (makkerplikten tvinger kortet fram ved første lovlige anledning).
        let trumfIdx = self.trumfFarge
        let øIdx = engine.ønsketKort.map(Kortmaske.indeks)
        let ønsketUte = engine.ønsketKort != nil && !engine.makkerAvslørt
        var forbudt = [UInt64](repeating: 0, count: 4)
        var utelukketØnsket = Set<Int>()

        func registrer(sete spillerSete: Int, kortIdx: Int, ledFarge: Int, førsteStikk: Bool) {
            if kortIdx / 13 != ledFarge {
                forbudt[spillerSete] |= Kortmaske.fargeMaske(ledFarge)
            }
            guard førsteStikk, ønsketUte, let ø = øIdx,
                  spillerSete != budgiver, kortIdx != ø else { return }
            // Fulgte spilleren en annen farge var ønsket kort aldri lovlig;
            // ellers ville makkerplikten tvunget det fram.
            if kortIdx / 13 != ledFarge || ledFarge == ø / 13 {
                utelukketØnsket.insert(spillerSete)
            }
        }

        let spilteIdx = engine.spilteKort.map(Kortmaske.indeks)
        var pos = 0
        var led = budgiver
        var trickNr = 0
        while pos + 4 <= spilteIdx.count - engine.currentTrick.count {
            let ledFarge = spilteIdx[pos] / 13
            var besteSete = led
            var besteIdx = spilteIdx[pos]
            for i in 0..<4 {
                let spillerSete = (led + i) % 4
                let kortIdx = spilteIdx[pos + i]
                registrer(sete: spillerSete, kortIdx: kortIdx, ledFarge: ledFarge, førsteStikk: trickNr == 0)
                if i > 0, Spillregler.slår(kortIdx, besteIdx, trumfFarge: trumfIdx) {
                    besteSete = spillerSete
                    besteIdx = kortIdx
                }
            }
            led = besteSete
            pos += 4
            trickNr += 1
        }
        if let ledFarge = pågående.first.map({ $0.indeks / 13 }) {
            for spill in pågående {
                registrer(sete: spill.sete, kortIdx: spill.indeks,
                          ledFarge: ledFarge, førsteStikk: trickNummer == 0)
            }
        }
        self.forbudt = forbudt

        // Egen lagtilhørighet: budgiveren og makkeren vet det selv fra start,
        // forsvarerne vet at de ikke har kortet.
        let jegHarØnsket = øIdx.map { minMaske & (1 << UInt64($0)) != 0 } ?? false
        self.jegErBudgiverlag = sete == budgiver || engine.makkerSeat == sete
        self.kjentMakker = engine.makkerAvslørt ? engine.makkerSeat : (jegHarØnsket ? sete : nil)

        if let ø = øIdx, ønsketUte, !jegHarØnsket {
            self.ønsketIndeks = ø
            let kandidater = (0..<4).filter { s in
                s != sete && s != budgiver && !utelukketØnsket.contains(s)
                    && forbudt[s] & (1 << UInt64(ø)) == 0
            }
            // Skulle slutningene (mot formodning) utelukke alle, slipp dem.
            self.ønsketKandidater = kandidater.isEmpty
                ? (0..<4).filter { $0 != sete && $0 != budgiver }
                : kandidater
        } else {
            self.ønsketIndeks = nil
            self.ønsketKandidater = []
        }
        self.pliktkort = (trickNummer == 0 && ønsketUte) ? øIdx : nil
    }
}

/// En samplet fullinformasjonsverden: konkrete hender for alle seter,
/// konsistent med alt setet vet.
struct Verden {
    var hender: SIMD4<UInt64>
    var makker: Int?
    var lagMaske: UInt8   // budgiverlagets seter som bitmaske
}

extension Spillinnsikt {
    /// Trekker en tilfeldig fordeling av de ukjente kortene som respekterer
    /// alle kjente begrensninger. Mest bundne kort plasseres først.
    func sampleVerden<R: RandomNumberGenerator>(rng: inout R) -> Verden? {
        var pool = Kortmaske.indekser(ukjente)
        if let ø = ønsketIndeks {
            pool.removeAll { $0 == ø }
        }

        for _ in 0..<120 {
            var hender = SIMD4<UInt64>(repeating: 0)
            hender[sete] = minHånd
            var behov = antallKort
            behov[sete] = 0
            var makker = kjentMakker

            if let ø = ønsketIndeks {
                let mulige = ønsketKandidater.filter { behov[$0] > 0 }
                guard let valgt = mulige.randomElement(using: &rng) else { return nil }
                hender[valgt] |= 1 << UInt64(ø)
                behov[valgt] -= 1
                makker = valgt
            }

            pool.shuffle(using: &rng)
            let ordnet = pool.sorted { a, b in
                antallTillatte(a, behov: behov) < antallTillatte(b, behov: behov)
            }

            var ok = true
            for kortIdx in ordnet {
                let bit: UInt64 = 1 << UInt64(kortIdx)
                let valgbare = (0..<4).filter { behov[$0] > 0 && forbudt[$0] & bit == 0 }
                guard !valgbare.isEmpty else { ok = false; break }
                // Vektet etter gjenstående behov for jevn fordeling.
                let total = valgbare.reduce(0) { $0 + behov[$1] }
                var r = Int.random(in: 0..<total, using: &rng)
                var valgt = valgbare[0]
                for s in valgbare {
                    r -= behov[s]
                    if r < 0 { valgt = s; break }
                }
                hender[valgt] |= bit
                behov[valgt] -= 1
            }
            guard ok else { continue }

            var lag: UInt8 = 1 << UInt8(budgiver)
            if !erAmerikaner, let makker { lag |= 1 << UInt8(makker) }
            return Verden(hender: hender, makker: erAmerikaner ? nil : makker, lagMaske: lag)
        }
        return nil
    }

    private func antallTillatte(_ kortIdx: Int, behov: [Int]) -> Int {
        let bit: UInt64 = 1 << UInt64(kortIdx)
        return (0..<4).filter { behov[$0] > 0 && forbudt[$0] & bit == 0 }.count
    }
}
