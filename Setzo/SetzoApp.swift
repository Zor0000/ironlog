import SwiftUI
import AuthenticationServices

@main
struct SetzoApp: App {
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
                .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                    Task { await appState.handleAppleCredentialRevocation() }
                }
                .onOpenURL { url in
                    Task { await appState.handleAuthURL(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Fold in any sets logged from the Lock Screen while backgrounded.
            if phase == .active {
                appState.reconcileFromLiveActivity()
                Task { await appState.resumeForegroundSync() }
            }
        }
    }
}
