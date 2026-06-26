import SwiftUI

@main
struct IronLogApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task {
                    await appState.boot()
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
