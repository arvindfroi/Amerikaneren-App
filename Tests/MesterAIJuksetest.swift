import XCTest
import Foundation
@testable import Amerikaneren

/// # Jukse-testen: bruker MesterAI skjult informasjon?
///
/// Testen er en **informasjonsteoretisk invariansprøve**, ikke en
/// kodegjennomlesning. Premisset er enkelt og umulig å komme utenom:
///
/// > Hvis MesterAI bare bruker lovlig informasjon, er valget dens en ren
/// > funksjon av (eget informasjonssett, frø, konfigurasjon). To stillinger
/// > med identisk informasjonssett MÅ derfor gi bit-identisk valg.
///
/// For hvert testtilfelle bygges en ORIGINAL stilling og en TVILLING der
/// * setets egen hånd er identisk,
/// * hele budhistorikken er identisk,
/// * alle spilte kort (i samme rekkefølge, av samme seter) er identiske,
/// * poengstillingen og kortantallet per sete er identisk,
/// * makkerstatusen setet kjenner er identisk,
///
/// mens de tre andre setenes GJENVÆRENDE kort – og vraket, for seter som
/// ikke er budgiver – er byttet ut med en annen lovlig fordeling av de
/// samme ukjente kortene. Avviker valget, lekker skjult informasjon.
///
/// ## Hvordan tvillingene garanteres lovlige
/// Tvillingen bygges ikke ved å «rette på» en tilstand, men ved å dele ut
/// på nytt og **spille hele runden om igjen gjennom motorens eget API** med
/// nøyaktig samme bud og nøyaktig samme kortsekvens. Motoren håndhever selv
/// følg-farge, budgiverens trumfutspill og makkerplikten i første stikk, så
/// en tvilling som lar seg spille fram er per konstruksjon konsistent med
/// alle renonser og alle slutninger som er offentlig kjent. Tvillinger som
/// motoren avviser, forkastes. I tillegg sammenliknes de to motorene felt
/// for felt på alt som er offentlig, før valget måles.
///
/// Budgiveren kjenner sitt eget vrak, så vraket permuteres aldri når det
/// er budgiveren som testes.
///
/// ## Positiv kontroll
/// `testPositivKontroll…` kjører den samme prøven på `Referansesøker`, en
/// søker med samme informasjonsgrunnlag som MesterAI og én bryter: `juks`.
/// Slått av skal prøven godta den; slått på (den forkaster verdener som
/// plasserer et bestemt kort feil – en beskjeden lekkasje) skal prøven
/// fange den. `Fasitspiller`, som løser dobbeltdummy på de EKTE hendene,
/// er den grove kontrollen. En test som aldri kan feile beviser ingenting.
final class MesterAIJuksetest: XCTestCase {

    // MARK: - Konfigurasjon

    /// FASTE verdenstall og et absurd romslig tidsbudsjett. Uten dette blir
    /// MesterAI lastavhengig, og to kjøringer ville avvike av tidsgrunner i
    /// stedet for informasjonsgrunner.
    private static func fastKonfig() -> MesterKonfig {
        var k = MesterKonfig()
        k.minVerdener = 16
        k.maksVerdener = 16
        k.maksVerdenerSluttspill = 48
        k.tidsbudsjett = 86_400   // aldri bindende: taket, ikke klokka, styrer
        k.verdenerVedBud = 24
        k.verdenerVedBytte = 12
        k.eksaktStikkGrense = 6
        return k
    }

    /// Antall posisjonspar per beslutningstype. Kan skrus opp for en grundig
    /// kjøring: `JUKSETEST_SKALA=4 swift test --filter MesterAIJuksetest`.
    private static var skala: Int {
        Int(ProcessInfo.processInfo.environment["JUKSETEST_SKALA"] ?? "") ?? 1
    }

    // MARK: - Stillingsoppskrift

    /// Alt som skal til for å bygge en stilling fra bunnen gjennom motorens
    /// eget API. Både originalen og tvillingen bygges via `bygg`, slik at
    /// de går nøyaktig samme vei gjennom motoren.
    private struct Oppsett {
        var hender: [[Card]]
        var talon: [Card]
        var førsteBudgiver: Int
        var bud: [PlacedBid]
        var vrak: [Card] = []
        var trumf: Suit = .spar
        var ønsket: Card?
        var spill: [(sete: Int, kort: Card)] = []
    }

    private enum Stopp { case budrunde, byttekort, velgTrumf, spill }

    private func bygg(_ o: Oppsett, stopp: Stopp) -> GameEngine? {
        guard o.hender.count == 4, o.hender.allSatisfy({ $0.count == 12 }),
              o.talon.count == 4 else { return nil }
        // Samme kort må ikke forekomme to steder.
        let alle = o.hender.flatMap { $0 } + o.talon
        guard Set(alle).count == 52 else { return nil }

        let e = GameEngine()
        e.startRunde(hender: o.hender.map { $0.sortertForHånd() },
                     talon: o.talon, førsteBudgiver: o.førsteBudgiver)
        for b in o.bud {
            guard e.giBud(seat: b.seat, action: b.action) else { return nil }
        }
        if stopp == .budrunde { return e.phase == .budrunde ? e : nil }
        guard e.phase == .byttekort, let budgiver = e.budgiverSeat else { return nil }
        if stopp == .byttekort { return e }
        guard e.kastByttekort(o.vrak, seat: budgiver) else { return nil }
        if stopp == .velgTrumf { return e }
        guard e.velgTrumf(suit: o.trumf, ønsket: o.ønsket) else { return nil }
        for t in o.spill {
            guard e.spill(kort: t.kort, seat: t.sete) else { return nil }
        }
        return e.phase == .spill ? e : nil
    }

    // MARK: - Tilfeldige, men reproduserbare stillinger

    private func del(rng: inout SeededGenerator) -> (hender: [[Card]], talon: [Card]) {
        var stokk = Deck.full()
        stokk.shuffle(using: &rng)
        let hender = (0..<4).map { s in Array(stokk[(s * 12)..<((s + 1) * 12)]).sortertForHånd() }
        return (hender, Array(stokk[48..<52]))
    }

    /// Spiller budrunden ferdig med et tilfeldig, men lovlig meldeforløp.
    /// Første sete melder alltid, ellers kan alle passe og motoren deler ut
    /// på nytt med en tilfeldig stokk (som ville ødelagt reproduserbarheten).
    private func lagBudhistorikk(hender: [[Card]], talon: [Card], førsteBudgiver: Int,
                                 rng: inout SeededGenerator) -> [PlacedBid]? {
        let e = GameEngine()
        e.startRunde(hender: hender, talon: talon, førsteBudgiver: førsteBudgiver)
        var bud: [PlacedBid] = []
        var første = true
        var runder = 0
        while e.phase == .budrunde, runder < 40 {
            runder += 1
            let sete = e.aktivBudgiver
            let lovlige = e.lovligeBud(for: sete)
            guard !lovlige.isEmpty else { return nil }
            let tallbud = lovlige.compactMap { a -> Int? in
                if case .bud(let n) = a { return n }
                return nil
            }
            var handling = BidAction.pass
            let terning = Int.random(in: 0..<100, using: &rng)
            if første, terning < 4, lovlige.contains(.soloAmerikaner) {
                handling = .soloAmerikaner
            } else if første, terning < 12, lovlige.contains(.amerikaner) {
                handling = .amerikaner
            } else if første || terning < 35, let n = tallbud.min(), n <= 9 {
                handling = .bud(n)
            }
            første = false
            guard e.giBud(seat: sete, action: handling) else { return nil }
            bud.append(PlacedBid(seat: sete, action: handling))
        }
        return e.phase == .byttekort ? bud : nil
    }

    /// Fullt oppsett fram til og med trumfvalget, med tilfeldig vrak og
    /// tilfeldig lovlig etterlysning.
    private func lagOppsettTilSpill(rng: inout SeededGenerator) -> Oppsett? {
        let (hender, talon) = del(rng: &rng)
        let førsteBudgiver = Int.random(in: 0..<4, using: &rng)
        guard let bud = lagBudhistorikk(hender: hender, talon: talon,
                                        førsteBudgiver: førsteBudgiver, rng: &rng) else { return nil }
        var o = Oppsett(hender: hender, talon: talon, førsteBudgiver: førsteBudgiver, bud: bud)
        guard let e = bygg(o, stopp: .byttekort), let budgiver = e.budgiverSeat else { return nil }

        var stokket = e.hands[budgiver]
        stokket.shuffle(using: &rng)
        o.vrak = Array(stokket.prefix(4))
        guard let etterKast = bygg(o, stopp: .velgTrumf) else { return nil }
        var farger = Kortmaske.farger
        farger.shuffle(using: &rng)
        for suit in farger {
            let ønskbare = etterKast.kortSomKanØnskes(trumf: suit)
            if etterKast.erSolo {
                o.trumf = suit
                let uttrekk: Card? = ønskbare.randomElement(using: &rng)
                o.ønsket = Int.random(in: 0..<2, using: &rng) == 0 ? Card?.none : uttrekk
                return o
            }
            if let ønsket = ønskbare.randomElement(using: &rng) {
                o.trumf = suit
                o.ønsket = ønsket
                return o
            }
        }
        return nil
    }

    /// Legger på et tilfeldig, lovlig spilleforløp av gitt lengde.
    private func medSpill(_ o: Oppsett, antall: Int, rng: inout SeededGenerator) -> Oppsett? {
        guard let e = bygg(o, stopp: .spill) else { return nil }
        var trekk: [(sete: Int, kort: Card)] = []
        for _ in 0..<antall {
            guard e.phase == .spill else { break }
            let sete = e.aktivSpiller
            guard let kort = e.lovligeKort(for: sete).randomElement(using: &rng),
                  e.spill(kort: kort, seat: sete) else { return nil }
            trekk.append((sete, kort))
        }
        var ny = o
        ny.spill = trekk
        return ny
    }

    /// Hvor langt runden er spilt. Vektet slik at fasen FØR makkeren er
    /// avslørt (første stikk) blir godt representert – det er der det finnes
    /// mest skjult informasjon å lekke.
    private func trekkSpillengde(rng: inout SeededGenerator) -> Int {
        Int.random(in: 0..<4, using: &rng) == 0
            ? Int.random(in: 0..<4, using: &rng)
            : Int.random(in: 0..<44, using: &rng)
    }

    // MARK: - Tvillingbygging

    /// Blander alle kort setet IKKE ser. Setets egen hånd står alltid urørt;
    /// `frysTalon` fryser i tillegg talongen, som budgiveren har tatt opp og
    /// derfor kjenner.
    private func stokkUsett(_ o: Oppsett, sete: Int, frysTalon: Bool,
                            rng: inout SeededGenerator) -> Oppsett {
        var pott = o.talon
        if frysTalon { pott = [] }
        for s in 0..<4 where s != sete { pott += o.hender[s] }
        pott.shuffle(using: &rng)

        var ny = o
        var neste = 0
        for s in 0..<4 where s != sete {
            ny.hender[s] = Array(pott[neste..<(neste + 12)]).sortertForHånd()
            neste += 12
        }
        if !frysTalon { ny.talon = Array(pott[neste..<(neste + 4)]) }
        return ny
    }

    /// Tvilling for en stilling midt i stikkspillet. Forslaget hentes fra
    /// `Spillinnsikt.sampleVerden` (som per definisjon bare kjenner det
    /// lovlige informasjonssettet), og MOTOREN avgjør om det holder: hele
    /// runden må la seg spille om igjen, trekk for trekk, med nøyaktig samme
    /// kortsekvens. Klarer den ikke det, er tvillingen forkastet.
    private func spilltvilling(original e: GameEngine, oppsett o: Oppsett, sete: Int,
                               rng: inout SeededGenerator) -> (GameEngine, Oppsett)? {
        guard let innsikt = Spillinnsikt(engine: e, sete: sete),
              let budgiver = e.budgiverSeat else { return nil }
        let ekte = (0..<4).map { Kortmaske.maske(e.hands[$0]) }
        var spiltAv = [[Card]](repeating: [], count: 4)
        for t in o.spill { spiltAv[t.sete].append(t.kort) }

        for _ in 0..<30 {
            guard let verden = innsikt.sampleVerden(rng: &rng) else { return nil }

            var union: UInt64 = 0
            for s in 0..<4 { union |= verden.hender[s] }
            // Budgiveren kjenner sitt eget vrak – det permuteres aldri.
            let nyttVrak = sete == budgiver ? o.vrak
                : Kortmaske.kortliste(innsikt.ukjente & ~union)
            guard nyttVrak.count == 4 else { continue }

            // Tvillingen må faktisk være en ANNEN verden.
            var forskjellig = Set(nyttVrak) != Set(o.vrak)
            for s in 0..<4 where s != sete && verden.hender[s] != ekte[s] { forskjellig = true }
            guard forskjellig else { continue }

            // Utdelte hender = spilte kort + de nye restene. Budgiveren deles
            // nøyaktig de tolv kortene som beholdes, og vraket blir talongen –
            // da gir samme vrak-handling samme sluttilstand.
            var nyeHender = [[Card]](repeating: [], count: 4)
            for s in 0..<4 {
                let rest = s == sete ? e.hands[s] : Kortmaske.kortliste(verden.hender[s])
                nyeHender[s] = (spiltAv[s] + rest).sortertForHånd()
            }
            guard nyeHender.allSatisfy({ $0.count == 12 }) else { continue }

            var ny = o
            ny.hender = nyeHender
            ny.talon = nyttVrak
            ny.vrak = nyttVrak
            guard let t = bygg(ny, stopp: .spill) else { continue }
            guard erOffentligIdentiske(e, t, sete: sete) else { continue }
            return (t, ny)
        }
        return nil
    }

    /// Alt som er offentlig – eller kjent for nettopp dette setet – må være
    /// bit-identisk. Dette er kontrakten testen hviler på.
    private func erOffentligIdentiske(_ a: GameEngine, _ b: GameEngine, sete: Int) -> Bool {
        guard a.hands[sete] == b.hands[sete],
              a.hands.map(\.count) == b.hands.map(\.count),
              a.bids == b.bids,
              a.budgiverSeat == b.budgiverSeat,
              a.høyesteBud == b.høyesteBud,
              a.trumf == b.trumf,
              a.ønsketKort == b.ønsketKort,
              a.ønsketLagt == b.ønsketLagt,
              a.erAmerikaner == b.erAmerikaner,
              a.erSolo == b.erSolo,
              a.makkerAvslørt == b.makkerAvslørt,
              a.spilteKort == b.spilteKort,
              a.currentTrick == b.currentTrick,
              a.stikkTatt == b.stikkTatt,
              a.trickNummer == b.trickNummer,
              a.aktivSpiller == b.aktivSpiller,
              a.scores == b.scores,
              a.phase == b.phase,
              a.kastet.count == b.kastet.count,
              // Setet vet selv om det er makker; en avslørt makker vet alle.
              (a.makkerSeat == sete) == (b.makkerSeat == sete),
              !a.makkerAvslørt || a.makkerSeat == b.makkerSeat
        else { return false }
        // Budgiveren kjenner sitt eget vrak.
        if a.budgiverSeat == sete, Set(a.kastet) != Set(b.kastet) { return false }
        return true
    }

    /// Reduserte (ikke-likeverdige) kandidater i stikkspillet – testen skal
    /// bare telle stillinger der MesterAI faktisk har noe å velge mellom.
    private func harEktevalg(_ e: GameEngine, sete: Int) -> Bool {
        let lovlige = e.lovligeKort(for: sete)
        guard lovlige.count > 1, let innsikt = Spillinnsikt(engine: e, sete: sete) else { return false }
        let pågåendeMaske = innsikt.pågående.reduce(UInt64(0)) { $0 | (1 << UInt64($1.indeks)) }
        let union = innsikt.ukjente | innsikt.minHånd | pågåendeMaske
        return Spillregler.reduserteTrekk(lovlig: Kortmaske.maske(lovlige), union: union).count > 1
    }

    // MARK: - Selve prøven for kortspill

    private struct Fasit {
        var par = 0
        var avvik = 0
        var eksempler: [String] = []
        var stikkfordeling = [Int](repeating: 0, count: 13)
    }

    /// Kjører invariansprøven på kortvalget med en vilkårlig beslutningsrutine.
    /// `velg` får (motor, sete, frø) og skal være deterministisk gitt frøet.
    private func prøvKortspill(mål: Int, frøStart: UInt64,
                               velg: (GameEngine, Int, UInt64) -> Card?) -> Fasit {
        var fasit = Fasit()
        var rng = SeededGenerator(seed: frøStart)
        var forsøk = 0
        while fasit.par < mål, forsøk < mål * 40 {
            forsøk += 1
            guard let grunn = lagOppsettTilSpill(rng: &rng) else { continue }
            let antallSpilt = trekkSpillengde(rng: &rng)
            guard let o = medSpill(grunn, antall: antallSpilt, rng: &rng),
                  let e = bygg(o, stopp: .spill) else { continue }
            let sete = e.aktivSpiller
            guard harEktevalg(e, sete: sete) else { continue }
            guard let (tvilling, _) = spilltvilling(original: e, oppsett: o, sete: sete, rng: &rng)
            else { continue }

            let frø = UInt64.random(in: 1...UInt64.max, using: &rng)
            let a = velg(e, sete, frø)
            let b = velg(tvilling, sete, frø)
            fasit.par += 1
            fasit.stikkfordeling[min(12, e.trickNummer)] += 1
            if a != b {
                fasit.avvik += 1
                if fasit.eksempler.count < 5 {
                    fasit.eksempler.append(
                        "stikk \(e.trickNummer + 1), sete \(sete): "
                        + "original \(a?.kortSymbol ?? "–") mot tvilling \(b?.kortSymbol ?? "–")")
                }
            }
        }
        return fasit
    }

    // MARK: - 1) Kortspill (den viktigste)

    func testKortvalgErInvariantUnderOmbyttingAvSkjulteKort() {
        let mål = 250 * Self.skala
        let konfig = Self.fastKonfig()
        let fasit = prøvKortspill(mål: mål, frøStart: 0xA11CE) { engine, sete, frø in
            MesterAI(sete: sete, konfig: konfig, seed: frø).velgKort(engine: engine)
        }
        skrivUt("velgKort", fasit)
        XCTAssertGreaterThanOrEqual(fasit.par, mål, "For få gyldige posisjonspar")
        XCTAssertEqual(fasit.avvik, 0,
                       "MesterAI endret kortvalg når bare MOTSTANDERNES skjulte kort ble byttet om – "
                       + "det er lekkasje av skjult informasjon. \(fasit.eksempler.joined(separator: "; "))")
    }

    // MARK: - 2) Budgivning

    func testBudErInvariantUnderOmbyttingAvSkjulteKort() {
        let mål = 150 * Self.skala
        let konfig = Self.fastKonfig()
        var rng = SeededGenerator(seed: 0xB1D)
        var par = 0, avvik = 0
        var eksempler: [String] = []
        var forsøk = 0
        while par < mål, forsøk < mål * 40 {
            forsøk += 1
            let (hender, talon) = del(rng: &rng)
            let førsteBudgiver = Int.random(in: 0..<4, using: &rng)
            guard let full = lagBudhistorikk(hender: hender, talon: talon,
                                             førsteBudgiver: førsteBudgiver, rng: &rng),
                  full.count > 1 else { continue }
            let k = Int.random(in: 0..<full.count, using: &rng)
            var o = Oppsett(hender: hender, talon: talon,
                            førsteBudgiver: førsteBudgiver, bud: Array(full.prefix(k)))
            guard let e = bygg(o, stopp: .budrunde) else { continue }
            let sete = e.aktivBudgiver
            guard e.lovligeBud(for: sete).count > 1 else { continue }

            // Bare de 40 kortene setet ikke ser byttes om; budhistorikken
            // og setets egen hånd står urørt.
            o = stokkUsett(o, sete: sete, frysTalon: false, rng: &rng)
            guard let t = bygg(o, stopp: .budrunde),
                  t.hands[sete] == e.hands[sete], t.bids == e.bids,
                  t.aktivBudgiver == sete, t.scores == e.scores else { continue }

            let frø = UInt64.random(in: 1...UInt64.max, using: &rng)
            let a = MesterAI(sete: sete, konfig: konfig, seed: frø).velgBud(engine: e)
            let b = MesterAI(sete: sete, konfig: konfig, seed: frø).velgBud(engine: t)
            par += 1
            if a != b {
                avvik += 1
                if eksempler.count < 5 {
                    eksempler.append("sete \(sete): \(a.beskrivelse) mot \(b.beskrivelse)")
                }
            }
        }
        print("  velgBud: \(par) posisjonspar, \(avvik) avvik")
        XCTAssertGreaterThanOrEqual(par, mål, "For få gyldige posisjonspar")
        XCTAssertEqual(avvik, 0, "MesterAI endret bud da bare skjulte kort ble byttet om. "
                       + eksempler.joined(separator: "; "))
    }

    // MARK: - 3) Byttekort  4) Trumf og makker

    /// Budgiveren kjenner sin egen hånd, talongen og (i trumffasen) sitt eget
    /// vrak. Alt det fryses; de 36 kortene hos de tre andre byttes om.
    private func prøvBudgiverfase(mål: Int, frøStart: UInt64, stopp: Stopp,
                                  navn: String,
                                  lik: (GameEngine, GameEngine, Int, UInt64, MesterKonfig) -> (Bool, String)) {
        let konfig = Self.fastKonfig()
        var rng = SeededGenerator(seed: frøStart)
        var par = 0, avvik = 0
        var eksempler: [String] = []
        var forsøk = 0
        while par < mål, forsøk < mål * 40 {
            forsøk += 1
            guard var o = lagOppsettTilSpill(rng: &rng),
                  let e = bygg(o, stopp: stopp), let sete = e.budgiverSeat else { continue }
            o = stokkUsett(o, sete: sete, frysTalon: true, rng: &rng)
            guard let t = bygg(o, stopp: stopp),
                  t.hands[sete] == e.hands[sete], t.bids == e.bids,
                  Set(t.kastet) == Set(e.kastet), t.phase == e.phase else { continue }

            let frø = UInt64.random(in: 1...UInt64.max, using: &rng)
            let (identisk, beskrivelse) = lik(e, t, sete, frø, konfig)
            par += 1
            if !identisk {
                avvik += 1
                if eksempler.count < 5 { eksempler.append("sete \(sete): \(beskrivelse)") }
            }
        }
        print("  \(navn): \(par) posisjonspar, \(avvik) avvik")
        XCTAssertGreaterThanOrEqual(par, mål, "For få gyldige posisjonspar (\(navn))")
        XCTAssertEqual(avvik, 0, "MesterAI endret \(navn) da bare skjulte kort ble byttet om. "
                       + eksempler.joined(separator: "; "))
    }

    func testByttekortErInvariantUnderOmbyttingAvSkjulteKort() {
        prøvBudgiverfase(mål: 120 * Self.skala, frøStart: 0xB1770, stopp: .byttekort,
                         navn: "velgByttekort") { e, t, sete, frø, konfig in
            let a = MesterAI(sete: sete, konfig: konfig, seed: frø).velgByttekort(engine: e)
            let b = MesterAI(sete: sete, konfig: konfig, seed: frø).velgByttekort(engine: t)
            let likt = Set(a) == Set(b)
            return (likt, "\(a.map(\.kortSymbol).joined(separator: " ")) mot "
                    + "\(b.map(\.kortSymbol).joined(separator: " "))")
        }
    }

    func testTrumfOgMakkerErInvariantUnderOmbyttingAvSkjulteKort() {
        prøvBudgiverfase(mål: 120 * Self.skala, frøStart: 0x7F00, stopp: .velgTrumf,
                         navn: "velgTrumfOgMakker") { e, t, sete, frø, konfig in
            let a = MesterAI(sete: sete, konfig: konfig, seed: frø).velgTrumfOgMakker(engine: e)
            let b = MesterAI(sete: sete, konfig: konfig, seed: frø).velgTrumfOgMakker(engine: t)
            let likt = a?.0 == b?.0 && a?.1 == b?.1
            func vis(_ v: (Suit, Card?)?) -> String {
                guard let v else { return "–" }
                return "\(v.0.rawValue)/\(v.1?.kortSymbol ?? "ingen")"
            }
            return (likt, "\(vis(a)) mot \(vis(b))")
        }
    }

    // MARK: - 5) Positiv kontroll

    /// Uten en kontroll som FEILER er invariansprøven verdiløs. Her kjøres
    /// samme prøve på tre spillere:
    ///  * `Referansesøker(juks: false)` – lovlig, skal gi 0 avvik,
    ///  * `Referansesøker(juks: true)`  – én liten lekkasje, skal fanges,
    ///  * `Fasitspiller`                – grov juks, skal fanges.
    func testPositivKontrollFangerJuks() {
        let mål = 120 * Self.skala

        let lovlig = prøvKortspill(mål: mål, frøStart: 0xC0DE) { engine, sete, frø in
            var s = Referansesøker(sete: sete, juks: false, verdener: 12,
                                   rng: SeededGenerator(seed: frø))
            return s.velgKort(engine: engine)
        }
        skrivUt("Referansesøker(juks: false)", lovlig)
        XCTAssertGreaterThanOrEqual(lovlig.par, mål)
        XCTAssertEqual(lovlig.avvik, 0,
                       "Negativ kontroll feilet: en beviselig LOVLIG søker ble flagget. "
                       + "Da er tvillingene ikke lovlige, og hele prøven er ugyldig. "
                       + lovlig.eksempler.joined(separator: "; "))

        let subtil = prøvKortspill(mål: mål, frøStart: 0xC0DE) { engine, sete, frø in
            var s = Referansesøker(sete: sete, juks: true, verdener: 12,
                                   rng: SeededGenerator(seed: frø))
            return s.velgKort(engine: engine)
        }
        skrivUt("Referansesøker(juks: true)", subtil)
        XCTAssertGreaterThan(subtil.avvik, 0,
                             "Prøven fanget ikke den subtile juksevarianten – da beviser den ingenting.")

        let grov = prøvKortspill(mål: mål, frøStart: 0xC0DE) { engine, sete, _ in
            Fasitspiller(sete: sete).velgKort(engine: engine)
        }
        skrivUt("Fasitspiller (dobbeltdummy på ekte hender)", grov)
        XCTAssertGreaterThan(grov.avvik, 0,
                             "Prøven fanget ikke engang en spiller som ser alle kortene.")
    }

    // MARK: - 6) Selvtest av tvillingmaskineriet

    /// Tvillingene må være ekte tvillinger: en annen skjult verden, men et
    /// identisk informasjonssett. Testen sjekker begge deler eksplisitt.
    func testTvillingeneErForskjelligeMenInformasjonsmessigIdentiske() {
        var rng = SeededGenerator(seed: 0x7411)
        var par = 0, medEndretVrak = 0, medEndretMakkersete = 0, uavslørt = 0
        var forsøk = 0
        while par < 60, forsøk < 3000 {
            forsøk += 1
            guard let grunn = lagOppsettTilSpill(rng: &rng) else { continue }
            let antallSpilt = trekkSpillengde(rng: &rng)
            guard let o = medSpill(grunn, antall: antallSpilt, rng: &rng),
                  let e = bygg(o, stopp: .spill) else { continue }
            let sete = e.aktivSpiller
            guard harEktevalg(e, sete: sete),
                  let (t, _) = spilltvilling(original: e, oppsett: o, sete: sete, rng: &rng)
            else { continue }
            par += 1
            if !e.ønsketLagt { uavslørt += 1 }

            XCTAssertTrue(erOffentligIdentiske(e, t, sete: sete))
            // Minst ett annet sete må ha fått andre kort.
            let endret = (0..<4).contains { $0 != sete && Set(t.hands[$0]) != Set(e.hands[$0]) }
            XCTAssertTrue(endret || Set(t.kastet) != Set(e.kastet),
                          "Tvillingen var identisk med originalen – prøven ville vært innholdsløs")
            if Set(t.kastet) != Set(e.kastet) { medEndretVrak += 1 }
            if t.makkerSeat != e.makkerSeat { medEndretMakkersete += 1 }
            // Informasjonssettet MesterAI faktisk leser må være identisk.
            guard let ia = Spillinnsikt(engine: e, sete: sete),
                  let ib = Spillinnsikt(engine: t, sete: sete) else { return XCTFail("Spillinnsikt manglet") }
            XCTAssertEqual(ia.minHånd, ib.minHånd)
            XCTAssertEqual(ia.ukjente, ib.ukjente)
            XCTAssertEqual(ia.antallKort, ib.antallKort)
            XCTAssertEqual(ia.antallDødeUkjente, ib.antallDødeUkjente)
            XCTAssertEqual(ia.forbudt, ib.forbudt)
            XCTAssertEqual(ia.spiltAvSete, ib.spiltAvSete)
            XCTAssertEqual(ia.ønsketIndeks, ib.ønsketIndeks)
            XCTAssertEqual(ia.ønsketKandidater, ib.ønsketKandidater)
            XCTAssertEqual(ia.pliktkort, ib.pliktkort)
            XCTAssertEqual(ia.kjentMakker, ib.kjentMakker)
            XCTAssertEqual(ia.jegErBudgiverlag, ib.jegErBudgiverlag)
            XCTAssertEqual(ia.stikkTatt, ib.stikkTatt)
            XCTAssertEqual(ia.poengNå, ib.poengNå)
        }
        print("  tvillinger: \(par) par, \(medEndretVrak) med annet vrak, "
              + "\(uavslørt) med uavslørt makker, \(medEndretMakkersete) med annet makkersete")
        XCTAssertGreaterThanOrEqual(par, 60)
        XCTAssertGreaterThan(medEndretMakkersete, 0,
                             "Ingen tvilling flyttet den skjulte makkeren – prøven er for svak")
    }

    // MARK: - Utskrift

    private func skrivUt(_ navn: String, _ f: Fasit) {
        let fordeling = f.stikkfordeling.enumerated()
            .filter { $0.element > 0 }
            .map { "s\($0.offset + 1):\($0.element)" }
            .joined(separator: " ")
        print("  \(navn): \(f.par) posisjonspar, \(f.avvik) avvik  [\(fordeling)]")
        for e in f.eksempler { print("      \(e)") }
    }
}

// MARK: - Kontrollspillere

/// Søker med nøyaktig samme informasjonsgrunnlag som MesterAI – `Spillinnsikt`
/// og `sampleVerden` – men med én bryter. Med `juks = true` forkastes verdener
/// som ikke plasserer ett bestemt skjult kort der det VIRKELIG ligger. Det er
/// en liten lekkasje, og nettopp derfor en god prøve på om testen biter.
struct Referansesøker {
    let sete: Int
    let juks: Bool
    let verdener: Int
    var rng: SeededGenerator

    mutating func velgKort(engine: GameEngine) -> Card? {
        let lovlige = engine.lovligeKort(for: sete)
        guard lovlige.count > 1, let innsikt = Spillinnsikt(engine: engine, sete: sete)
        else { return lovlige.first }

        let pågåendeMaske = innsikt.pågående.reduce(UInt64(0)) { $0 | (1 << UInt64($1.indeks)) }
        let union = innsikt.ukjente | innsikt.minHånd | pågåendeMaske
        let kandidater = Spillregler.reduserteTrekk(lovlig: Kortmaske.maske(lovlige), union: union)
        guard kandidater.count > 1 else { return kandidater.first.map(Kortmaske.kort) }

        // Lekkasjen: det høyeste ukjente kortet, og setet som FAKTISK har det.
        var fasitSete: Int?
        var fasitBit: UInt64 = 0
        if juks {
            for idx in Kortmaske.indekser(innsikt.ukjente).reversed() {
                let bit: UInt64 = 1 << UInt64(idx)
                if let eier = (0..<4).first(where: { Kortmaske.maske(engine.hands[$0]) & bit != 0 }) {
                    fasitSete = eier
                    fasitBit = bit
                    break
                }
            }
        }

        var sum = [Double](repeating: 0, count: kandidater.count)
        var talt = 0
        var forsøk = 0
        while talt < verdener, forsøk < verdener * 80 {
            forsøk += 1
            guard let verden = innsikt.sampleVerden(rng: &rng) else { break }
            if let fasitSete, verden.hender[fasitSete] & fasitBit == 0 { continue }
            let dd = Dobbeltdummy()
            for (i, kandidat) in kandidater.enumerated() {
                sum[i] += Referansesøker.evaluer(kandidat: kandidat, verden: verden,
                                                 innsikt: innsikt, dd: dd)
            }
            talt += 1
        }
        guard talt > 0 else { return lovlige.first }
        return Referansesøker.beste(kandidater, sum, trumfFarge: innsikt.trumfFarge)
    }

    static func evaluer(kandidat: Int, verden: Verden, innsikt: Spillinnsikt,
                        dd: Dobbeltdummy) -> Double {
        var t = Spilltilstand(
            hender: verden.hender, leder: innsikt.leder, pågående: innsikt.pågående,
            trumfFarge: innsikt.trumfFarge, lagMaske: verden.lagMaske,
            budgiver: innsikt.budgiver, pliktkort: innsikt.pliktkort,
            førsteStikk: innsikt.trickNummer == 0
        )
        var perSete = [0, 0, 0, 0]
        if let vinner = Spillregler.utfør(&t, indeks: kandidat) { perSete[vinner] += 1 }
        t = GrådigSpiller.spillUt(t, stoppVedStikkIgjen: 6, perSete: &perSete)
        var lagStikk = Double(dd.løs(t))
        for s in 0..<4 where verden.lagMaske & (1 << UInt8(s)) != 0 {
            lagStikk += Double(perSete[s])
        }
        let påLaget = verden.lagMaske & (1 << UInt8(innsikt.sete)) != 0
        return påLaget ? lagStikk : -lagStikk
    }

    static func beste(_ kandidater: [Int], _ sum: [Double], trumfFarge: Int?) -> Card {
        var besteIndeks = kandidater[0]
        var besteSum = sum[0]
        for (i, kandidat) in kandidater.enumerated().dropFirst() {
            let bedre = sum[i] > besteSum + 1e-9
            let liktMenBilligere = abs(sum[i] - besteSum) <= 1e-9
                && Kortmaske.kostnad(kandidat, trumfFarge: trumfFarge)
                    < Kortmaske.kostnad(besteIndeks, trumfFarge: trumfFarge)
            if bedre || liktMenBilligere {
                besteIndeks = kandidat
                besteSum = sum[i]
            }
        }
        return Kortmaske.kort(besteIndeks)
    }
}

/// Grov juks: løser stillingen dobbeltdummy på de EKTE hendene til alle fire.
struct Fasitspiller {
    let sete: Int

    func velgKort(engine: GameEngine) -> Card? {
        let lovlige = engine.lovligeKort(for: sete)
        guard lovlige.count > 1, let innsikt = Spillinnsikt(engine: engine, sete: sete),
              let budgiver = engine.budgiverSeat else { return lovlige.first }

        let pågåendeMaske = innsikt.pågående.reduce(UInt64(0)) { $0 | (1 << UInt64($1.indeks)) }
        let union = innsikt.ukjente | innsikt.minHånd | pågåendeMaske
        let kandidater = Spillregler.reduserteTrekk(lovlig: Kortmaske.maske(lovlige), union: union)
        guard kandidater.count > 1 else { return kandidater.first.map(Kortmaske.kort) }

        var hender = SIMD4<UInt64>(repeating: 0)
        for s in 0..<4 { hender[s] = Kortmaske.maske(engine.hands[s]) }
        var lagMaske: UInt8 = 1 << UInt8(budgiver)
        if !engine.erSolo, let makker = engine.makkerSeat { lagMaske |= 1 << UInt8(makker) }
        let verden = Verden(hender: hender, makker: engine.makkerSeat, lagMaske: lagMaske)

        let dd = Dobbeltdummy()
        var sum = [Double](repeating: 0, count: kandidater.count)
        for (i, kandidat) in kandidater.enumerated() {
            sum[i] = Referansesøker.evaluer(kandidat: kandidat, verden: verden,
                                            innsikt: innsikt, dd: dd)
        }
        return Referansesøker.beste(kandidater, sum, trumfFarge: innsikt.trumfFarge)
    }
}
