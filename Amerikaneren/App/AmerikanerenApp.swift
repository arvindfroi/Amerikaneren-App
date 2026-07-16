import SwiftUI

@main
struct AmerikanerenApp: App {
    @StateObject private var appState = AppState()

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
    }
}
