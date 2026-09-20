import SwiftUI

@main
struct IronLogApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(Theme.accent)
                .task {
                    await appState.boot()
                }
                .onOpenURL { url in
                    Task { await appState.handleAuthURL(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Fold in any sets logged from the Lock Screen while backgrounded.
            if phase == .active {
                appState.reconcileFromLiveActivity()
            }
        }
    }
}
