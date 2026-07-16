import Foundation
import GameKit
import UIKit

/// Håndterer Game Center-innlogging, matchmaking og meldingsflyt.
/// Krever Game Center-capability og at appen er registrert i App Store Connect.
@MainActor
final class GameCenterManager: NSObject, ObservableObject {
    @Published var erInnlogget = false
    @Published var innloggingsFeil: String?
    @Published var match: GKMatch?
    @Published var spillereIMatch: [String] = []

    /// Kalles for hver innkommende melding, med avsenderen.
    var onMessage: ((OnlineMessage, GKPlayer) -> Void)?
    /// Kalles når en spiller kobler fra.
    var onPlayerDisconnected: ((GKPlayer) -> Void)?

    static let delt = GameCenterManager()

    var lokalID: String { GKLocalPlayer.local.gamePlayerID }
    var lokaltNavn: String { GKLocalPlayer.local.displayName }

    /// Verten er spilleren med lavest gamePlayerID – deterministisk likt
    /// på alle enheter, uten ekstra forhandling.
    var erVert: Bool {
        guard let match else { return false }
        let alle = [lokalID] + match.players.map(\.gamePlayerID)
        return alle.min() == lokalID
    }

    func loggInn() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    // Presentér Game Centers innloggingsskjerm.
                    Self.øversteViewController()?.present(viewController, animated: true)
                    return
                }
                if let error {
                    self.innloggingsFeil = error.localizedDescription
                    self.erInnlogget = false
                    return
                }
                self.erInnlogget = GKLocalPlayer.local.isAuthenticated
            }
        }
    }

    /// Starter Game Centers matchmaking-UI for et bord (2–4 mennesker,
    /// resten av setene fylles med CPU-er av verten).
    /// - Parameter playerGroup: 0 = åpen pool. I ranked settes divisjonen
    ///   (RankTier) som playerGroup, så man kun matches innen samme kategori.
    func finnMatch(playerGroup: Int = 0) {
        let forespørsel = GKMatchRequest()
        forespørsel.minPlayers = 2
        forespørsel.maxPlayers = 4
        forespørsel.playerGroup = playerGroup
        forespørsel.inviteMessage = playerGroup == 0
            ? "Bli med på et parti Amerikaneren!"
            : "Ranked Amerikaneren – tør du?"

        guard let mmvc = GKMatchmakerViewController(matchRequest: forespørsel) else { return }
        mmvc.matchmakerDelegate = self
        Self.øversteViewController()?.present(mmvc, animated: true)
    }

    /// Rapporterer Elo-ratingen til Game Center-ledertavlen (må opprettes
    /// i App Store Connect med denne id-en).
    static let ledertavleID = "amerikaneren.elo"

    func rapporterRating(_ rating: Int) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        GKLeaderboard.submitScore(
            rating, context: 0, player: GKLocalPlayer.local,
            leaderboardIDs: [Self.ledertavleID]
        ) { error in
            if let error { print("Kunne ikke rapportere rating: \(error)") }
        }
    }

    func send(_ melding: OnlineMessage) {
        guard let match else { return }
        send(melding, til: match.players)
    }

    func send(_ melding: OnlineMessage, til spillere: [GKPlayer]) {
        guard let match, !spillere.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(melding)
            try match.send(data, to: spillere, dataMode: .reliable)
        } catch {
            print("Kunne ikke sende melding: \(error)")
        }
    }

    func forlatMatch() {
        match?.disconnect()
        match = nil
        spillereIMatch = []
    }

    private static func øversteViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rot = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var topp = rot
        while let presentert = topp.presentedViewController { topp = presentert }
        return topp
    }
}

extension GameCenterManager: GKMatchmakerViewControllerDelegate {
    nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        Task { @MainActor in viewController.dismiss(animated: true) }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        Task { @MainActor in
            viewController.dismiss(animated: true)
            self.innloggingsFeil = error.localizedDescription
        }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        Task { @MainActor in
            viewController.dismiss(animated: true)
            match.delegate = self
            self.match = match
            self.spillereIMatch = [self.lokaltNavn] + match.players.map(\.displayName)
        }
    }
}

extension GameCenterManager: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let melding = try? JSONDecoder().decode(OnlineMessage.self, from: data) else { return }
        Task { @MainActor in
            self.onMessage?(melding, player)
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor in
            self.spillereIMatch = [self.lokaltNavn] + match.players.map(\.displayName)
            if state == .disconnected {
                self.onPlayerDisconnected?(player)
            }
        }
    }
}
