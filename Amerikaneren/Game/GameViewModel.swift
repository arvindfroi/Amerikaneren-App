import Foundation
import SwiftUI

/// Kobler GameEngine til UI-et og driver AI-spillerne med små pauser,
/// så partiet føles som et ekte bord. Mennesket sitter alltid på sete 0.
@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var oppdatering = 0   // bumpes for å tegne på nytt
    @Published var visRundeOppsummering = false
    @Published var visSpillFerdig = false
    @Published var sisteReplikk: (navn: String, tekst: String)?

    let engine: GameEngine
    let motstandere: [Opponent]           // sete 1..3
    let stage: CampaignStage?
    let spillerNavn: String
    private var aiSpillere: [Int: AIPlayer] = [:]
    private var aiOppgave: Task<Void, Never>?
    private let startTid = Date()
    private var harVunnetKravBud = false  // for kampanjescenarioer med budkrav

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
        bump()
        kjørAI()
    }

    func menneskeVelgerTrumf(suit: Suit, ønsket: Card) {
        guard engine.velgTrumf(suit: suit, ønsket: ønsket) else { return }
        bump()
        kjørAI()
    }

    func menneskeSpiller(_ kort: Card) {
        guard engine.spill(kort: kort, seat: 0) else { return }
        etterTrekk()
        bump()
        kjørAI()
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
                guard seat != 0, let ai = aiSpillere[seat] else { return }
                try? await Task.sleep(nanoseconds: 700_000_000)
                let bud = ai.velgBud(engine: engine)
                if bud == .amerikaner {
                    sisteReplikk = (navn(for: seat), "AMERIKANER! Jeg tar alle tretten alene!")
                }
                engine.giBud(seat: seat, action: bud)
                bump()

            case .velgTrumf:
                guard let seat = engine.budgiverSeat, seat != 0, let ai = aiSpillere[seat] else { return }
                try? await Task.sleep(nanoseconds: 900_000_000)
                if let (suit, ønsket) = ai.velgTrumfOgMakker(engine: engine) {
                    engine.velgTrumf(suit: suit, ønsket: ønsket)
                    sisteReplikk = (navn(for: seat), "\(suit.navn) er trumf. Jeg vil ha \(ønsket.beskrivelse.lowercased())!")
                }
                bump()

            case .spill:
                let seat = engine.aktivSpiller
                guard seat != 0, let ai = aiSpillere[seat] else { return }
                try? await Task.sleep(nanoseconds: engine.currentTrick.isEmpty ? 800_000_000 : 550_000_000)
                if let kort = ai.velgKort(engine: engine) {
                    engine.spill(kort: kort, seat: seat)
                    etterTrekk()
                }
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
        if let runde = engine.sisteRunde, runde.budgiver == 0, runde.klarte,
           case .bud(let n) = runde.bud, let krav = stage?.kravMinsteBud, n >= krav {
            harVunnetKravBud = true
        }
        // Scenario-forsprang kan avgjøre partiet selv om motoren ikke ser det.
        if engine.phase == .rundeFerdig, scenarioVinner != nil {
            visSpillFerdig = true
            replikkVedSlutt()
            return
        }
        if engine.phase == .spillFerdig {
            visSpillFerdig = true
            replikkVedSlutt()
        } else {
            visRundeOppsummering = true
        }
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
    }
}
