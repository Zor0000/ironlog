import SwiftUI

struct WorkoutsView: View {
    @EnvironmentObject private var app: AppState
    @State private var showDiscardConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if app.hasActiveWorkout {
                    CurrentWorkoutBanner(showDiscardConfirmation: $showDiscardConfirmation)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Group {
                    switch app.workoutStep {
                    case .split:
                        splitStep
                    case .day:
                        dayStep
                    case .workout:
                        workoutStep
                    }
                }
                // Covers every `.entrance()` in the step's subtree at once, so
                // new rows added later inherit it without threading a flag.
                .environment(\.suppressesEntrance, app.steppingBack)
                .id(app.workoutStep)
                // Only the *insertion* edge carries the direction: the new screen
                // arrives from the right going forward, from the left going back.
                //
                // The outgoing screen deliberately just fades. A removal
                // transition is baked into a view instance when it is created,
                // so it can only ever use the direction of the navigation that
                // brought that screen in — one step stale, and visibly wrong the
                // moment you go back and then forward again.
                .transition(.asymmetric(
                    insertion: .move(edge: app.steppingBack ? .leading : .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            .padding(18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .animation(AppMotion.screen, value: app.workoutStep)
        .animation(AppMotion.quick, value: app.hasActiveWorkout)
        .discardWorkoutOverlay(isPresented: $showDiscardConfirmation)
    }

    private var splitStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            TitleBlock(title: "Split Type", subtitle: "Choose your training program")
            freeWorkoutCard
                .entrance(0)
            if app.library.splits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Workout library unavailable", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                    Text("The bundled exercise data could not be loaded. Reinstall the app or rebuild the release package.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted2)
                }
                .cardStyle()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(app.library.splits.enumerated()), id: \.element) { index, split in
                        Button {
                            NativeFeedback.selection()
                            withAnimation(AppMotion.quick) {
                                app.selectSplit(split)
                            }
                        } label: {
                            HStack {
                                Text(split)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.muted2)
                            }
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(Theme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        }
                        .foregroundStyle(Theme.text)
                        .buttonStyle(TactileButtonStyle())
                        .entrance(index + 1)
                    }
                }
            }
        }
    }

    /// Accent-tinted "start empty" card, set apart from the plain split rows so
    /// it reads as the fast path, not just another split. Skips the wizard —
    /// `startFreeWorkout()` drops straight into the log with the add-exercise form.
    private var freeWorkoutCard: some View {
        Button {
            NativeFeedback.light()
            withAnimation(AppMotion.smooth) {
                app.startFreeWorkout()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Free Workout")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Start empty — add any exercise on the fly")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted2)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(14)
            .background(Theme.accentDim)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityIdentifier("split-free-workout-button")
    }

    private var dayStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            BackButton(label: app.selectedSplit ?? "Split") {
                NativeFeedback.selection()
                withAnimation(AppMotion.quick) {
                    app.workoutStep = .split
                    app.selectedSplit = nil
                }
            }
            TitleBlock(title: "Training Day", subtitle: "Start the full day in one session")
            ForEach(Array((app.library.splitDays[app.selectedSplit ?? ""] ?? []).enumerated()), id: \.element.id) { index, day in
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) {
                        app.selectDay(day.day)
                    }
                } label: {
                    HStack {
                        Text(day.day)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.muted2)
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                }
                .foregroundStyle(Theme.text)
                .buttonStyle(TactileButtonStyle())
                .entrance(index)
            }
        }
    }

    private var workoutStep: some View {
        let muscles = app.selectedWorkoutMuscleIDs.compactMap { app.library.muscle($0) }
        // Split only — the day already shows in the back button and Start button.
        let context = app.selectedSplit ?? ""
        return VStack(alignment: .leading, spacing: 14) {
            BackButton(label: app.selectedDay ?? app.selectedWorkoutMuscleLabel) {
                NativeFeedback.selection()
                withAnimation(AppMotion.quick) {
                    if app.selectedDay != nil {
                        app.workoutStep = .day
                        app.selectedDay = nil
                    } else {
                        app.workoutStep = .split   // Full Body: back to the split list
                        app.selectedSplit = nil
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Suggested Workout")
                    .sectionTitle()
                if !context.isEmpty {
                    Pill(text: context)
                }
            }
            ForEach(muscles) { muscle in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: muscle.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(muscle.label)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.top, 4)

                    ForEach(Array(app.library.exercises(split: app.selectedSplit, muscle: muscle.id).enumerated()), id: \.element.id) { index, exercise in
                        ExerciseSuggestionCard(exercise: exercise, record: app.personalRecords[exercise.name])
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .entrance(index)
                    }
                }
            }

            Button {
                NativeFeedback.light()
                withAnimation(AppMotion.smooth) {
                    app.startWorkout()
                }
            } label: {
                Label("Start \(app.selectedDay ?? app.selectedWorkoutMuscleLabel)", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("start-suggested-workout-button")
            .padding(.top, 6)
        }
    }
}

struct CurrentWorkoutBanner: View {
    @EnvironmentObject private var app: AppState
    @Binding var showDiscardConfirmation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Workout in progress")
                        .font(.system(size: 15, weight: .semibold))
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted2)
                }
                Spacer()
            }
            HStack(spacing: 9) {
                Button {
                    NativeFeedback.light()
                    withAnimation(AppMotion.smooth) {
                        app.continueWorkout()
                    }
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    NativeFeedback.selection()
                    showDiscardConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 46, height: 46)
                        .foregroundStyle(Theme.danger)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel("Discard workout")
            }
        }
        .cardStyle()
    }

    private var summary: String {
        if app.todayExercises.isEmpty {
            return "Free workout waiting for exercises"
        }
        let done = app.completedSetCount
        let total = app.todayExercises.reduce(0) { $0 + $1.sets.count }
        let count = app.todayExercises.count
        return "\(count) \(count == 1 ? "exercise" : "exercises") · \(done)/\(total) \(total == 1 ? "set" : "sets") done"
    }
}

struct ExerciseSuggestionCard: View {
    let exercise: ExerciseTemplate
    let record: PersonalRecord?
    @State private var showTip = false

    var body: some View {
        Button {
            NativeFeedback.selection()
            withAnimation(AppMotion.quick) {
                showTip.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.system(size: 15, weight: .semibold))
                        Text(meta)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted2)
                    }
                    Spacer()
                    if record != nil {
                        Label("PR", systemImage: "trophy")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .foregroundStyle(.black)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                }
                if showTip {
                    Text(exercise.tip)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(14)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        }
        .foregroundStyle(Theme.text)
        .buttonStyle(TactileButtonStyle())
        .animation(AppMotion.quick, value: showTip)
    }

    private var meta: String {
        var parts = ["\(exercise.sets) sets x \(exercise.reps) \(exercise.timed ? (exercise.minutes ? "min" : "sec") : "reps")"]
        if exercise.bodyweight || exercise.timed { parts.append(exercise.timed ? "Timed" : "Bodyweight") }
        if let record {
            parts.append(record.weight > 0 ? "Best: \(formatWeight(record.weight)) x \(record.reps)" : "Best: BW x \(record.reps)")
        }
        return parts.joined(separator: " · ")
    }
}

struct TitleBlock: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).sectionTitle()
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted2)
        }
    }
}

struct BackButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: "chevron.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted2)
                .padding(.vertical, 4)
        }
        .buttonStyle(TactileButtonStyle())
    }
}

func clean(_ number: Double) -> String {
    number.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(number)) : String(format: "%.1f", number)
}
