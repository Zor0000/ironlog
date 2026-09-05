import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            NativeBackground()
            if app.showingOnboarding {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else if app.showingAuth {
                AuthView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                AppShellView()
                    .transition(.opacity.combined(with: .scale(scale: 0.995)))
            }
            if let toast = app.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.border))
                        .shadow(color: .black.opacity(0.24), radius: 20, y: 12)
                        .padding(.bottom, 72)
                        .allowsHitTesting(false)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
            }
        }
        .foregroundStyle(Theme.text)
        .onChange(of: app.toast) { _, message in
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .animation(AppMotion.smooth, value: app.toast)
        .animation(AppMotion.screen, value: app.showingAuth)
        .animation(AppMotion.screen, value: app.showingOnboarding)
    }
}

/// First-run intro: three swipeable cards ending in the cloud-vs-local choice.
/// Shown once (gated on `hasOnboarded` in the snapshot), always skippable.
struct OnboardingView: View {
    @EnvironmentObject private var app: AppState
    @State private var page = 0

    private let cards: [(icon: String, title: String, text: String)] = [
        ("dumbbell.fill", "Log sets in seconds",
         "Pick a split, tap through your exercises, check off sets as you lift. No clutter, no subscription."),
        ("timer", "Rest runs itself",
         "Finishing a set starts your rest timer. Log the next set right from the Lock Screen — and get pinged when rest is over."),
        ("chart.line.uptrend.xyaxis", "Watch the bar go up",
         "PRs are detected automatically and every exercise gets a progress graph. Your data stays yours."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") {
                    NativeFeedback.selection()
                    app.finishOnboarding(createAccount: false)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.muted2)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .frame(minHeight: 44)
                .accessibilityIdentifier("onboarding-skip-button")
            }

            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    VStack(spacing: 18) {
                        Image(systemName: card.icon)
                            .font(.largeTitle)
                            .foregroundStyle(Theme.accent)
                        Text(card.title)
                            .font(.title.weight(.black))
                            .fontWidth(.condensed)
                        Text(card.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 9) {
                if page < cards.count - 1 {
                    Button {
                        NativeFeedback.light()
                        withAnimation(AppMotion.smooth) { page += 1 }
                    } label: {
                        Label("Next", systemImage: "arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button {
                        NativeFeedback.light()
                        app.finishOnboarding(createAccount: true)
                    } label: {
                        Label("Create Account — Sync Everywhere", systemImage: "icloud")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                        NativeFeedback.selection()
                        app.finishOnboarding(createAccount: false)
                    } label: {
                        Text("Continue locally — no account needed")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("onboarding-continue-locally-button")
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
            .animation(AppMotion.quick, value: page)
        }
    }
}

struct AuthView: View {
    @EnvironmentObject private var app: AppState
    @State private var mode: AuthMode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 4) {
                Text("IronLog")
                    .font(.largeTitle.weight(.black))
                    .fontWidth(.condensed)
                    .tracking(4)
                    .foregroundStyle(Theme.accent)
                Text("Track your gains. Own your progress.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted2)
            }

            VStack(spacing: 14) {
                Picker("Account action", selection: $mode) {
                    Text("Sign In").tag(AuthMode.signIn)
                    Text("Sign Up").tag(AuthMode.signUp)
                }
                .pickerStyle(.segmented)
                .disabled(app.isBusy)
                .tint(Theme.accent)
                .animation(AppMotion.quick, value: mode)

                if let message = app.authMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(message.contains("created") ? Theme.success : Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if mode == .signUp {
                    TextField("Your name", text: $name)
                        .accessibilityLabel("Your name")
                        .textContentType(.name)
                        .fieldStyle()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                TextField("Email address", text: $email)
                    .accessibilityLabel("Email address")
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .fieldStyle()
                if mode == .signUp {
                    Text("Use at least 6 characters for your password.").font(.footnote).foregroundStyle(Theme.muted2)
                }
                SecureField("Password", text: $password)
                    .accessibilityLabel("Password")
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .fieldStyle()

                Button(app.isBusy ? "Please wait…" : mode == .signIn ? "Sign In" : "Create Account") {
                    NativeFeedback.light()
                    Task {
                        if mode == .signIn {
                            await app.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                        } else {
                            let didCreateAccount = await app.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, name: name)
                            if didCreateAccount {
                                mode = .signIn
                            }
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(app.isBusy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || (mode == .signUp && (password.count < 6 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
                .opacity(app.isBusy ? 0.6 : 1)

                Button {
                    NativeFeedback.selection()
                    app.continueLocally()
                } label: {
                    Text("Continue locally")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(app.isBusy)
            }
            .cardStyle(radius: 18)
            .padding(.horizontal, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .entrance()
            Spacer()
        }
        }
        .keyboardDismissControl()
    }
}

struct AppShellView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var tabSelection
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                tabContent(.workouts) { WorkoutsView() }
                tabContent(.log) { LogView() }
                tabContent(.run) { RunView() }
                tabContent(.history) { HistoryView() }
                tabContent(.stats) { StatsView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)


            HStack {
                navButton(.workouts, "Workouts", "list.bullet")
                navButton(.log, "Today", "timer")
                navButton(.run, "Run", "figure.run")
                navButton(.history, "History", "calendar")
                navButton(.stats, "Stats", "chart.bar")
            }
            .padding(.horizontal, 6)
            .padding(.top, 9)
            .padding(.bottom, 10)
            .background {
                Rectangle()
                    .fill(Theme.surface.opacity(0.96))
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.035), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .top)
        }
        .keyboardDismissControl()
    }

    private func tabContent<Content: View>(_ tab: WorkoutTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(app.selectedTab == tab ? 1 : 0)
            .allowsHitTesting(app.selectedTab == tab)
            .accessibilityHidden(app.selectedTab != tab)
    }

    private var header: some View {
        HStack {
            Text("IronLog")
                .font(.title.weight(.black))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .fontWidth(.condensed)
                .tracking(2)
                .foregroundStyle(Theme.accent)
            Spacer()
            if !typeSize.isAccessibilitySize {
            VStack(alignment: .trailing, spacing: 1) {
                Text(Date().formatted(.dateTime.weekday(.wide)))
                    .font(.footnote.weight(.bold))
                Text(Date().formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption)
                    .foregroundStyle(Theme.muted2)
            }
            }
            Button {
                NativeFeedback.selection()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(Theme.muted2)
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(Theme.surface.opacity(0.96))
                .overlay {
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.08), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)
    }

    private func navButton(_ tab: WorkoutTab, _ label: String, _ icon: String) -> some View {
        let isActive = app.selectedTab == tab
        return Button {
            NativeFeedback.selection()
            withAnimation(AppMotion.quick) {
                app.selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3.weight(.medium))
                    .scaleEffect(isActive ? 1.08 : 1)
                    .symbolEffect(.bounce, value: isActive)
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.accentDim)
                        .matchedGeometryEffect(id: "tabSelection", in: tabSelection)
                }
            }
            .foregroundStyle(isActive ? Theme.accent : Theme.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: icon) }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

extension View {
    func fieldStyle() -> some View {
        textFieldStyle(.plain)
            .font(.subheadline)
            .padding(13)
            .foregroundStyle(Theme.text)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

}
