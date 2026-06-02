import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            NativeBackground()
            if app.showingAuth {
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
    }
}

struct AuthView: View {
    @EnvironmentObject private var app: AppState
    @State private var mode: AuthMode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 4) {
                Text("IronLog")
                    .font(.system(size: 52, weight: .black))
                    .fontWidth(.condensed)
                    .tracking(4)
                    .foregroundStyle(Theme.accent)
                Text("Track your gains. Own your progress.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted2)
            }

            VStack(spacing: 14) {
                Picker("", selection: $mode) {
                    Text("Sign In").tag(AuthMode.signIn)
                    Text("Sign Up").tag(AuthMode.signUp)
                }
                .pickerStyle(.segmented)
                .tint(Theme.accent)
                .animation(AppMotion.quick, value: mode)

                if let message = app.authMessage {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(message.contains("created") ? Theme.success : Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if mode == .signUp {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .fieldStyle()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                TextField("Email address", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .fieldStyle()
                SecureField("Password (min 6 chars)", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .fieldStyle()

                Button(mode == .signIn ? "Sign In" : "Create Account") {
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
                .disabled(app.isBusy || email.isEmpty || password.count < 6 || (mode == .signUp && name.isEmpty))
                .opacity(app.isBusy ? 0.6 : 1)

                Button {
                    NativeFeedback.selection()
                    app.continueLocally()
                } label: {
                    Text("Continue locally")
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
            .cardStyle(radius: 18)
            .padding(.horizontal, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .entrance()
            Spacer()
        }
    }
}

struct AppShellView: View {
    @EnvironmentObject private var app: AppState
    @Namespace private var tabSelection

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $app.selectedTab) {
                WorkoutsView().tag(WorkoutTab.workouts)
                LogView().tag(WorkoutTab.log)
                HistoryView().tag(WorkoutTab.history)
                StatsView().tag(WorkoutTab.stats)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(AppMotion.screen, value: app.selectedTab)

            HStack {
                navButton(.workouts, "Workouts", "list.bullet")
                navButton(.log, "Today", "timer")
                navButton(.history, "History", "calendar")
                navButton(.stats, "Stats", "chart.bar")
            }
            .padding(.horizontal, 10)
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
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted2)
            }
            Button(app.user?.isLocal == true ? "Sync" : "Sign out") {
                NativeFeedback.selection()
                app.user?.isLocal == true ? app.showAuth() : app.signOut()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.muted2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
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
                    .font(.system(size: 10, weight: .medium))
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
}
