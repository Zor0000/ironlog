import SwiftUI

struct ConfirmActionModal: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    let systemImage: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.danger.opacity(0.14))
                        .frame(width: 54, height: 54)
                    Image(systemName: systemImage)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(Theme.danger)
                }

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 20, weight: .black))
                        .fontWidth(.condensed)
                        .foregroundStyle(Theme.text)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 9) {
                    Button {
                        NativeFeedback.light()
                        confirm()
                    } label: {
                        Label(confirmTitle, systemImage: systemImage)
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Theme.danger)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(TactileButtonStyle())

                    Button {
                        NativeFeedback.selection()
                        cancel()
                    } label: {
                        Text(cancelTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(Theme.text)
                            .background(Theme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    }
                    .buttonStyle(TactileButtonStyle())
                }
            }
            .padding(18)
            .frame(maxWidth: 340)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.surface)
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.07), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
            }
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
            .shadow(color: .black.opacity(0.38), radius: 30, y: 18)
            .padding(.horizontal, 22)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}

/// Discard-workout confirmation overlay shared by the Log and Workouts tabs.
private struct DiscardWorkoutOverlay: ViewModifier {
    @EnvironmentObject private var app: AppState
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ConfirmActionModal(
                    title: "Discard workout?",
                    message: "This clears the current exercises, sets, timer and note. Saved history will not be affected.",
                    confirmTitle: "Discard Workout",
                    cancelTitle: "Keep Logging",
                    systemImage: "trash"
                ) {
                    withAnimation(AppMotion.smooth) {
                        isPresented = false
                        app.discardWorkout()
                    }
                } cancel: {
                    withAnimation(AppMotion.quick) {
                        isPresented = false
                    }
                }
            }
        }
    }
}

extension View {
    func discardWorkoutOverlay(isPresented: Binding<Bool>) -> some View {
        modifier(DiscardWorkoutOverlay(isPresented: isPresented))
    }
}
