import SwiftUI

/// Native presentation isolates destructive actions from the app beneath it,
/// supplies the cancel/destructive roles and follows system accessibility settings.
private struct DiscardWorkoutOverlay: ViewModifier {
    @EnvironmentObject private var app: AppState
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("Discard workout?", isPresented: $isPresented) {
            Button("Keep Logging", role: .cancel) { }
            Button("Discard Workout", role: .destructive) { app.discardWorkout() }
        } message: {
            Text("This clears the current exercises, sets, timer and note. Saved history will not be affected.")
        }
    }
}

extension View {
    func discardWorkoutOverlay(isPresented: Binding<Bool>) -> some View {
        modifier(DiscardWorkoutOverlay(isPresented: isPresented))
    }
}
