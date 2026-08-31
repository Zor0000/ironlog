import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var bodyWeightText = ""
    @FocusState private var bodyWeightFocused: Bool

    var body: some View {
        ZStack {
            NativeBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        TitleBlock(title: "Settings", subtitle: "Account, units & timer")
                        Spacer()
                        Button {
                            NativeFeedback.selection()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 30, height: 30)
                                .foregroundStyle(Theme.muted2)
                                .background(Theme.surface2)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Theme.border))
                        }
                        .buttonStyle(TactileButtonStyle())
                        .accessibilityLabel("Close settings")
                    }
                    accountCard
                    unitsCard
                    bodyWeightCard
                    timerCard
                    notificationsCard
                    aboutCard
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)

            if showDeleteConfirmation {
                ConfirmActionModal(
                    title: "Delete account?",
                    message: "This permanently deletes your workouts, records and account data from this iPhone and the cloud. This cannot be undone.",
                    confirmTitle: "Delete Everything",
                    cancelTitle: "Keep My Data",
                    systemImage: "trash"
                ) {
                    withAnimation(AppMotion.smooth) {
                        showDeleteConfirmation = false
                    }
                    Task {
                        if await app.deleteAccount() {
                            dismiss()
                        }
                    }
                } cancel: {
                    withAnimation(AppMotion.quick) {
                        showDeleteConfirmation = false
                    }
                }
            }
        }
        .foregroundStyle(Theme.text)
        .animation(AppMotion.quick, value: showDeleteConfirmation)
        .task {
            notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    // MARK: Account

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Account")
            HStack(spacing: 10) {
                Image(systemName: isCloudUser ? "person.crop.circle.badge.checkmark" : "iphone")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCloudUser ? (app.user?.email ?? "") : "Local — saved on this iPhone")
                        .font(.system(size: 15, weight: .semibold))
                    Text(app.syncMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted2)
                }
            }
            if isCloudUser {
                settingsButton("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                    app.signOut()
                    dismiss()
                }
            } else {
                settingsButton("Sign In / Create Account", systemImage: "person.badge.plus") {
                    dismiss()
                    app.showAuth()
                }
            }
            settingsButton("Delete Account & Data", systemImage: "trash", tint: Theme.danger) {
                showDeleteConfirmation = true
            }
            .accessibilityIdentifier("delete-account-button")
            .disabled(app.isBusy)
        }
        .cardStyle()
    }

    private var isCloudUser: Bool {
        app.user?.isLocal == false
    }

    // MARK: Units

    private var unitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Weight Unit")
            Picker("", selection: Binding(
                get: { app.unitPreference },
                set: { app.setUnitPreference($0) }
            )) {
                Text("Kilograms (kg)").tag(WeightUnit.kg)
                Text("Pounds (lb)").tag(WeightUnit.lb)
            }
            .pickerStyle(.segmented)
            Text("Weights are stored in kg and converted for display, so switching is always safe.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted2)
        }
        .cardStyle()
    }

    // MARK: Body weight

    /// Typed in the display unit (like every other weight in the app) and
    /// converted back to canonical KG on the keystroke — the same
    /// display↔storage split `setUnitPreference` documents.
    private var bodyWeightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Body Weight")
            HStack {
                TextField("70.0", text: $bodyWeightText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 24, weight: .bold))
                    .fontWidth(.condensed)
                    .focused($bodyWeightFocused)
                    .frame(width: 110)
                    .accessibilityIdentifier("body-weight-field")
                Text(currentWeightUnit.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            Text("Used to estimate calories for runs and walks.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted2)
        }
        .cardStyle()
        .onAppear { bodyWeightText = app.bodyWeight.map(formatWeightValue) ?? "" }
        .onChange(of: bodyWeightText) { _, text in
            guard let value = decimalEntry(text), value > 0 else { return }
            app.setBodyWeight(displayWeightToKg(value))
        }
        // The typed text lives in the old display unit after a switch; re-derive
        // it so the next keystroke does not reinterpret the number.
        .onChange(of: app.unitPreference) { _, _ in
            bodyWeightFocused = false
            bodyWeightText = app.bodyWeight.map(formatWeightValue) ?? ""
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { bodyWeightFocused = false }
            }
        }
    }

    // MARK: Rest timer default

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Rest Timer Default")
            HStack(spacing: 8) {
                ForEach(restTimerPresets, id: \.self) { value in
                    Button {
                        NativeFeedback.selection()
                        app.setTimerPreset(value)
                    } label: {
                        Pill(text: formatDuration(value), isActive: app.timerMax == value)
                    }
                    .buttonStyle(TactileButtonStyle())
                }
                Spacer(minLength: 0)
            }
        }
        .cardStyle()
    }

    // MARK: Notifications

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Rest Notifications")
            HStack(spacing: 8) {
                Circle()
                    .fill(notificationStatus == .denied ? Theme.danger : Theme.success)
                    .frame(width: 8, height: 8)
                Text(notificationStatusText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted2)
            }
            if notificationStatus == .denied {
                settingsButton("Open iOS Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .denied: "Off — the \"rest over\" alert won't fire while the app is in the background."
        case .authorized, .provisional, .ephemeral: "On — you'll be alerted when rest ends, even with the phone locked."
        default: "You'll be asked to allow alerts when your first rest timer starts."
        }
    }

    // MARK: About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("About")
            HStack {
                Text("Version")
                    .font(.system(size: 14))
                Spacer()
                Text(appVersion)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted2)
            }
            Link(destination: URL(string: "https://zor0000.github.io/ironlog/privacy.html")!) {
                aboutRow("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "mailto:neerajchormale39@gmail.com")!) {
                aboutRow("Support", systemImage: "envelope")
            }
        }
        .cardStyle()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func aboutRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14))
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted2)
        }
        .foregroundStyle(Theme.text)
    }

    // MARK: Shared bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text).cardLabel()
    }

    private func settingsButton(_ title: String, systemImage: String, tint: Color = Theme.text, action: @escaping () -> Void) -> some View {
        Button {
            NativeFeedback.selection()
            action()
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(SecondaryButtonStyle(tint: tint))
    }
}
