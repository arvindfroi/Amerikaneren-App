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

/// Hva et sete meldte i budrunden – offentlig informasjon som sier noe om
/// håndstyrken: den som bød 8 har neppe søppel, den som passet på 5 har
/// neppe en kanonhånd. Brukes til å vekte samplede verdener.
struct BudProfil {
    /// Høyeste tallbud setet ga.
    var tallbud: Int?
    /// Laveste tallbud setet kunne gitt da det passet (nil om det aldri
    /// passet, eller om gulvet alt var Amerikaner-nivå).
    var passetVedGulv: Int?
    /// Meldte Amerikaner eller solo (alle stikk).
    var meldteAlle = false

    var harSignal: Bool { tallbud != nil || passetVedGulv != nil || meldteAlle }

    /// Bygger profiler per sete fra budhistorikken.
    static func fra(bids: [PlacedBid], minsteBud: Int) -> [BudProfil] {
        var profiler = [BudProfil](repeating: BudProfil(), count: 4)
        var høyesteRang = -1
        for bud in bids {
            switch bud.action {
            case .pass:
                if profiler[bud.seat].passetVedGulv == nil, høyesteRang < BidAction.amerikaner.rang {
                    profiler[bud.seat].passetVedGulv = max(minsteBud, høyesteRang + 1)
                }
            case .bud(let n):
                profiler[bud.seat].tallbud = max(profiler[bud.seat].tallbud ?? 0, n)
                høyesteRang = n
            case .amerikaner, .soloAmerikaner:
                profiler[bud.seat].meldteAlle = true
                høyesteRang = bud.action.rang
            }
        }
        return profiler
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
    let erAmerikaner: Bool       // laget må ta alle stikkene (med makker)
    let erSolo: Bool             // budvinneren spiller helt alene
    let trumfFarge: Int?
    let stikkTotalt: Int         // stikk i runden (12 med byttekort, ellers 13)
    let minHånd: UInt64
    let antallKort: [Int]        // kort igjen per sete (åpen informasjon)
    let ukjente: UInt64          // kort setet ikke vet hvor er
    let antallDødeUkjente: Int   // vrakede byttekort med ukjent innhold (0 for budgiver)
    let forbudt: [UInt64]        // per sete: kort setet beviselig ikke har (renons)
    let ønsketIndeks: Int?       // uavslørt etterlyst kort som ikke er på egen hånd
    let ønsketKandidater: [Int]  // seter som kan ha det (aldri vraket – det er forbudt å ønske dødt)
    let pliktkort: Int?          // etterlyst kort som ennå må håndheves i første stikk
    let kjentMakker: Int?        // avslørt makker – eller meg selv om jeg har kortet
    let jegErBudgiverlag: Bool
    let stikkTatt: [Int]
    let trickNummer: Int
    let leder: Int
    let pågående: [(sete: Int, indeks: Int)]
    let budProfiler: [BudProfil]   // hva hvert sete meldte (offentlig)
    let spiltAvSete: [UInt64]      // kort hvert sete har lagt så langt
    let målPoeng: Int              // styrer Amerikaner-satsene og målstreken
    let budgiverFaktor: Int        // budvinnerens multiplikator (normalt 2)
    let poengNå: [Int]             // stillingen i partiet (offentlig)
    let harMålstrek: Bool          // false i åpne partier med fast rundetall

    init?(engine: GameEngine, sete: Int) {
        guard engine.phase == .spill,
              engine.rules.antallSpillere == 4,
              let budgiver = engine.budgiverSeat,
              let budAction = engine.høyesteBud?.action else { return nil }

        self.sete = sete
        self.budgiver = budgiver
        self.bud = budAction
        self.erAmerikaner = engine.erAmerikaner
        self.erSolo = engine.erSolo
        self.trumfFarge = engine.trumf.map(Kortmaske.fargeIndeks)
        self.stikkTotalt = engine.rules.kortPerSpiller
        self.målPoeng = engine.rules.målPoeng
        self.budgiverFaktor = engine.rules.budgiverFaktor
        self.poengNå = engine.scores
        self.harMålstrek = engine.rules.maksRunder == nil
        let minMaske = Kortmaske.maske(engine.hands[sete])
        self.minHånd = minMaske
        self.antallKort = engine.hands.map(\.count)
        self.stikkTatt = engine.stikkTatt
        self.trickNummer = engine.trickNummer
        self.leder = engine.currentTrick.first?.seat ?? engine.aktivSpiller
        self.pågående = engine.currentTrick.map { ($0.seat, Kortmaske.indeks($0.card)) }

        // Budgiveren kjenner sitt eget vrak; for alle andre er de vrakede
        // kortene bare «ukjente kort som aldri dukker opp».
        let spilteMaske = Kortmaske.maske(engine.spilteKort)
        let kastetMaske = Kortmaske.maske(engine.kastet)
        if sete == budgiver {
            self.ukjente = Kortmaske.alle & ~spilteMaske & ~minMaske & ~kastetMaske
            self.antallDødeUkjente = 0
        } else {
            self.ukjente = Kortmaske.alle & ~spilteMaske & ~minMaske
            self.antallDødeUkjente = engine.kastet.count
        }

        // Gjenspill de ferdige stikkene for å finne renonser og – i første
        // stikk – hvem som beviselig ikke kan ha det etterlyste kortet
        // (makkerplikten tvinger kortet fram ved første lovlige anledning).
        let trumfIdx = self.trumfFarge
        let øIdx = engine.ønsketKort.map(Kortmaske.indeks)
        let ønsketUte = engine.ønsketKort != nil && !engine.ønsketLagt
        var forbudt = [UInt64](repeating: 0, count: 4)
        var spiltAv = [UInt64](repeating: 0, count: 4)
        var utelukketØnsket = Set<Int>()

        func registrer(sete spillerSete: Int, kortIdx: Int, ledFarge: Int, førsteStikk: Bool) {
            spiltAv[spillerSete] |= 1 << UInt64(kortIdx)
            if kortIdx / 13 != ledFarge {
                forbudt[spillerSete] |= Kortmaske.fargeMaske(ledFarge)
            }
            // Utspillsplikt: budgiveren må åpne første stikk i trumf, så et
            // annet utspill beviser at budgiveren er renons i trumffargen.
            if førsteStikk, spillerSete == budgiver, let trumfIdx, ledFarge != trumfIdx {
                forbudt[budgiver] |= Kortmaske.fargeMaske(trumfIdx)
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
        self.spiltAvSete = spiltAv
        self.budProfiler = BudProfil.fra(bids: engine.bids, minsteBud: engine.rules.minsteBud)

        // Egen lagtilhørighet: budgiveren og makkeren vet det selv fra start,
        // forsvarerne vet at de ikke har kortet. Ved solo-amerikaner finnes
        // ingen makker – den som har det etterlyste kortet er en motspiller.
        let jegHarØnsket = øIdx.map { minMaske & (1 << UInt64($0)) != 0 } ?? false
        self.jegErBudgiverlag = sete == budgiver || engine.makkerSeat == sete
        self.kjentMakker = engine.erSolo ? nil
            : engine.makkerAvslørt ? engine.makkerSeat
            : (jegHarØnsket ? sete : nil)

        // Etterlyste kort kan aldri ligge i vraket (forbudt å ønske dødt),
        // så kortet sitter garantert hos ett av de andre setene.
        if let ø = øIdx, ønsketUte, !jegHarØnsket, ukjente & (1 << UInt64(ø)) != 0 {
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
    /// alle kjente begrensninger. «Sete 4» er vrakhaugen: de byttekortene
    /// budvinneren la bort, med ukjent innhold for alle andre. Mest bundne
    /// kort plasseres først.
    func sampleVerden<R: RandomNumberGenerator>(rng: inout R) -> Verden? {
        var pool = Kortmaske.indekser(ukjente)
        if let ø = ønsketIndeks {
            pool.removeAll { $0 == ø }
        }

        for _ in 0..<120 {
            var hender = SIMD4<UInt64>(repeating: 0)
            hender[sete] = minHånd
            var behov = antallKort + [antallDødeUkjente]
            behov[sete] = 0
            var makker = kjentMakker

            if let ø = ønsketIndeks {
                let mulige = ønsketKandidater.filter { behov[$0] > 0 }
                guard let valgt = mulige.randomElement(using: &rng) else { return nil }
                hender[valgt] |= 1 << UInt64(ø)
                if !erSolo { makker = valgt }
                behov[valgt] -= 1
            }

            pool.shuffle(using: &rng)
            let ordnet = pool.sorted { a, b in
                antallTillatte(a, behov: behov) < antallTillatte(b, behov: behov)
            }

            var ok = true
            for kortIdx in ordnet {
                let bit: UInt64 = 1 << UInt64(kortIdx)
                let valgbare = (0...4).filter { s in
                    behov[s] > 0 && (s == 4 || forbudt[s] & bit == 0)
                }
                guard !valgbare.isEmpty else { ok = false; break }
                // Vektet etter gjenstående behov for jevn fordeling.
                let total = valgbare.reduce(0) { $0 + behov[$1] }
                var r = Int.random(in: 0..<total, using: &rng)
                var valgt = valgbare[0]
                for s in valgbare {
                    r -= behov[s]
                    if r < 0 { valgt = s; break }
                }
                if valgt < 4 { hender[valgt] |= bit }
                behov[valgt] -= 1
            }
            guard ok else { continue }

            var lag: UInt8 = 1 << UInt8(budgiver)
            if !erSolo, let makker { lag |= 1 << UInt8(makker) }
            return Verden(hender: hender, makker: erSolo ? nil : makker, lagMaske: lag)
        }
        return nil
    }

    private func antallTillatte(_ kortIdx: Int, behov: [Int]) -> Int {
        let bit: UInt64 = 1 << UInt64(kortIdx)
        return (0...4).filter { s in
            behov[s] > 0 && (s == 4 || forbudt[s] & bit == 0)
        }.count
    }
}

// MARK: - Budvekt

/// Hvor sannsynlig en samplet verden er gitt det setene meldte. Delt kode,
/// slik at PIMC-søket i `MesterAI` og informasjonssett-søket i
/// `MesterISMCTS` bruker nøyaktig samme verdensfordeling – ellers ville en
/// sammenlikning av de to måle vektingen og ikke søkemetoden.
enum Budvekt {
    static func vekt(profiler: [BudProfil], hender: SIMD4<UInt64>, spiltAv: [UInt64]?,
                     stikkTotalt: Int, egetSete: Int) -> Double {
        var vekt = 1.0
        for s in 0..<4 where s != egetSete {
            let profil = profiler[s]
            guard profil.harSignal else { continue }
            let full = hender[s] | (spiltAv?[s] ?? 0)
            guard full != 0 else { continue }
            let est = AIPlayer.besteTrumf(hånd: Kortmaske.kortliste(full)).estimat
            if profil.meldteAlle {
                vekt *= exp(-0.5 * max(0, Double(stikkTotalt) - 2.0 - est))
            } else if let n = profil.tallbud {
                vekt *= exp(-0.6 * max(0, Double(n) - (est + 2.5)))
            }
            if let gulv = profil.passetVedGulv {
                vekt *= exp(-0.4 * max(0, est + 2.0 - Double(gulv) - 1.5))
            }
        }
        return max(vekt, 0.02)
    }
}

// MARK: - Målfunksjonen i kortspillet

extension Spillinnsikt {
    /// Budvekten for en samplet verden i stikkspillet.
    func budVekt(hender: SIMD4<UInt64>) -> Double {
        Budvekt.vekt(profiler: budProfiler, hender: hender, spiltAv: spiltAvSete,
                     stikkTotalt: stikkTotalt, egetSete: sete)
    }

    /// Målfunksjonen i kortspillet, regnet ut for **alle fire seter**.
    ///
    /// Dette er nøyaktig regnestykket fra `MesterAI.vurder`, bare generalisert
    /// fra «eget sete» til et sete-parameter: forventet poengendring for setet
    /// minus de tre andres, vektet mot hvor nær hver av dem er målstreken, og
    /// med et stort tillegg/fradrag for å krysse (eller fôre noen over)
    /// målstreken. `MesterAI` henter fortsatt bare sin egen komponent, så tall
    /// og A/B-er derfra er uendret; ISMCTS trenger hele vektoren fordi hvert
    /// sete i treet maksimerer sin egen verdi (max^n).
    ///
    /// - Parameters:
    ///   - lagMaske: budgiverlagets seter i den samplede verdenen.
    ///   - perSete: stikk vunnet per sete etter rotstillingen.
    ///   - restLagStikk: budgiverlagets stikk i den delen som ble løst med
    ///     dobbeltdummy (0 når resten er spilt helt ut).
    func måltall(lagMaske: UInt8, perSete: [Int], restLagStikk: Int) -> SIMD4<Double> {
        var lagStikk = restLagStikk
        for s in 0..<4 where lagMaske & (1 << UInt8(s)) != 0 {
            lagStikk += stikkTatt[s] + perSete[s]
        }

        let mål: Int
        switch bud {
        case .bud(let n): mål = n
        case .amerikaner, .soloAmerikaner, .pass: mål = stikkTotalt
        }
        let suksess = lagStikk >= mål

        // Poengsatser som i motoren (GameEngine.avsluttRunde).
        let budgiverPoeng: Int
        let makkerPoeng: Int
        switch bud {
        case .soloAmerikaner:
            budgiverPoeng = målPoeng; makkerPoeng = 0
        case .amerikaner:
            budgiverPoeng = målPoeng / 2; makkerPoeng = målPoeng / 4
        case .bud(let n):
            budgiverPoeng = n * budgiverFaktor; makkerPoeng = n
        case .pass:
            budgiverPoeng = 0; makkerPoeng = 0
        }

        // Forsvarernes stikk er eksakte for den spilte delen; en eventuell
        // dobbeltdummy-hale gir bare lagets sum, så resten fordeles likt.
        let spiltStikk = (0..<4).reduce(0) { $0 + stikkTatt[$1] + perSete[$1] }
        let haleForsvar = (stikkTotalt - spiltStikk) - restLagStikk
        let antallForsvarere = 4 - (0..<4).count { lagMaske & (1 << UInt8($0)) != 0 }
        let forsvarsAndel = antallForsvarere > 0 ? Double(haleForsvar) / Double(antallForsvarere) : 0

        var delta = SIMD4<Double>(repeating: 0)
        for s in 0..<4 {
            if s == budgiver {
                delta[s] = Double(suksess ? budgiverPoeng : -budgiverPoeng)
            } else if lagMaske & (1 << UInt8(s)) != 0 {
                delta[s] = Double(suksess ? makkerPoeng : -makkerPoeng)
            } else {
                delta[s] = Double(stikkTatt[s] + perSete[s]) + forsvarsAndel
            }
        }

        var ut = SIMD4<Double>(repeating: 0)
        let målstrek = Double(målPoeng)
        for meg in 0..<4 {
            var verdi = delta[meg]
            for s in 0..<4 where s != meg {
                let nærhet = Double(min(poengNå[s], målPoeng)) / Double(målPoeng)
                verdi -= (1.0 + nærhet) / 3.0 * delta[s]
            }
            if harMålstrek {
                if Double(poengNå[meg]) + delta[meg] >= målstrek {
                    verdi += målstrek
                } else if (0..<4).contains(where: {
                    $0 != meg && Double(poengNå[$0]) + delta[$0] >= målstrek
                }) {
                    verdi -= målstrek
                }
            }
            ut[meg] = verdi
        }
        return ut
    }
}
