import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

/// Lock Screen / Dynamic Island card for a tracked run, walk or ride.
///
/// The elapsed clock is drawn by iOS from `Text(timerInterval:)` rather than
/// pushed by the app: a Live Activity cannot run a timer of its own, and pushing
/// once a second would exhaust ActivityKit's update budget on the one value the
/// system can animate for free. The app only pushes the two measured numbers.
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            // No `activityBackgroundTint`, matching the lifting activity: iOS
            // then draws its native translucent card and the wallpaper blurs
            // through.
            RunLockScreenView(state: context.state, attributes: context.attributes)
                .activitySystemActionForegroundColor(WidgetPalette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandMetric(value: context.state.distanceText, label: context.attributes.distanceUnit)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandMetric(value: context.state.paceText, label: "/\(context.attributes.distanceUnit)")
                }
                DynamicIslandExpandedRegion(.center) {
                    RunClock(state: context.state, size: 24, width: 76)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RunActions(isPaused: context.state.isPaused, compact: true)
                }
            } compactLeading: {
                Image(systemName: context.attributes.kindIcon)
                    .foregroundStyle(WidgetPalette.accent)
            } compactTrailing: {
                RunClock(state: context.state, size: 13, width: 50)
            } minimal: {
                Image(systemName: context.attributes.kindIcon)
                    .foregroundStyle(WidgetPalette.accent)
            }
            .keylineTint(WidgetPalette.accent)
        }
    }
}

/// The elapsed clock. Live while recording, frozen while paused — a counter that
/// kept climbing on a paused run would be lying about the moving time.
private struct RunClock: View {
    let state: RunActivityAttributes.ContentState
    let size: CGFloat
    /// Reserved width. Auto-updating text must be given room up front — see below.
    let width: CGFloat

    var body: some View {
        Group {
            if state.isPaused {
                Text(state.elapsedText)
            } else {
                // Counts up from `clockStart`; the upper bound is arbitrary but
                // must be finite. Same API, and the same "reserved width, no
                // `minimumScaleFactor`/`lineLimit`" shape, as `RestBadge` — the
                // countdown this app already ships.
                //
                // Known unverified: in the Simulator the seconds render as
                // "8:––" (the minutes advance correctly on each push). That was
                // reproduced with `Text(_:style:.timer)` too, and with and
                // without the sizing modifiers, which points at the Simulator
                // not driving Live Activity text animation rather than at this
                // view — but it has NOT been confirmed on hardware. Check it on
                // a device before release: `scripts/install_iphone.sh`.
                Text(
                    timerInterval: state.clockStart...state.clockStart.addingTimeInterval(24 * 3600),
                    countsDown: false
                )
            }
        }
        .font(.system(size: size, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(WidgetPalette.accent)
        .frame(minWidth: width, alignment: .leading)
    }
}

// MARK: - Lock Screen

/// Sizing note: the lock-screen Live Activity has a firm height ceiling and iOS
/// renders the card **blank** — not clipped — if the content exceeds it. This
/// card is three fixed rows (header 30 / metrics 44 / actions 40) plus padding,
/// which leaves comfortable headroom. Re-measure on the simulator before adding
/// a fourth row.
private struct RunLockScreenView: View {
    let state: RunActivityAttributes.ContentState
    let attributes: RunActivityAttributes

    var body: some View {
        VStack(spacing: 8) {
            header
            metrics
            RunActions(isPaused: state.isPaused, compact: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(WidgetPalette.accent.opacity(0.9))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: attributes.kindIcon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                }
            Text(attributes.kindLabel)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WidgetPalette.text)
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        let (text, color): (String, Color) =
            state.isPaused ? ("Paused", WidgetPalette.muted)
            : state.signalLost ? ("Weak GPS", .orange)
            : ("Tracking", WidgetPalette.success)
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private var metrics: some View {
        HStack(alignment: .firstTextBaseline) {
            RunClock(state: state, size: 34, width: 108)
            Spacer(minLength: 8)
            metric(state.distanceText, attributes.distanceUnit)
                .frame(minWidth: 62, alignment: .trailing)
            metric(state.paceText, "/\(attributes.distanceUnit)")
                .frame(minWidth: 62, alignment: .trailing)
        }
        .frame(height: 44)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(WidgetPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WidgetPalette.muted)
        }
    }
}

// MARK: - Actions

/// Pause/Resume and Finish. Both run their intent in the app's process, so they
/// drive the same `RunTracker` the in-app buttons do.
private struct RunActions: View {
    let isPaused: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isPaused {
                Button(intent: ResumeRunIntent()) {
                    label("Resume", icon: "play.fill", primary: false)
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: PauseRunIntent()) {
                    label("Pause", icon: "pause.fill", primary: false)
                }
                .buttonStyle(.plain)
            }

            Button(intent: FinishRunIntent()) {
                label("Finish", icon: "checkmark", primary: true)
            }
            .buttonStyle(.plain)
        }
        .frame(height: compact ? 36 : 40)
    }

    private func label(_ title: String, icon: String, primary: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(primary ? .black : WidgetPalette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(primary ? WidgetPalette.accent : WidgetPalette.secondaryButton)
        )
        .overlay {
            if !primary {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(WidgetPalette.stepStroke, lineWidth: 1)
            }
        }
    }
}

private struct IslandMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WidgetPalette.text)
            Text(label.uppercased())
                .font(.system(size: 9))
                .foregroundStyle(WidgetPalette.muted)
        }
        .padding(.horizontal, 4)
    }
}
