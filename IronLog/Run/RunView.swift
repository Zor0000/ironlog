import SwiftUI
import MapKit

/// The Run tab: start a GPS-tracked run, walk or ride, watch the numbers that
/// matter, save it into the same History timeline as a lifting session.
struct RunView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var tracker = RunTracker.shared
    @State private var showDiscardConfirmation = false

    var body: some View {
        VStack(spacing: 14) {
            if tracker.hasActiveRun {
                activeScreen
            } else {
                idleScreen
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .animation(AppMotion.screen, value: tracker.phase)
        .animation(AppMotion.quick, value: tracker.kind)
        .overlay {
            if showDiscardConfirmation {
                ConfirmActionModal(
                    title: "Discard \(tracker.kind.label.lowercased())?",
                    message: "The \(formatDistance(tracker.distance)) \(currentDistanceUnit.label) tracked so far will be lost.",
                    confirmTitle: "Discard \(tracker.kind.label)",
                    cancelTitle: "Keep Going",
                    systemImage: "trash"
                ) {
                    withAnimation(AppMotion.smooth) {
                        showDiscardConfirmation = false
                        tracker.discard()
                    }
                } cancel: {
                    withAnimation(AppMotion.quick) { showDiscardConfirmation = false }
                }
            }
        }
    }

    // MARK: Idle — full-bleed activity picker

    private var idleScreen: some View {
        VStack(spacing: 12) {
            TitleBlock(title: "Go Outside", subtitle: "GPS-tracked run, walk or ride")

            if tracker.permissionDenied {
                permissionCard
            }

            // The three tiles share whatever height is left, so the picker fills
            // the screen instead of huddling under the title.
            VStack(spacing: 10) {
                ForEach(Array(CardioKind.allCases.enumerated()), id: \.element) { index, kind in
                    kindTile(kind)
                        .entrance(index)
                }
            }
            .frame(maxHeight: .infinity)

            startButton
            lastActivityLine
        }
    }

    private func kindTile(_ kind: CardioKind) -> some View {
        let isSelected = tracker.kind == kind
        return Button {
            NativeFeedback.selection()
            withAnimation(AppMotion.quick) { tracker.kind = kind }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: kind.icon)
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.muted2)
                    .frame(width: 76)
                    .symbolEffect(.bounce, value: isSelected)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.label)
                        .font(.system(size: 24, weight: .black))
                        .fontWidth(.condensed)
                        .foregroundStyle(isSelected ? Theme.accent : Theme.text)
                    Text(kind.blurb)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(isSelected ? Theme.accentDim : Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityIdentifier("run-kind-\(kind.rawValue)")
        .accessibilityLabel(kind.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var startButton: some View {
        Button {
            NativeFeedback.light()
            withAnimation(AppMotion.smooth) { tracker.start(kind: tracker.kind) }
        } label: {
            Label("Start \(tracker.kind.label)", systemImage: "location.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("run-start-button")
    }

    private var lastActivityLine: some View {
        Group {
            if let session = app.sessions.first(where: \.isCardio), let activity = session.activity {
                Text("Last \(activity.kind.label.lowercased()): \(formatDistance(activity.distance)) \(currentDistanceUnit.label) · \(formatElapsed(activity.duration)) · \(session.createdAt.displayDay)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Location access is off", systemImage: "location.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.danger)
            Text("Distance and pace come from GPS, so IronLog needs location while you're recording. Nothing is tracked at any other time.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted2)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .cardStyle()
    }

    // MARK: Active

    private var activeScreen: some View {
        VStack(spacing: 14) {
            if let interruption = tracker.interruption {
                interruptionBanner(interruption)
            }

            VStack(spacing: 16) {
                HStack {
                    Label(tracker.kind.label, systemImage: tracker.kind.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    statusPill
                }

                Text(formatElapsed(tracker.elapsed))
                    .font(.system(size: 68, weight: .black))
                    .fontWidth(.condensed)
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("run-elapsed")

                HStack {
                    metric(formatDistance(tracker.distance), currentDistanceUnit.label)
                    Spacer()
                    metric(formatPace(seconds: tracker.elapsed, metres: tracker.distance), "/\(currentDistanceUnit.label)")
                }
            }
            .cardStyle()

            Spacer(minLength: 0)

            if tracker.phase != .awaitingPermission {
                HStack(spacing: 8) {
                    Button {
                        NativeFeedback.selection()
                        withAnimation(AppMotion.quick) {
                            tracker.phase == .running ? tracker.pause() : tracker.resume()
                        }
                    } label: {
                        Label(
                            tracker.phase == .running ? "Pause" : "Resume",
                            systemImage: tracker.phase == .running ? "pause.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("run-pause-button")

                    Button {
                        NativeFeedback.success()
                        // `finish()` returns nil and keeps the run alive when
                        // nothing was tracked; `saveRun` explains that.
                        app.saveRun(tracker.finish())
                    } label: {
                        Label("Finish", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("run-finish-button")
                }

                Button {
                    NativeFeedback.selection()
                    showDiscardConfirmation = true
                } label: {
                    Text("Discard")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(TactileButtonStyle())
            }
        }
    }

    private func interruptionBanner(_ interruption: RunTracker.Interruption) -> some View {
        let (icon, title, detail): (String, String, String) = {
            switch interruption {
            case .permissionLost:
                return ("location.slash",
                        "Paused — location turned off",
                        "Your \(formatDistance(tracker.distance)) \(currentDistanceUnit.label) is safe. Re-enable location in Settings to keep going, or finish here.")
            case .restored:
                return ("arrow.counterclockwise",
                        "\(tracker.kind.label) recovered",
                        "IronLog closed mid-activity. Time counted while it was closed is not included — resume to keep going, or finish and save what you have.")
            }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.blue)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted2)
                .fixedSize(horizontal: false, vertical: true)
            if interruption == .permissionLost, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.blue.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.blue.opacity(0.4)))
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            switch tracker.phase {
            case .awaitingPermission: return ("Waiting for permission", Theme.blue)
            case .paused: return ("Paused", Theme.muted2)
            case .idle: return ("", Theme.muted2)
            case .running:
                if tracker.waitingForFix { return ("Acquiring GPS…", Theme.blue) }
                if tracker.signalLost { return ("Weak GPS signal", Theme.danger) }
                return ("Tracking", Theme.success)
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
            .accessibilityIdentifier("run-status")
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .fontWidth(.condensed)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted2)
        }
    }
}

/// Route line for a saved activity, shown in History. Auto-frames the whole route.
struct RouteMap: View {
    let route: [RoutePoint]

    var body: some View {
        let coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        Map(initialPosition: .region(region(for: coordinates)), interactionModes: []) {
            MapPolyline(coordinates: coordinates)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .allowsHitTesting(false)
    }

    /// Bounding box of the route plus a margin, so the line never touches the edge.
    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(center: .init(), span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in coordinates {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.002),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.002)
            )
        )
    }
}
