import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

/// A stepper value never shows blank — an empty field reads as "0".
private func nonEmpty(_ value: String?) -> String {
    let value = value ?? ""
    return value.isEmpty ? "0" : value
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // No `activityBackgroundTint` on purpose: iOS then draws its native
            // translucent material card, so the wallpaper blurs through.
            LockScreenView(state: context.state.workout, unit: context.attributes.weightUnit)
                .activitySystemActionForegroundColor(WidgetPalette.accent)
        } dynamicIsland: { context in
            let workout = context.state.workout
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(workout)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestBadge(state: workout)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedControls(state: workout, unit: context.attributes.weightUnit)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(WidgetPalette.accent)
            } compactTrailing: {
                CompactTrailing(state: workout)
            } minimal: {
                MinimalView(state: workout)
            }
            .keylineTint(WidgetPalette.accent)
        }
    }

    private func expandedLeading(_ state: LiveWorkoutState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.currentExercise?.name ?? state.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WidgetPalette.text)
                .lineLimit(1)
            Text("Set \(state.currentSetNumber) of \(state.currentExercise?.sets.count ?? 0)")
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.muted)
        }
    }
}

private extension View {
    /// Hairline top-lit rim that makes a translucent fill read as glass rather
    /// than as a flat wash. Skipped on opaque fills (the accent button), which
    /// have their own edge.
    func glassEdge(radius: CGFloat, visible: Bool = true) -> some View {
        overlay {
            if visible {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(WidgetPalette.stepStroke, lineWidth: 1)
            }
        }
    }
}

// MARK: - Lock Screen

/// Full-size lock-screen card. Larger, more tappable controls than a stock
/// Live Activity — a big weight/reps stepper pair and a primary action row with
/// exercise navigation — so a set can be dialed in and logged without unlocking.
///
/// Sizing note: the lock-screen Live Activity has a firm height ceiling; iOS
/// renders the card blank (not clipped) if the content exceeds it. Every metric
/// here is tuned to keep the three rows (header / steppers / actions) inside that
/// budget while staying as large as the budget allows.
private struct LockScreenView: View {
    let state: LiveWorkoutState
    let unit: String

    var body: some View {
        VStack(spacing: 7) {
            header
            if state.isComplete {
                completeBanner
            } else {
                steppers
                actions
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 9)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 9) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(WidgetPalette.accent.opacity(0.9))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.currentExercise?.name ?? state.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ProgressPips(
                    sets: state.currentExercise?.sets ?? [],
                    currentSetIndex: state.currentSetIndex ?? 0,
                    trailing: subtitle
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            RestBadge(state: state)
        }
    }

    private var subtitle: String {
        var parts = ["Set \(state.currentSetNumber)/\(state.currentExercise?.sets.count ?? 0)"]
        parts.append(state.title)
        if state.exercises.count > 1 {
            parts.append("\(state.currentExerciseIndex + 1)/\(state.exercises.count)")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var steppers: some View {
        let exercise = state.currentExercise
        // Bodyweight moves keep the weight tile — loaded lunges/pull-ups are common.
        let showWeight = !(exercise?.timed ?? false)
        HStack(spacing: 8) {
            if showWeight {
                StepperTile(
                    label: unit,
                    value: nonEmpty(state.currentSet?.weight),
                    down: DecreaseWeightIntent(),
                    up: IncreaseWeightIntent(),
                    size: .large
                )
            }
            StepperTile(
                label: (exercise?.timed ?? false) ? durationFieldLabel(minutes: exercise?.usesMinutes ?? false) : "REPS",
                value: nonEmpty(state.currentSet?.reps),
                down: DecreaseRepsIntent(),
                up: IncreaseRepsIntent(),
                size: .large
            )
        }
        // The reducer makes a finished exercise read-only; dim it so the ±
        // buttons look inert rather than broken.
        .opacity(state.isCurrentExerciseComplete ? 0.45 : 1)
    }

    @ViewBuilder private var actions: some View {
        let hasOpenSet = state.currentExercise?.sets.contains { !$0.done } ?? false
        let showNav = state.exercises.count > 1
        let isFirst = state.currentExerciseIndex <= 0
        let isLast = state.currentExerciseIndex >= state.exercises.count - 1

        HStack(spacing: 8) {
            if showNav {
                Button(intent: PreviousExerciseIntent()) {
                    navIcon("chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(isFirst)
                .opacity(isFirst ? 0.4 : 1)
            }

            if hasOpenSet {
                Button(intent: LogSetIntent()) {
                    actionLabel("Log set", systemImage: "checkmark", tint: .black, background: WidgetPalette.accent)
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: UndoSetIntent()) {
                    actionLabel("Undo", systemImage: "arrow.uturn.backward", tint: WidgetPalette.text, background: WidgetPalette.secondaryButton)
                }
                .buttonStyle(.plain)
            }

            if showNav {
                Button(intent: NextExerciseIntent()) {
                    navIcon("chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(isLast)
                .opacity(isLast ? 0.4 : 1)
            }
        }
    }

    private func actionLabel(_ title: String, systemImage: String, tint: Color, background: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 14, weight: .bold))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .glassEdge(radius: 14, visible: background != WidgetPalette.accent)
    }

    private func navIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(WidgetPalette.text)
            .frame(width: 36, height: 36)
            .background(WidgetPalette.secondaryButton, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glassEdge(radius: 14)
    }

    private var completeBanner: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24))
                .foregroundStyle(WidgetPalette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("All sets logged")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetPalette.text)
                Text("Open IronLog to save")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - Components

/// Inline set-progress pips followed by the context text — lives on the
/// header's subtitle line so it costs no extra height.
private struct ProgressPips: View {
    let sets: [LiveSet]
    let currentSetIndex: Int
    let trailing: String

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                    Capsule()
                        .fill(fill(for: set, at: index))
                        .frame(width: index == currentSetIndex && !set.done ? 14 : 6, height: 6)
                }
            }
            Text(trailing)
                .font(.system(size: 10))
                .foregroundStyle(WidgetPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func fill(for set: LiveSet, at index: Int) -> Color {
        if set.done { return WidgetPalette.accent }
        if index == currentSetIndex { return WidgetPalette.text.opacity(0.55) }
        return WidgetPalette.pip
    }
}

private struct StepperTile<Down: AppIntent, Up: AppIntent>: View {
    /// Two calibrated size classes: `large` for the roomy lock-screen card and
    /// `regular` for the tighter Dynamic Island expanded view. Only the knobs
    /// that actually differ between them live here; the rest are fixed inline.
    enum Size {
        case regular, large

        var button: CGFloat { self == .large ? 32 : 30 }
        var vPadding: CGFloat { self == .large ? 5 : 10 }
        var hPadding: CGFloat { self == .large ? 9 : 10 }
        var rowSpacing: CGFloat { self == .large ? 3 : 5 }
    }

    let label: String
    let value: String
    let down: Down
    let up: Up
    var size: Size = .regular

    var body: some View {
        VStack(spacing: size.rowSpacing) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(WidgetPalette.muted)
            HStack(spacing: 0) {
                Button(intent: down) { stepIcon("minus") }
                    .buttonStyle(.plain)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                Button(intent: up) { stepIcon("plus") }
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, size.vPadding)
        .padding(.horizontal, size.hPadding)
        .frame(maxWidth: .infinity)
        .background(WidgetPalette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(WidgetPalette.tileStroke, lineWidth: 1))
    }

    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(WidgetPalette.text)
            .frame(width: size.button, height: size.button)
            .background(WidgetPalette.stepButton, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .glassEdge(radius: 12)
    }
}

/// Single-line status pill. Centers cleanly against the title and never clips,
/// unlike a stacked caption + value. Fixed-width timer prevents reflow as digits change.
private struct RestBadge: View {
    let state: LiveWorkoutState

    var body: some View {
        if let endsAt = state.restEndsAt, endsAt > Date() {
            pill(tint: WidgetPalette.accent) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .bold))
                Text(timerInterval: Date()...endsAt, countsDown: true)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 38, alignment: .leading)
            }
        } else {
            pill(tint: WidgetPalette.success) {
                Circle()
                    .fill(WidgetPalette.success)
                    .frame(width: 7, height: 7)
                Text("Ready")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
    }

    private func pill<Content: View>(
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 5) {
            content()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(WidgetPalette.secondaryButton, in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 1))
    }
}

private struct CompactTrailing: View {
    let state: LiveWorkoutState

    var body: some View {
        if let endsAt = state.restEndsAt, endsAt > Date() {
            Text(timerInterval: Date()...endsAt, countsDown: true)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.accent)
                .frame(maxWidth: 44)
        } else {
            Text("\(state.currentExerciseDoneCount)/\(state.currentExercise?.sets.count ?? 0)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.text)
        }
    }
}

private struct MinimalView: View {
    let state: LiveWorkoutState

    var body: some View {
        if let endsAt = state.restEndsAt, endsAt > Date() {
            Text(timerInterval: Date()...endsAt, countsDown: true)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.accent)
                .frame(maxWidth: 40)
        } else {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(WidgetPalette.accent)
        }
    }
}

private struct ExpandedControls: View {
    let state: LiveWorkoutState
    let unit: String

    var body: some View {
        if state.isComplete {
            Text("All sets logged — open IronLog to save")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WidgetPalette.muted)
                .frame(maxWidth: .infinity)
        } else {
            let exercise = state.currentExercise
            // Bodyweight moves keep the weight tile — loaded lunges/pull-ups are common.
        let showWeight = !(exercise?.timed ?? false)
            HStack(spacing: 8) {
                if showWeight {
                    StepperTile(
                        label: unit,
                        value: nonEmpty(state.currentSet?.weight),
                        down: DecreaseWeightIntent(),
                        up: IncreaseWeightIntent()
                    )
                }
                StepperTile(
                    label: (exercise?.timed ?? false) ? durationFieldLabel(minutes: exercise?.usesMinutes ?? false) : "REPS",
                    value: nonEmpty(state.currentSet?.reps),
                    down: DecreaseRepsIntent(),
                    up: IncreaseRepsIntent()
                )
                // Gated on the *current exercise*, not the whole workout: on a
                // finished exercise this button used to re-log its last set and
                // restart rest from full. The lock-screen card already made the
                // same swap; the island had been missed.
                if state.isCurrentExerciseComplete {
                    Button(intent: UndoSetIntent()) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WidgetPalette.text)
                            .frame(width: 46, height: 46)
                            .background(WidgetPalette.secondaryButton, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(intent: LogSetIntent()) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 46, height: 46)
                            .background(WidgetPalette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }
}
