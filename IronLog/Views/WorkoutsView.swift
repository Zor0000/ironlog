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
                    case .muscle:
                        muscleStep
                    case .workout:
                        workoutStep
                    }
                }
                .id(app.workoutStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .padding(18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .animation(AppMotion.screen, value: app.workoutStep)
        .animation(AppMotion.quick, value: app.hasActiveWorkout)
        .confirmationDialog("Discard the workout in progress?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard Workout", role: .destructive) {
                NativeFeedback.light()
                withAnimation(AppMotion.smooth) {
                    app.discardWorkout()
                }
            }
            Button("Keep Logging", role: .cancel) {
                app.continueWorkout()
            }
        }
    }

    private var splitStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            TitleBlock(title: "Split Type", subtitle: "Choose your training program")
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
                        .entrance(index)
                    }
                }
            }
        }
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
            TitleBlock(title: "Training Day", subtitle: "Select your training day")
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
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
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

    private var muscleStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            BackButton(label: app.selectedDay.map { "\($0) · \(app.selectedSplit ?? "")" } ?? (app.selectedSplit ?? "Split")) {
                NativeFeedback.selection()
                withAnimation(AppMotion.quick) {
                    if app.selectedDay != nil {
                        app.workoutStep = .day
                        app.selectedDay = nil
                    } else {
                        app.workoutStep = .split
                        app.selectedSplit = nil
                    }
                }
            }
            TitleBlock(title: "Muscle Group", subtitle: "Select today's focus")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                ForEach(Array(app.library.visibleMuscles(split: app.selectedSplit, day: app.selectedDay).enumerated()), id: \.element.id) { index, muscle in
                    Button {
                        NativeFeedback.selection()
                        withAnimation(AppMotion.quick) {
                            app.selectMuscle(muscle.id)
                        }
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: muscle.systemImage)
                                .font(.system(size: 26, weight: .medium))
                                .frame(height: 28)
                            Text(muscle.label)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    }
                    .foregroundStyle(Theme.text)
                    .buttonStyle(TactileButtonStyle())
                    .entrance(index, offset: 12)
                }
            }
        }
    }

    private var workoutStep: some View {
        let muscle = app.library.muscle(app.selectedMuscle)
        let context = [app.selectedSplit, app.selectedDay].compactMap(\.self).joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 10) {
            BackButton(label: muscle?.label ?? "Muscle") {
                NativeFeedback.selection()
                withAnimation(AppMotion.quick) {
                    app.workoutStep = .muscle
                    app.selectedMuscle = nil
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Suggested Workout")
                    .sectionTitle()
                Pill(text: context)
            }
            HStack(spacing: 6) {
                if let muscle {
                    Image(systemName: muscle.systemImage)
                    Text(muscle.label)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted2)

            ForEach(Array(app.library.exercises(split: app.selectedSplit, muscle: app.selectedMuscle).enumerated()), id: \.element.id) { index, exercise in
                ExerciseSuggestionCard(exercise: exercise, record: app.personalRecords[exercise.name])
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .entrance(index)
            }
            Button {
                NativeFeedback.light()
                withAnimation(AppMotion.smooth) {
                    app.startWorkout()
                }
            } label: {
                Label("Start This Workout", systemImage: "play.fill")
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
                        .font(.system(size: 14, weight: .semibold))
                    Text(summary)
                        .font(.system(size: 11))
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
        return "\(app.todayExercises.count) exercises · \(done)/\(total) sets done"
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(meta)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted2)
                    }
                    Spacer()
                    if record != nil {
                        Label("PR", systemImage: "trophy")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .foregroundStyle(.black)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                }
                if showTip {
                    Text(exercise.tip)
                        .font(.system(size: 11))
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
        var parts = ["\(exercise.sets) sets x \(exercise.reps) \(exercise.timed ? "sec" : "reps")"]
        if exercise.bodyweight || exercise.timed { parts.append(exercise.timed ? "Timed" : "Bodyweight") }
        if let record {
            parts.append(record.weight > 0 ? "Best: \(clean(record.weight))kg x \(record.reps)" : "Best: BW x \(record.reps)")
        }
        return parts.joined(separator: " · ")
    }
}

struct TitleBlock: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).sectionTitle()
            Text(subtitle)
                .font(.system(size: 11))
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
