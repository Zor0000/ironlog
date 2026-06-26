import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(state: context.state.workout, unit: context.attributes.weightUnit)
                .activityBackgroundTint(WidgetPalette.surfaceDeep)
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

// MARK: - Lock Screen

/// Compact, single-screen layout. Three rows (header / steppers / actions) sized
/// to stay within the Lock Screen Live Activity height budget so nothing clips.
private struct LockScreenView: View {
    let state: LiveWorkoutState
    let unit: String

    var body: some View {
        VStack(spacing: 16) {
            header
            if state.isComplete {
                completeBanner
            } else {
                steppers
                actions
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WidgetPalette.accent)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.currentExercise?.name ?? state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                ProgressPips(
                    sets: state.currentExercise?.sets ?? [],
                    currentSetIndex: state.currentSetIndex ?? 0,
                    trailing: subtitle
                )
            }
            Spacer(minLength: 8)
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
        let showWeight = !(exercise?.bodyweight ?? false) && !(exercise?.timed ?? false)
        HStack(spacing: 11) {
            if showWeight {
                StepperTile(
                    label: unit,
                    value: nonEmpty(state.currentSet?.weight),
                    down: DecreaseWeightIntent(),
                    up: IncreaseWeightIntent()
                )
            }
            StepperTile(
                label: (exercise?.timed ?? false) ? "SECS" : "REPS",
                value: nonEmpty(state.currentSet?.reps),
                down: DecreaseRepsIntent(),
                up: IncreaseRepsIntent()
            )
        }
    }

    private func nonEmpty(_ value: String?) -> String {
        let value = value ?? ""
        return value.isEmpty ? "0" : value
    }

    @ViewBuilder private var actions: some View {
        let hasOpenSet = state.currentExercise?.sets.contains { !$0.done } ?? false
        let isLast = state.currentExerciseIndex >= state.exercises.count - 1
        HStack(spacing: 11) {
            if hasOpenSet {
                Button(intent: LogSetIntent()) {
                    ActionLabel(title: "Log set", systemImage: "checkmark", leadingIcon: true)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(WidgetPalette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: UndoSetIntent()) {
                    ActionLabel(title: "Undo", systemImage: "arrow.uturn.backward", leadingIcon: true)
                        .foregroundStyle(WidgetPalette.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(WidgetPalette.secondaryButton, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button(intent: NextExerciseIntent()) {
                ActionLabel(title: "Next", systemImage: "arrow.right", leadingIcon: false)
                    .foregroundStyle(isLast ? WidgetPalette.muted : WidgetPalette.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(WidgetPalette.secondaryButton, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isLast)
            .opacity(isLast ? 0.45 : 1)
        }
    }

    private var completeBanner: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(WidgetPalette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("All sets logged")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WidgetPalette.text)
                Text("Open IronLog to save")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

// MARK: - Components

/// Title + icon, icon on the leading or trailing edge.
private struct ActionLabel: View {
    let title: String
    let systemImage: String
    let leadingIcon: Bool

    var body: some View {
        HStack(spacing: 7) {
            if leadingIcon { icon }
            Text(title).font(.system(size: 15, weight: .semibold))
            if !leadingIcon { icon }
        }
    }

    private var icon: some View {
        Image(systemName: systemImage).font(.system(size: 13, weight: .bold))
    }
}

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
                        .frame(width: index == currentSetIndex && !set.done ? 12 : 5, height: 5)
                }
            }
            Text(trailing)
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.muted)
                .lineLimit(1)
        }
    }

    private func fill(for set: LiveSet, at index: Int) -> Color {
        if set.done { return WidgetPalette.accent }
        if index == currentSetIndex { return WidgetPalette.text.opacity(0.55) }
        return WidgetPalette.pip
    }
}

private struct StepperTile<Down: AppIntent, Up: AppIntent>: View {
    let label: String
    let value: String
    let down: Down
    let up: Up

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(WidgetPalette.muted)
            HStack(spacing: 0) {
                Button(intent: down) { stepIcon("minus") }
                    .buttonStyle(.plain)
                Spacer(minLength: 2)
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 2)
                Button(intent: up) { stepIcon("plus") }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(WidgetPalette.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WidgetPalette.tileStroke, lineWidth: 1))
    }

    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(WidgetPalette.text)
            .frame(width: 30, height: 30)
            .background(WidgetPalette.stepButton, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct RestBadge: View {
    let state: LiveWorkoutState

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("Rest")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(WidgetPalette.muted)
            if let endsAt = state.restEndsAt, endsAt > Date() {
                Text(timerInterval: Date()...endsAt, countsDown: true)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(WidgetPalette.accent)
                    .frame(maxWidth: 56, alignment: .trailing)
            } else {
                Text("Ready")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WidgetPalette.success)
            }
        }
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
            let showWeight = !(exercise?.bodyweight ?? false) && !(exercise?.timed ?? false)
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
                    label: (exercise?.timed ?? false) ? "SECS" : "REPS",
                    value: nonEmpty(state.currentSet?.reps),
                    down: DecreaseRepsIntent(),
                    up: IncreaseRepsIntent()
                )
                Button(intent: LogSetIntent()) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(WidgetPalette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
    }

    private func nonEmpty(_ value: String?) -> String {
        let value = value ?? ""
        return value.isEmpty ? "0" : value
    }
}
