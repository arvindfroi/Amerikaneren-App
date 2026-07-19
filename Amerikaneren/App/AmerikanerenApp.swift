import SwiftUI

@main
struct AmerikanerenApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.harFullførtOnboarding {
                    HovedmenyView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(appState)
            .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, fase in
            // Send eventuelle kølagte treningsopptak når appen er aktiv.
            if fase == .active { Innsamler.standard.prøvOpplasting() }
        }
    }
}
