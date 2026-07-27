import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let surface = Color(red: 0.078, green: 0.078, blue: 0.078)
    static let surface2 = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let border = Color(red: 0.153, green: 0.153, blue: 0.153)
    static let accent = Color(red: 0.831, green: 1.0, blue: 0.29)
    static let accentDim = Color(red: 0.831, green: 1.0, blue: 0.29).opacity(0.12)
    static let text = Color(red: 0.937, green: 0.937, blue: 0.937)
    // Kept above ~4.5:1 contrast on bg/surface2 — don't darken below this.
    static let muted = Color(red: 0.48, green: 0.48, blue: 0.48)
    static let muted2 = Color(red: 0.64, green: 0.64, blue: 0.64)
    static let success = Color(red: 0.29, green: 0.87, blue: 0.50)
    static let danger = Color(red: 1.0, green: 0.267, blue: 0.267)
    static let blue = Color(red: 0.29, green: 0.62, blue: 1.0)
}

enum AppMotion {
    static let tap = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.72, blendDuration: 0.08)
    static let quick = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.08)
    static let smooth = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.86, blendDuration: 0.12)
    static let screen = Animation.interactiveSpring(response: 0.46, dampingFraction: 0.9, blendDuration: 0.14)
}

enum NativeFeedback {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct NativeBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            LinearGradient(
                colors: [
                    Theme.surface.opacity(0.95),
                    Theme.bg,
                    Color.black.opacity(0.48)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.1), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 220)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }
}

/// The session-note editors sit at the bottom of a ScrollView where SwiftUI's keyboard
/// avoidance doesn't scroll them clear of the keyboard — the live log is inside a paged
/// TabView above the tab bar, the session editor inside a sheet — so you can't see what
/// you're typing. Tag the note card with `.id(sessionNoteAnchor)` and pin it to the visible
/// bottom ourselves, on focus and as the text grows.
let sessionNoteAnchor = "session-note"

extension View {
    func keepsNoteVisible(_ proxy: ScrollViewProxy, focused: Bool, text: String) -> some View {
        onChange(of: focused) { _, isFocused in
            guard isFocused else { return }
            // ponytail: fixed delay waits out the keyboard inset; a keyboard-frame observer
            // if this ever feels off on slower devices.
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(AppMotion.smooth) { proxy.scrollTo(sessionNoteAnchor, anchor: .bottom) }
            }
        }
        .onChange(of: text) { _, _ in
            guard focused else { return }
            proxy.scrollTo(sessionNoteAnchor, anchor: .bottom)
        }
    }

    func cardStyle(radius: CGFloat = 14) -> some View {
        padding(16)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface.opacity(0.88))
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.045), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.border.opacity(0.9)))
            .shadow(color: .black.opacity(0.24), radius: 20, y: 12)
    }

    func sectionTitle() -> some View {
        font(.system(size: 22, weight: .black))
            .fontWidth(.condensed)
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Theme.text)
    }

    /// Small uppercase label heading a card section ("Weight Unit", "Session Note").
    func cardLabel() -> some View {
        font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
    }

    func entrance(_ index: Int = 0, offset: CGFloat = 16) -> some View {
        modifier(EntranceModifier(index: index, offset: offset))
    }
}

private struct EntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    let index: Int
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : offset)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.985)
            .onAppear {
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(AppMotion.smooth.delay(Double(index) * 0.045)) {
                        isVisible = true
                    }
                }
            }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.black)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: Theme.accent.opacity(configuration.isPressed ? 0.08 : 0.2), radius: configuration.isPressed ? 8 : 18, y: configuration.isPressed ? 3 : 9)
            .animation(AppMotion.tap, value: configuration.isPressed)
    }
}

/// Full-width outlined button on the dark surface — the "not the primary
/// action" counterpart to `PrimaryButtonStyle` (Continue locally, modal cancel,
/// settings rows). `tint` colors the label; pass `Theme.danger` for destructive.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(tint)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(AppMotion.tap, value: configuration.isPressed)
    }
}

struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(AppMotion.tap, value: configuration.isPressed)
    }
}

struct Pill: View {
    let text: String
    var icon: String? = nil
    var isActive = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            }
            Text(text)
        }
        .font(.system(size: 13, weight: isActive ? .bold : .medium))
        .foregroundStyle(isActive ? .black : Theme.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isActive ? Theme.accent : Theme.surface2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isActive ? Theme.accent : Theme.border))
        .animation(AppMotion.quick, value: isActive)
    }
}
