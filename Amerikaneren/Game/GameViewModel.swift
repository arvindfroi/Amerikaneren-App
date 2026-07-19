import Foundation
import SwiftUI

/// Kobler GameEngine til UI-et og driver AI-spillerne med små pauser,
/// så partiet føles som et ekte bord. Mennesket sitter alltid på sete 0.
@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var oppdatering = 0   // bumpes for å tegne på nytt
    @Published var visRundeOppsummering = false
    @Published var visSpillFerdig = false
    @Published var sisteReplikk: (navn: String, tekst: String)? {
        didSet {
            // Replikker forsvinner av seg selv, så bordet ikke gror igjen.
            guard sisteReplikk != nil else { return }
            replikkOppgave?.cancel()
            replikkOppgave = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                self?.sisteReplikk = nil
            }
        }
    }
    /// «X tok stikket»-banner, vises et øyeblikk mellom stikkene.
    @Published var stikkBanner: String?

    private var replikkOppgave: Task<Void, Never>?
    private var bannerOppgave: Task<Void, Never>?
    private var varMinTur = false

    let engine: GameEngine
    let motstandere: [Opponent]           // sete 1..3
    let stage: CampaignStage?
    let spillerNavn: String
    private var aiSpillere: [Int: AIPlayer] = [:]
    private var aiOppgave: Task<Void, Never>?
    private let startTid = Date()
    private var harVunnetKravBud = false  // for kampanjescenarioer med budkrav
    private var rundeopptak: [Rundeopptak] = []   // treningsdata (kun med samtykke)
    private var partiLevert = false

    var mode: MatchMode { stage == nil ? .offline : .kampanje }

    init(motstandere: [Opponent], spillerNavn: String, stage: CampaignStage? = nil) {
        self.motstandere = motstandere
        self.spillerNavn = spillerNavn
        self.stage = stage
        var rules = GameRules()
        if let stage { rules.målPoeng = stage.målPoeng }
        self.engine = GameEngine(rules: rules)
        for (i, motstander) in motstandere.enumerated() {
            aiSpillere[i + 1] = AIPlayer(seat: i + 1, difficulty: motstander.difficulty, personality: motstander.personality)
        }
    }

    func navn(for seat: Int) -> String {
        seat == 0 ? spillerNavn : motstandere[seat - 1].navn
    }

    func opponent(for seat: Int) -> Opponent? {
        seat == 0 ? nil : motstandere[seat - 1]
    }

    // MARK: - Spillflyt

    func startSpill() {
        engine.startRunde()
        // Scenario-forsprang legges inn som en «historisk» runde 0-justering.
        if let stage, engine.rundeResultater.isEmpty {
            påførStartpoeng(stage)
        }
        if let hoved = motstandere.first, stage != nil {
            sisteReplikk = (hoved.navn, hoved.introReplikk)
        }
        bump()
        kjørAI()
    }

    private var startJustering: [Int] = [0, 0, 0, 0]
    private func påførStartpoeng(_ stage: CampaignStage) {
        startJustering = [stage.spillerStartPoeng, stage.motstanderStartPoeng, 0, 0]
    }

    /// Poengsum inkludert scenario-forsprang.
    func poeng(for seat: Int) -> Int {
        engine.scores[seat] + startJustering[seat]
    }

    private var scenarioVinner: Int? {
        let mål = engine.rules.målPoeng
        let kandidater = (0..<4).filter { poeng(for: $0) >= mål }
        guard !kandidater.isEmpty else { return nil }
        return kandidater.max { poeng(for: $0) < poeng(for: $1) }
    }

    func bump() { oppdatering += 1 }

    // MARK: - Menneskets handlinger

    func menneskeByr(_ bud: BidAction) {
        guard engine.giBud(seat: 0, action: bud) else { return }
        varMinTur = false
        bud == .amerikaner || bud == .soloAmerikaner ? Feedback.amerikanerMeldt() : Feedback.budGitt()
        bump()
        kjørAI()
    }

    func menneskeVelgerTrumf(suit: Suit, ønsket: Card?) {
        guard engine.velgTrumf(suit: suit, ønsket: ønsket) else { return }
        Feedback.budGitt()
        bump()
        kjørAI()
    }

    func menneskeVraker(_ kort: [Card]) {
        guard engine.kastByttekort(kort, seat: 0) else { return }
        Feedback.kortSpilt()
        bump()
        kjørAI()
    }

    func menneskeSpiller(_ kort: Card) {
        let førTrick = engine.trickNummer
        guard engine.spill(kort: kort, seat: 0) else { return }
        varMinTur = false
        Feedback.kortSpilt()
        etterKortSpilt(førTrick: førTrick)
        etterTrekk()
        bump()
        kjørAI()
    }

    /// Banner + haptikk når et stikk nettopp ble avgjort.
    private func etterKortSpilt(førTrick: Int) {
        guard engine.trickNummer > førTrick, let vinner = engine.sisteStikkVinner else { return }
        Feedback.stikkAvgjort(mitt: vinner == 0)
        stikkBanner = vinner == 0 ? "Du tok stikket!" : "\(navn(for: vinner)) tok stikket"
        bannerOppgave?.cancel()
        bannerOppgave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.stikkBanner = nil
        }
    }

    /// Diskret varsel når turen kommer til mennesket.
    private func sjekkDinTur() {
        let minTur = (engine.phase == .spill && engine.aktivSpiller == 0)
            || (engine.phase == .budrunde && engine.aktivBudgiver == 0)
            || (engine.phase == .byttekort && engine.budgiverSeat == 0)
            || (engine.phase == .velgTrumf && engine.budgiverSeat == 0)
        if minTur && !varMinTur { Feedback.dinTur() }
        varMinTur = minTur
    }

    // MARK: - AI-motor

    private func kjørAI() {
        aiOppgave?.cancel()
        aiOppgave = Task { [weak self] in
            await self?.aiLøkke()
        }
    }

    private func aiLøkke() async {
        while !Task.isCancelled {
            switch engine.phase {
            case .budrunde:
                let seat = engine.aktivBudgiver
                guard seat != 0, let ai = aiSpillere[seat] else { sjekkDinTur(); return }
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                let bud = ai.velgBud(engine: engine)
                if bud == .amerikaner {
                    sisteReplikk = (navn(for: seat), "AMERIKANER! Vi tar alle stikkene!")
                    Feedback.amerikanerMeldt()
                } else if bud == .soloAmerikaner {
                    sisteReplikk = (navn(for: seat), "SOLO-AMERIKANER! Jeg tar alle stikkene HELT alene!")
                    Feedback.amerikanerMeldt()
                }
                engine.giBud(seat: seat, action: bud)
                sjekkDinTur()
                bump()

            case .byttekort:
                guard let seat = engine.budgiverSeat, seat != 0, let ai = aiSpillere[seat] else { sjekkDinTur(); return }
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                let vrak = ai.velgByttekort(engine: engine)
                if !engine.kastByttekort(vrak, seat: seat) {
                    // Sikkerhetsnett: kast de fire første kortene om AI-en feiler.
                    let nødvrak = Array(engine.hands[seat].prefix(engine.rules.antallByttekort))
                    engine.kastByttekort(nødvrak, seat: seat)
                }
                sisteReplikk = (navn(for: seat), "Jeg tar talongen og bytter ut fire kort.")
                sjekkDinTur()
                bump()

            case .velgTrumf:
                guard let seat = engine.budgiverSeat, seat != 0, let ai = aiSpillere[seat] else { sjekkDinTur(); return }
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                if let (suit, ønsket) = ai.velgTrumfOgMakker(engine: engine),
                   engine.velgTrumf(suit: suit, ønsket: ønsket) {
                    sisteReplikk = (navn(for: seat), ønsket.map {
                        "\(suit.navn) er trumf. Jeg vil ha \($0.beskrivelse.lowercased())!"
                    } ?? "\(suit.navn) er trumf – og jeg klarer meg helt selv!")
                } else {
                    // Sikkerhetsnett: velg første mulige trumf og etterlysning.
                    for suit in Suit.allCases {
                        if let ønsket = engine.kortSomKanØnskes(trumf: suit).first,
                           engine.velgTrumf(suit: suit, ønsket: ønsket) { break }
                        if engine.erSolo, engine.velgTrumf(suit: suit, ønsket: nil) { break }
                    }
                }
                sjekkDinTur()
                bump()

            case .spill:
                let seat = engine.aktivSpiller
                guard seat != 0, let ai = aiSpillere[seat] else { sjekkDinTur(); return }
                // Lengre pause i starten av et nytt stikk, så alle rekker
                // å se det forrige stikket og banneret.
                let nyttStikk = engine.currentTrick.isEmpty && engine.trickNummer > 0
                try? await Task.sleep(nanoseconds: nyttStikk ? 1_400_000_000
                                      : engine.currentTrick.isEmpty ? 800_000_000 : 550_000_000)
                guard !Task.isCancelled else { return }
                if let kort = ai.velgKort(engine: engine) {
                    let førTrick = engine.trickNummer
                    engine.spill(kort: kort, seat: seat)
                    Feedback.kortSpilt()
                    etterKortSpilt(førTrick: førTrick)
                    etterTrekk()
                }
                sjekkDinTur()
                bump()

            case .rundeFerdig, .spillFerdig, .venterPåStart:
                return
            }
        }
    }

    private func etterTrekk() {
        if engine.phase == .rundeFerdig || engine.phase == .spillFerdig {
            håndterRundeSlutt()
        }
    }

    private func håndterRundeSlutt() {
        if let opptak = Rundeopptak(fra: engine) {
            rundeopptak.append(opptak)
        }
        if let runde = engine.sisteRunde, runde.budgiver == 0, runde.klarte,
           case .bud(let n) = runde.bud, let krav = stage?.kravMinsteBud, n >= krav {
            harVunnetKravBud = true
        }
        // Scenario-forsprang kan avgjøre partiet selv om motoren ikke ser det.
        if engine.phase == .rundeFerdig, scenarioVinner != nil {
            visSpillFerdig = true
            replikkVedSlutt()
            Feedback.spillSlutt(vant: jegVant)
            leverTreningsdata()
            return
        }
        if engine.phase == .spillFerdig {
            visSpillFerdig = true
            replikkVedSlutt()
            Feedback.spillSlutt(vant: jegVant)
            leverTreningsdata()
        } else {
            visRundeOppsummering = true
            if let runde = engine.sisteRunde {
                Feedback.rundeSlutt(bra: runde.poengEndring[0] >= 0)
            }
        }
    }

    /// Leverer partiets rundeopptak til innsamlingen ved partislutt.
    /// Innsamleren gjør ingenting uten samtykke, og opptakene er anonyme:
    /// bare kort, bud og CPU-nivåer – aldri navn.
    private func leverTreningsdata() {
        guard !partiLevert, !rundeopptak.isEmpty else { return }
        partiLevert = true
        let seter = [Seteinfo(menneske: true, cpuNivå: nil)]
            + motstandere.map { Seteinfo(menneske: false, cpuNivå: $0.difficulty.rawValue) }
        let parti = Partiopptak(
            regler: engine.rules,
            modus: mode == .kampanje ? "kampanje" : "offline",
            seter: seter,
            runder: rundeopptak,
            sluttPoeng: (0..<4).map { poeng(for: $0) },
            vinner: vinnerSeat
        )
        Innsamler.standard.leverParti(parti)
    }

    private func replikkVedSlutt() {
        guard let hoved = motstandere.first else { return }
        sisteReplikk = jegVant
            ? (hoved.navn, hoved.tapReplikk)
            : (hoved.navn, hoved.seierReplikk)
    }

    func nesteRunde() {
        visRundeOppsummering = false
        engine.nesteRunde()
        bump()
        kjørAI()
    }

    // MARK: - Resultat

    var vinnerSeat: Int? {
        scenarioVinner ?? engine.vinnerSeat
    }

    var jegVant: Bool { vinnerSeat == 0 }

    /// Kampanjekrav: vant partiet OG oppfylte eventuelt budkrav.
    var kampanjeBestått: Bool {
        guard jegVant else { return false }
        if let krav = stage?.kravMinsteBud { return harVunnetKravBud || harKlartBudIHistorikk(krav) }
        return true
    }

    private func harKlartBudIHistorikk(_ krav: Int) -> Bool {
        engine.rundeResultater.contains { runde in
            if runde.budgiver == 0, runde.klarte, case .bud(let n) = runde.bud { return n >= krav }
            return false
        }
    }

    func lagMatchRecord() -> MatchRecord {
        let ider = ["meg"] + motstandere.map(\.id)
        let navnListe = [spillerNavn] + motstandere.map(\.navn)
        let vinner = vinnerSeat
        let deltakere = (0..<4).map { s in
            MatchParticipant(
                id: ider[s], navn: navnListe[s], erMeg: s == 0,
                opponentId: s == 0 ? nil : motstandere[s - 1].id,
                sluttPoeng: poeng(for: s), vantPartiet: s == vinner
            )
        }
        let runder = engine.rundeResultater.map { runde in
            RoundRecord(
                budgiverId: ider[runde.budgiver],
                makkerId: runde.makker.map { ider[$0] },
                bud: runde.bud.rang,
                trumf: runde.trumf?.navn,
                klarte: runde.klarte,
                stikk: Dictionary(uniqueKeysWithValues: zip(ider, runde.stikkPerSpiller)),
                poengEndring: Dictionary(uniqueKeysWithValues: zip(ider, runde.poengEndring))
            )
        }
        return MatchRecord(
            mode: mode, deltakere: deltakere, runder: runder,
            varighetSekunder: Int(Date().timeIntervalSince(startTid)),
            kampanjeStageId: stage?.id
        )
    }

    deinit {
        aiOppgave?.cancel()
        replikkOppgave?.cancel()
        bannerOppgave?.cancel()
    }
}
