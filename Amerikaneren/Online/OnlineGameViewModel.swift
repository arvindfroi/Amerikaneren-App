import Foundation
import GameKit
import SwiftUI

/// Driver et online-parti. Verten eier `GameEngine` og er eneste autoritet;
/// klienter speiler personaliserte øyeblikksbilder og sender handlinger.
/// Tomme seter fylles med CPU-er, og spillere som faller fra erstattes av
/// CPU-er slik at partiet alltid kan fullføres.
@MainActor
final class OnlineGameViewModel: ObservableObject {
    @Published var spillAktivt = false
    @Published var setup: OnlineSetup?
    @Published var snap: OnlineSnapshot?
    @Published var infoTekst: String?
    @Published var statsLagret = false

    private let gc = GameCenterManager.delt

    // Kun verten:
    private var engine: GameEngine?
    private var aiSeter: [Int: AIPlayer] = [:]
    private var seteTilRemote: [Int: GKPlayer] = [:]
    private var seatNavn: [String] = []
    private var seatIdentitet: [String] = []
    private var aiOppgave: Task<Void, Never>?

    var erVert: Bool { gc.erVert }
    var mittSete: Int { setup?.dittSete ?? 0 }

    func kobleTil() {
        gc.onMessage = { [weak self] melding, fra in
            self?.håndter(melding, fra: fra)
        }
        gc.onPlayerDisconnected = { [weak self] spiller in
            self?.spillerKobletFra(spiller)
        }
    }

    // MARK: - Vert: oppstart

    /// Verten setter opp bordet: mennesker sorteres deterministisk på
    /// gamePlayerID, resten av setene fylles med CPU-er på Middels.
    func startSomVert() {
        guard let match = gc.match, erVert else { return }
        let motor = GameEngine()
        engine = motor

        let mennesker: [(id: String, navn: String, spiller: GKPlayer?)] =
            ([(gc.lokalID, gc.lokaltNavn, GKPlayer?.none)]
             + match.players.map { ($0.gamePlayerID, $0.displayName, GKPlayer?.some($0)) })
            .sorted { $0.0 < $1.0 }
            .map { (id: $0.0, navn: $0.1, spiller: $0.2) }

        seatNavn = []
        seatIdentitet = []
        seteTilRemote = [:]
        aiSeter = [:]

        for (sete, menneske) in mennesker.enumerated() {
            seatNavn.append(menneske.navn)
            seatIdentitet.append("gc:\(menneske.id)")
            if let spiller = menneske.spiller {
                seteTilRemote[sete] = spiller
            }
        }
        // Fyll resten av bordet med CPU-er.
        let utfyllere = OpponentRoster.tilfeldigBord(difficulty: .middels)
        var neste = 0
        while seatNavn.count < 4 {
            let sete = seatNavn.count
            let cpu = utfyllere[neste]
            neste += 1
            seatNavn.append("\(cpu.navn) 🤖")
            seatIdentitet.append("ai:\(cpu.id)")
            aiSeter[sete] = AIPlayer(seat: sete, difficulty: cpu.difficulty, personality: cpu.personality)
        }

        // Send personlig setup til hver spiller.
        for (sete, spiller) in seteTilRemote {
            gc.send(.setup(OnlineSetup(
                seatNavn: seatNavn, seatIdentitet: seatIdentitet,
                dittSete: sete, målPoeng: motor.rules.målPoeng
            )), til: [spiller])
        }
        let mittSete = seatIdentitet.firstIndex(of: "gc:\(gc.lokalID)") ?? 0
        setup = OnlineSetup(seatNavn: seatNavn, seatIdentitet: seatIdentitet,
                            dittSete: mittSete, målPoeng: motor.rules.målPoeng)

        motor.startRunde()
        spillAktivt = true
        kringkast()
        kjørAI()
    }

    // MARK: - Meldinger inn

    private func håndter(_ melding: OnlineMessage, fra spiller: GKPlayer) {
        switch melding {
        case .setup(let s):
            guard !erVert else { return }
            setup = s
            spillAktivt = true

        case .snapshot(let s):
            guard !erVert else { return }
            snap = s
            if s.phase == .spillFerdig { infoTekst = nil }

        case .action(let handling):
            guard erVert,
                  let sete = seteTilRemote.first(where: { $0.value.gamePlayerID == spiller.gamePlayerID })?.key
            else { return }
            utfør(handling, sete: sete)
        }
    }

    /// Vertens motor validerer alle handlinger – ulovlige forkastes stille.
    private func utfør(_ handling: OnlineAction, sete: Int) {
        guard let engine else { return }
        switch handling {
        case .bud(let bud):
            engine.giBud(seat: sete, action: bud)
        case .trumf(let suit, let kort):
            guard engine.budgiverSeat == sete else { return }
            engine.velgTrumf(suit: suit, ønsket: kort)
        case .kort(let kort):
            engine.spill(kort: kort, seat: sete)
        }
        kringkast()
        kjørAI()
    }

    // MARK: - Lokale handlinger (begge roller)

    func byr(_ bud: BidAction) { lokalHandling(.bud(bud)) }
    func velgerTrumf(suit: Suit, kort: Card) { lokalHandling(.trumf(suit, kort)) }
    func spiller(_ kort: Card) { lokalHandling(.kort(kort)) }

    private func lokalHandling(_ handling: OnlineAction) {
        if erVert {
            utfør(handling, sete: mittSete)
        } else {
            gc.send(.action(handling))
        }
    }

    /// Kun verten går videre til neste runde.
    func nesteRunde() {
        guard erVert, let engine, engine.phase == .rundeFerdig else { return }
        engine.nesteRunde()
        kringkast()
        kjørAI()
    }

    // MARK: - Vert: AI og kringkasting

    private func kjørAI() {
        guard erVert else { return }
        aiOppgave?.cancel()
        aiOppgave = Task { [weak self] in
            await self?.aiLøkke()
        }
    }

    private func aiLøkke() async {
        while !Task.isCancelled, let engine {
            let sete: Int
            switch engine.phase {
            case .budrunde: sete = engine.aktivBudgiver
            case .velgTrumf: sete = engine.budgiverSeat ?? 0
            case .spill: sete = engine.aktivSpiller
            default: return
            }
            guard let ai = aiSeter[sete] else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }

            switch engine.phase {
            case .budrunde:
                engine.giBud(seat: sete, action: ai.velgBud(engine: engine))
            case .velgTrumf:
                if let (suit, kort) = ai.velgTrumfOgMakker(engine: engine) {
                    engine.velgTrumf(suit: suit, ønsket: kort)
                }
            case .spill:
                if let kort = ai.velgKort(engine: engine) {
                    engine.spill(kort: kort, seat: sete)
                }
            default:
                return
            }
            kringkast()
        }
    }

    /// Bygger og distribuerer personaliserte øyeblikksbilder: hver spiller
    /// får kun sin egen hånd og sine egne lovlige trekk.
    private func kringkast() {
        guard erVert, let engine else { return }
        for (sete, spiller) in seteTilRemote {
            gc.send(.snapshot(bilde(for: sete, engine: engine)), til: [spiller])
        }
        snap = bilde(for: mittSete, engine: engine)
    }

    private func bilde(for sete: Int, engine: GameEngine) -> OnlineSnapshot {
        OnlineSnapshot(
            scores: engine.scores,
            phase: engine.phase,
            aktivSeat: engine.phase == .budrunde ? engine.aktivBudgiver
                : engine.phase == .velgTrumf ? (engine.budgiverSeat ?? 0)
                : engine.aktivSpiller,
            bids: engine.bids,
            høyesteBud: engine.høyesteBud,
            trumf: engine.trumf,
            ønsketKort: engine.ønsketKort,
            makkerAvslørt: engine.makkerAvslørt,
            makkerSeat: engine.makkerAvslørt ? engine.makkerSeat : nil,
            erAmerikaner: engine.erAmerikaner,
            budgiverSeat: engine.budgiverSeat,
            currentTrick: engine.currentTrick,
            sisteStikk: engine.sisteStikk,
            stikkTatt: engine.stikkTatt,
            trickNummer: engine.trickNummer,
            dinHånd: engine.hands.indices.contains(sete) ? engine.hands[sete] : [],
            lovligeKort: engine.lovligeKort(for: sete),
            lovligeBud: engine.lovligeBud(for: sete),
            sisteRunde: engine.sisteRunde,
            vinnerSeat: engine.vinnerSeat,
            rundeHistorikk: engine.phase == .spillFerdig ? engine.rundeResultater : nil
        )
    }

    // MARK: - Frafall

    /// Verten erstatter frafalne spillere med en CPU så partiet kan
    /// fullføres. Faller verten selv fra, avsluttes partiet hos klientene.
    private func spillerKobletFra(_ spiller: GKPlayer) {
        if erVert {
            guard let sete = seteTilRemote.first(where: { $0.value.gamePlayerID == spiller.gamePlayerID })?.key
            else { return }
            seteTilRemote[sete] = nil
            aiSeter[sete] = AIPlayer(seat: sete, difficulty: .middels, personality: .balansert)
            seatNavn[sete] = "\(spiller.displayName) 🤖"
            infoTekst = "\(spiller.displayName) forlot bordet – en CPU tar over setet."
            kringkast()
            kjørAI()
        } else if spillAktivt {
            infoTekst = "Forbindelsen til verten er borte. Partiet avsluttes."
        }
    }

    // MARK: - Avslutning og statistikk

    func navn(for sete: Int) -> String {
        setup?.seatNavn.indices.contains(sete) == true ? setup!.seatNavn[sete] : "Sete \(sete + 1)"
    }

    /// Lagres lokalt på hver enhet, med en selv som «meg» – da fungerer
    /// H2H-statistikken mot både venner og CPU-utfyllere.
    func lagreStatistikk(i appState: AppState) {
        guard !statsLagret, let setup, let snap, snap.phase == .spillFerdig else { return }
        statsLagret = true

        let ider = setup.seatIdentitet.enumerated().map { sete, identitet -> String in
            if sete == mittSete { return "meg" }
            if identitet.hasPrefix("ai:") { return String(identitet.dropFirst(3)) }
            return "online-\(identitet.dropFirst(3))"
        }
        let deltakere = (0..<4).map { sete in
            MatchParticipant(
                id: ider[sete],
                navn: setup.seatNavn[sete],
                erMeg: sete == mittSete,
                opponentId: setup.seatIdentitet[sete].hasPrefix("ai:")
                    ? String(setup.seatIdentitet[sete].dropFirst(3)) : nil,
                sluttPoeng: snap.scores[sete],
                vantPartiet: sete == snap.vinnerSeat
            )
        }
        let runder = (snap.rundeHistorikk ?? []).map { runde in
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
        appState.registrerParti(MatchRecord(mode: .online, deltakere: deltakere, runder: runder))
    }

    func forlat() {
        aiOppgave?.cancel()
        engine = nil
        spillAktivt = false
        setup = nil
        snap = nil
        infoTekst = nil
        statsLagret = false
        gc.forlatMatch()
    }
}
