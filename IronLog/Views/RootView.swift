import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState

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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.border))
                        .shadow(color: .black.opacity(0.24), radius: 20, y: 12)
                        .padding(.bottom, 72)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
            }
        }
        .foregroundStyle(Theme.text)
        .sensoryFeedback(.success, trigger: app.toast)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted2)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .accessibilityIdentifier("onboarding-skip-button")
            }

            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    VStack(spacing: 18) {
                        Image(systemName: card.icon)
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.accent)
                        Text(card.title)
                            .font(.system(size: 30, weight: .black))
                            .fontWidth(.condensed)
                        Text(card.text)
                            .font(.system(size: 14))
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
    @State private var confirmation = ""
    @State private var showForgotPassword = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 4) {
                Text(app.isPasswordRecovery ? "New password" : "IronLog")
                    .font(.system(size: 52, weight: .black))
                    .fontWidth(.condensed)
                    .tracking(app.isPasswordRecovery ? 0 : 4)
                    .foregroundStyle(Theme.accent)
                Text(app.isPasswordRecovery
                     ? "Choose a new password for your account."
                     : "Track your gains. Own your progress.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted2)
            }

            VStack(spacing: 14) {
                if app.isPasswordRecovery {
                    passwordRecoveryForm
                } else {
                    Picker("", selection: $mode) {
                        Text("Sign In").tag(AuthMode.signIn)
                        Text("Sign Up").tag(AuthMode.signUp)
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.accent)
                    .animation(AppMotion.quick, value: mode)
                    .disabled(app.isBusy)

                    authMessage

                    if mode == .signUp {
                        TextField("", text: $name)
                            .textContentType(.name)
                            .fieldStyle()
                            .placeholderText("Your name", visible: name.isEmpty)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    TextField("", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fieldStyle()
                        .placeholderText("Email address", visible: email.isEmpty)
                    SecureField("", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .fieldStyle()
                        .placeholderText(mode == .signIn ? "Password" : "Password (8+ characters)", visible: password.isEmpty)

                    if mode == .signIn {
                        Button("Forgot password?") {
                            app.authMessage = nil
                            showForgotPassword = true
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .disabled(app.isBusy)
                        .accessibilityIdentifier("forgot-password-button")
                    } else {
                        Text("Use at least 8 characters.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        NativeFeedback.light()
                        Task {
                            if mode == .signIn {
                                await app.signIn(email: cleanEmail, password: password)
                            } else {
                                let shouldShowSignIn = await app.signUp(
                                    email: cleanEmail,
                                    password: password,
                                    name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                                )
                                if shouldShowSignIn { mode = .signIn }
                            }
                        }
                    } label: {
                        busyLabel(authButtonTitle, darkSpinner: true)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit)

                    HStack(spacing: 12) {
                        Rectangle().fill(Theme.border).frame(height: 1)
                        Text("OR")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted2)
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }

                    Button {
                        NativeFeedback.light()
                        Task { await app.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Text("G")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Text("Continue with Google")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(app.isBusy)
                    .accessibilityIdentifier("google-sign-in-button")

                    Button {
                        NativeFeedback.selection()
                        app.continueLocally()
                    } label: {
                        Text("Continue locally")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(app.isBusy)
                }
            }
            .cardStyle(radius: 18)
            .padding(.horizontal, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .entrance()
            Spacer()
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(initialEmail: cleanEmail)
                .environmentObject(app)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var authMessage: some View {
        if let message = app.authMessage {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(isPositiveMessage(message) ? Theme.success : Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("auth-message")
        }
    }

    private var passwordRecoveryForm: some View {
        VStack(spacing: 14) {
            authMessage
            SecureField("", text: $password)
                .textContentType(.newPassword)
                .fieldStyle()
                .placeholderText("New password", visible: password.isEmpty)
            SecureField("", text: $confirmation)
                .textContentType(.newPassword)
                .fieldStyle()
                .placeholderText("Confirm new password", visible: confirmation.isEmpty)
            Text(password.count >= 8 && confirmation != password
                 ? "Passwords do not match."
                 : "Use at least 8 characters.")
                .font(.system(size: 12))
                .foregroundStyle(password.count >= 8 && confirmation != password ? Theme.danger : Theme.muted2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NativeFeedback.light()
                Task { await app.completePasswordReset(password) }
            } label: {
                busyLabel(app.isBusy ? "Updating…" : "Update Password", darkSpinner: true)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(app.isBusy || password.count < 8 || password != confirmation)
            .accessibilityIdentifier("update-password-button")
        }
    }

    private func busyLabel(_ title: String, darkSpinner: Bool) -> some View {
        HStack(spacing: 8) {
            if app.isBusy {
                ProgressView().tint(darkSpinner ? .black : Theme.text)
            }
            Text(title)
        }
    }

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        guard !app.isBusy,
              !cleanEmail.isEmpty,
              !password.isEmpty else { return false }
        if mode == .signUp {
            return password.count >= 8 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var authButtonTitle: String {
        if app.isBusy {
            return mode == .signIn ? "Signing In…" : "Creating Account…"
        }
        return mode == .signIn ? "Sign In" : "Create Account"
    }

    private func isPositiveMessage(_ message: String) -> Bool {
        message.contains("created") || message.contains("reset link")
    }

}

private struct ForgotPasswordView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var sent = false

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        ZStack {
            NativeBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("Reset password")
                    .font(.system(size: 30, weight: .black))
                    .fontWidth(.condensed)
                Text(sent
                     ? "If an account exists for that email, a reset link is on its way."
                     : "Enter your account email and we’ll send you a secure reset link.")
                    .font(.system(size: 13))
                    .foregroundStyle(sent ? Theme.success : Theme.muted2)

                if !sent {
                    TextField("", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fieldStyle()
                        .placeholderText("Email address", visible: email.isEmpty)
                    if let message = app.authMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.danger)
                    }
                    Button {
                        Task {
                            sent = await app.requestPasswordReset(
                                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if app.isBusy { ProgressView().tint(.black) }
                            Text(app.isBusy ? "Sending…" : "Send Reset Link")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(app.isBusy || !email.contains("@"))
                    .accessibilityIdentifier("send-reset-link-button")
                } else {
                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(28)
        }
        .onAppear { app.authMessage = nil }
    }
}

struct AppShellView: View {
    @EnvironmentObject private var app: AppState
    @Namespace private var tabSelection
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $app.selectedTab) {
                WorkoutsView().tag(WorkoutTab.workouts)
                LogView().tag(WorkoutTab.log)
                RunView().tag(WorkoutTab.run)
                HistoryView().tag(WorkoutTab.history)
                StatsView().tag(WorkoutTab.stats)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(AppMotion.screen, value: app.selectedTab)

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
    }

    private var header: some View {
        HStack {
            Text("IronLog")
                .font(.system(size: 28, weight: .black))
                .fontWidth(.condensed)
                .tracking(2)
                .foregroundStyle(Theme.accent)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Date().formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 13, weight: .bold))
                Text(Date().formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted2)
            }
            Button {
                NativeFeedback.selection()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted2)
                    .frame(width: 32, height: 32)
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
                    .font(.system(size: 20, weight: .medium))
                    .scaleEffect(isActive ? 1.08 : 1)
                    .symbolEffect(.bounce, value: isActive)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
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
    }
}

extension View {
    func fieldStyle() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(13)
            .foregroundStyle(Theme.text)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    /// Legible placeholder overlay — the system placeholder is nearly invisible on the dark
    /// surface. Pass "" to the field itself and drive `visible` off its emptiness. Apply after
    /// `fieldStyle()` so the 13pt inset lines up with the field's text.
    func placeholderText(_ text: String, visible: Bool) -> some View {
        overlay(alignment: .leading) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted2)
                .padding(.horizontal, 13)
                .allowsHitTesting(false)
                .opacity(visible ? 1 : 0)
        }
    }
}
