import Foundation
import GameKit
import UIKit

/// Meldingsprotokollen som sendes mellom spillere over GKMatch.
/// Verten (laveste playerID) kjører GameEngine og kringkaster tilstand;
/// klientene sender handlinger.
enum OnlineMessage: Codable {
    case handUpdate(seat: Int, hand: [Card])
    case bidPlaced(seat: Int, action: BidAction)
    case trumpChosen(suit: Suit, requested: Card)
    case cardPlayed(seat: Int, card: Card)
    case stateSync(scores: [Int], phase: String, activeSeat: Int)
    case chat(seat: Int, text: String)
}

/// Håndterer Game Center-innlogging, matchmaking og meldingsflyt.
/// Krever Game Center-capability og at appen er registrert i App Store Connect.
@MainActor
final class GameCenterManager: NSObject, ObservableObject {
    @Published var erInnlogget = false
    @Published var innloggingsFeil: String?
    @Published var match: GKMatch?
    @Published var mottatteMeldinger: [OnlineMessage] = []
    @Published var spillereIMatch: [String] = []

    static let delt = GameCenterManager()

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

    /// Starter Game Centers matchmaking-UI for et 4-spillerbord.
    func finnMatch() {
        let forespørsel = GKMatchRequest()
        forespørsel.minPlayers = 2
        forespørsel.maxPlayers = 4
        forespørsel.inviteMessage = "Bli med på et parti Amerikaneren!"

        guard let mmvc = GKMatchmakerViewController(matchRequest: forespørsel) else { return }
        mmvc.matchmakerDelegate = self
        Self.øversteViewController()?.present(mmvc, animated: true)
    }

    func send(_ melding: OnlineMessage) {
        guard let match else { return }
        do {
            let data = try JSONEncoder().encode(melding)
            try match.sendData(toAllPlayers: data, with: .reliable)
        } catch {
            print("Kunne ikke sende melding: \(error)")
        }
    }

    func forlatMatch() {
        match?.disconnect()
        match = nil
        spillereIMatch = []
        mottatteMeldinger = []
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
            self.spillereIMatch = [GKLocalPlayer.local.displayName] + match.players.map(\.displayName)
        }
    }
}

extension GameCenterManager: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let melding = try? JSONDecoder().decode(OnlineMessage.self, from: data) else { return }
        Task { @MainActor in
            self.mottatteMeldinger.append(melding)
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor in
            self.spillereIMatch = [GKLocalPlayer.local.displayName] + match.players.map(\.displayName)
        }
    }
}
