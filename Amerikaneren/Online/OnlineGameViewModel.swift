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
    /// Beregnet ratingendring når et ranked-parti er ferdig.
    @Published var eloResultat: (nyRating: Int, delta: Int, plassering: Int)?

    /// Settes når spilleren starter matchmaking: ranked eller vennskapelig.
    var rankedØnsket = false
    /// Egen rating, gis fra viewet (AppState) før matchmaking.
    var minRating = EloCalculator.startRating
    /// Antall egne ranked-kamper, til K-faktoren.
    var mineRankedKamper = 0

    private let gc = GameCenterManager.delt

    // Kun verten:
    private var engine: GameEngine?
    private var aiSeter: [Int: AIPlayer] = [:]
    private var seteTilRemote: [Int: GKPlayer] = [:]
    private var seatNavn: [String] = []
    private var seatIdentitet: [String] = []
    private var aiOppgave: Task<Void, Never>?
    /// Ratinger mottatt via hello-meldinger, per gamePlayerID.
    private var mottatteRatinger: [String: Int] = [:]

    var erVert: Bool { gc.erVert }
    var mittSete: Int { setup?.dittSete ?? 0 }
    var erRanked: Bool { setup?.ranked ?? false }

    func kobleTil() {
        gc.onMessage = { [weak self] melding, fra in
            self?.håndter(melding, fra: fra)
        }
        gc.onPlayerDisconnected = { [weak self] spiller in
            self?.spillerKobletFra(spiller)
        }
    }

    /// Kalles når matchen er funnet: presenter deg med rating, slik at
    /// verten kan sette opp et eventuelt ranked-parti.
    func sendHello() {
        gc.send(.hello(OnlineHello(rating: minRating)))
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

        var seatRating: [Int] = []
        for (sete, menneske) in mennesker.enumerated() {
            seatNavn.append(menneske.navn)
            seatIdentitet.append("gc:\(menneske.id)")
            seatRating.append(menneske.spiller == nil ? minRating
                              : mottatteRatinger[menneske.id] ?? EloCalculator.startRating)
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
            seatRating.append(EloCalculator.cpuRating(cpu.difficulty))
            aiSeter[sete] = AIPlayer(seat: sete, difficulty: cpu.difficulty, personality: cpu.personality)
        }

        // Send personlig setup til hver spiller.
        for (sete, spiller) in seteTilRemote {
            gc.send(.setup(OnlineSetup(
                seatNavn: seatNavn, seatIdentitet: seatIdentitet,
                dittSete: sete, målPoeng: motor.rules.målPoeng,
                ranked: rankedØnsket, seatRating: seatRating
            )), til: [spiller])
        }
        let mittSete = seatIdentitet.firstIndex(of: "gc:\(gc.lokalID)") ?? 0
        setup = OnlineSetup(seatNavn: seatNavn, seatIdentitet: seatIdentitet,
                            dittSete: mittSete, målPoeng: motor.rules.målPoeng,
                            ranked: rankedØnsket, seatRating: seatRating)

        motor.startRunde()
        spillAktivt = true
        kringkast()
        kjørAI()
    }

    // MARK: - Meldinger inn

    private func håndter(_ melding: OnlineMessage, fra spiller: GKPlayer) {
        switch melding {
        case .hello(let hei):
            mottatteRatinger[spiller.gamePlayerID] = hei.rating

        case .setup(let s):
            guard !erVert else { return }
            setup = s
            spillAktivt = true

        case .snapshot(let s):
            guard !erVert else { return }
            snap = s
            if s.phase == .spillFerdig {
                infoTekst = nil
                beregnEloOmRanked()
            }

        case .action(let handling):
            guard erVert,
                  let sete = seteTilRemote.first(where: { $0.value.gamePlayerID == spiller.gamePlayerID })?.key
            else { return }
            utfør(handling, sete: sete)
        }
    }

    /// Regner ut egen ratingendring når et ranked-parti er ferdig.
    /// Hver enhet beregner kun sin egen delta – motstandernes K spiller
    /// ingen rolle for den.
    private func beregnEloOmRanked() {
        guard eloResultat == nil, let setup, setup.ranked, let snap,
              snap.phase == .spillFerdig, setup.seatRating.count == 4 else { return }
        let mineMotstandere = (0..<4)
            .filter { $0 != mittSete }
            .map { (rating: setup.seatRating[$0], poeng: snap.scores[$0]) }
        let delta = EloCalculator.delta(
            rating: setup.seatRating[mittSete],
            poeng: snap.scores[mittSete],
            motstandere: mineMotstandere,
            k: EloCalculator.kFaktor(antallRankedKamper: mineRankedKamper)
        )
        let plassering = 1 + (0..<4).filter { snap.scores[$0] > snap.scores[mittSete] }.count
        eloResultat = (nyRating: max(100, setup.seatRating[mittSete] + delta),
                       delta: delta, plassering: plassering)
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
        if snap?.phase == .spillFerdig { beregnEloOmRanked() }
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
        appState.registrerParti(MatchRecord(
            mode: setup.ranked ? .ranked : .online,
            deltakere: deltakere, runder: runder,
            eloDelta: eloResultat?.delta
        ))
        // Ranked: oppdater rating lokalt og rapporter til ledertavlen.
        if setup.ranked, let resultat = eloResultat {
            appState.brukEloResultat(delta: resultat.delta, plassering: resultat.plassering)
            gc.rapporterRating(appState.eloRating)
        }
    }

    func forlat() {
        aiOppgave?.cancel()
        engine = nil
        spillAktivt = false
        setup = nil
        snap = nil
        infoTekst = nil
        statsLagret = false
        eloResultat = nil
        rankedØnsket = false
        mottatteRatinger = [:]
        gc.forlatMatch()
    }
}
