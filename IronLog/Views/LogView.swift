import SwiftUI

struct LogView: View {
    @EnvironmentObject private var app: AppState
    @State private var newExerciseName = ""
    @State private var showDiscardConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TimerCard()
                if app.todayExercises.isEmpty && !app.showAddExerciseForm {
                    emptyState
                } else {
                    activeLog
                }
            }
            .padding(18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .animation(AppMotion.quick, value: app.todayExercises)
        .animation(AppMotion.quick, value: app.showAddExerciseForm)
        .confirmationDialog("Discard the workout in progress?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard Workout", role: .destructive) {
                NativeFeedback.light()
                withAnimation(AppMotion.smooth) {
                    app.discardWorkout()
                }
            }
            Button("Keep Logging", role: .cancel) {}
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "dumbbell")
                .font(.system(size: 46))
                .foregroundStyle(Theme.muted)
            Text("No workout started yet.\nGo to Workouts and pick your muscles.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted2)
            Button {
                NativeFeedback.light()
                withAnimation(AppMotion.smooth) {
                    app.startFreeWorkout()
                }
            } label: {
                Label("Start Free Workout", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("start-free-workout-button")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var activeLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            logHeader
            progressCard

            ForEach(Array(app.todayExercises.enumerated()), id: \.element.id) { index, exercise in
                LogExerciseCard(exercise: exercise)
                    .entrance(index)
            }

            addExerciseBlock

            VStack(alignment: .leading, spacing: 10) {
                Text("Session Note (optional)")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
                TextEditor(text: Binding(
                    get: { app.workoutNote },
                    set: { app.updateWorkoutNote($0) }
                ))
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            }
            .cardStyle()

            Button {
                NativeFeedback.success()
                Task {
                    await app.finishWorkout(note: app.workoutNote)
                }
            } label: {
                Label("Finish & Save Workout", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("finish-workout-button")
        }
    }

    private var logHeader: some View {
        HStack(spacing: 8) {
            Text("Today").sectionTitle()
            let muscle = app.library.muscle(app.selectedMuscle)
            Pill(text: [muscle?.label, app.selectedSplit].compactMap(\.self).joined(separator: " · "))
            Spacer()
            Button {
                NativeFeedback.selection()
                showDiscardConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Theme.danger)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            }
            .buttonStyle(TactileButtonStyle())
        }
    }

    private var progressCard: some View {
        let totalSets = app.todayExercises.reduce(0) { $0 + $1.sets.count }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(app.validCompletedSetCount)/\(totalSets)")
                    .font(.system(size: 28, weight: .black))
                    .fontWidth(.condensed)
                    .foregroundStyle(Theme.accent)
                Text("valid sets ready to save")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(app.todayExercises.count)")
                    .font(.system(size: 28, weight: .black))
                    .fontWidth(.condensed)
                    .foregroundStyle(Theme.text)
                Text("exercises")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted2)
            }
        }
        .cardStyle()
    }

    private var addExerciseBlock: some View {
        Group {
            if app.showAddExerciseForm {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add Exercise")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.muted)
                    TextField("Exercise name", text: $newExerciseName)
                        .fieldStyle()
                        .accessibilityIdentifier("new-exercise-name-field")
                    HStack {
                        Button {
                            NativeFeedback.selection()
                            withAnimation(AppMotion.quick) {
                                app.setAddExerciseWeighted(false)
                            }
                        } label: {
                            Pill(text: "Reps only", isActive: !app.addExerciseWeighted)
                        }
                        .buttonStyle(TactileButtonStyle())
                        Button {
                            NativeFeedback.selection()
                            withAnimation(AppMotion.quick) {
                                app.setAddExerciseWeighted(true)
                            }
                        } label: {
                            Pill(text: "Weight + Reps", isActive: app.addExerciseWeighted)
                        }
                        .buttonStyle(TactileButtonStyle())
                    }
                    HStack {
                        Button("Add") {
                            NativeFeedback.light()
                            withAnimation(AppMotion.quick) {
                                app.addExercise(name: newExerciseName)
                                newExerciseName = ""
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("confirm-add-exercise-button")
                        Button {
                            NativeFeedback.selection()
                            withAnimation(AppMotion.quick) {
                                app.cancelAddingExercise()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 44, height: 44)
                                .background(Theme.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        }
                        .foregroundStyle(Theme.text)
                        .buttonStyle(TactileButtonStyle())
                    }
                }
                .cardStyle()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) {
                        app.beginAddingExercise()
                    }
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(Theme.muted2)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5])))
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityIdentifier("show-add-exercise-button")
            }
        }
    }
}

struct TimerCard: View {
    @EnvironmentObject private var app: AppState
    private let presets = [60, 90, 120, 180]
    private var progress: Double {
        guard app.timerMax > 0 else { return 0 }
        return Double(app.timerSecs) / Double(app.timerMax)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Rest Timer")
                    .font(.system(size: 10))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted2)
                Text(format(app.timerSecs))
                    .font(.system(size: 40, weight: .black))
                    .fontWidth(.condensed)
                    .tracking(2)
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) {
                        app.toggleTimer()
                    }
                } label: {
                    Image(systemName: app.timerRunning ? "pause.fill" : "play.fill")
                        .symbolEffect(.bounce, value: app.timerRunning)
                }
                .timerButton(active: app.timerRunning)
                Button {
                    NativeFeedback.light()
                    withAnimation(AppMotion.quick) {
                        app.resetTimer()
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .timerButton()
                Menu {
                    ForEach(presets, id: \.self) { value in
                        Button(format(value)) {
                            NativeFeedback.selection()
                            app.setTimerPreset(value)
                        }
                    }
                } label: {
                    Text(format(app.timerMax))
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
                .foregroundStyle(Theme.text)
            }
        }
        .cardStyle()
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.accent.opacity(app.timerRunning ? 0.28 : 0), lineWidth: 1)
        }
        .overlay(alignment: .bottomLeading) {
            Capsule()
                .fill(Theme.accent.opacity(app.timerRunning ? 0.95 : 0.28))
                .frame(height: 3)
                .scaleEffect(x: progress, y: 1, anchor: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 1)
        }
        .animation(AppMotion.quick, value: app.timerRunning)
        .animation(.linear(duration: 0.2), value: app.timerSecs)
    }

    private func format(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

struct LogExerciseCard: View {
    @EnvironmentObject private var app: AppState
    let exercise: ActiveExercise

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) {
                        app.toggleExercise(exercise.id)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(exercise.name)
                                    .font(.system(size: 13, weight: .semibold))
                                if exercise.bodyweight {
                                    SmallBadge("Bodyweight")
                                }
                                if exercise.timed {
                                    SmallBadge("Timed")
                                }
                            }
                            Text("\(exercise.sets.filter(\.done).count)/\(exercise.sets.count) sets done")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted2)
                            .rotationEffect(.degrees(exercise.expanded ? 90 : 0))
                    }
                    .frame(maxWidth: .infinity)
                }
                .foregroundStyle(Theme.text)
                .buttonStyle(TactileButtonStyle())

                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) {
                        app.removeExercise(exercise.id)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Theme.muted2)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
                }
                .buttonStyle(TactileButtonStyle())
            }
            .padding(14)

            if exercise.expanded {
                VStack(spacing: 8) {
                    ForEach(exercise.sets) { set in
                        setRow(set)
                    }
                    Button {
                        NativeFeedback.light()
                        withAnimation(AppMotion.quick) {
                            app.addSet(to: exercise.id)
                        }
                    } label: {
                        Label("Add Set", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(Theme.muted2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5])))
                    }
                    .buttonStyle(TactileButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 13)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(exercise.expanded ? Theme.accent.opacity(0.24) : Theme.border))
        .animation(AppMotion.quick, value: exercise.expanded)
    }

    private func setRow(_ set: WorkoutSet) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text("\((exercise.sets.firstIndex(where: { $0.id == set.id }) ?? 0) + 1)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .frame(width: 20, height: 34, alignment: .bottom)

            if !exercise.bodyweight && !exercise.timed {
                SmallInput(label: "KG", value: set.weight, identifier: "set-weight-input") { value in
                    app.updateSet(exerciseID: exercise.id, setID: set.id, weight: value)
                }
            }
            SmallInput(label: exercise.timed ? "SECS" : "REPS", value: set.reps, identifier: "set-reps-input") { value in
                app.updateSet(exerciseID: exercise.id, setID: set.id, reps: value)
            }
            Button {
                NativeFeedback.success()
                withAnimation(AppMotion.quick) {
                    app.toggleDone(exerciseID: exercise.id, setID: set.id)
                }
            } label: {
                Image(systemName: set.done ? "checkmark" : "circle")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(set.done ? .black : Theme.muted2)
                    .background(set.done ? Theme.success : .clear)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(set.done ? Theme.success : Theme.border, lineWidth: 1.5))
                    .symbolEffect(.bounce, value: set.done)
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityIdentifier("set-done-button")

            Button {
                NativeFeedback.selection()
                withAnimation(AppMotion.quick) {
                    app.removeSet(exerciseID: exercise.id, setID: set.id)
                }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 34)
                    .foregroundStyle(exercise.sets.count > 1 ? Theme.muted2 : Theme.muted)
            }
            .buttonStyle(TactileButtonStyle())
            .disabled(exercise.sets.count <= 1)
        }
    }
}

struct SmallInput: View {
    let label: String
    let value: String
    var identifier: String?
    let onChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Theme.muted2)
            TextField("0", text: Binding(get: { value }, set: onChange))
                .keyboardType(label == "KG" ? .decimalPad : .numberPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(8)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                .accessibilityIdentifier(identifier ?? "\(label.lowercased())-input")
        }
    }
}

struct SmallBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.blue)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.blue.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.blue.opacity(0.25)))
    }
}

extension View {
    func timerButton(active: Bool = false) -> some View {
        font(.system(size: 15, weight: .bold))
            .frame(width: 38, height: 38)
            .foregroundStyle(active ? .black : Theme.text)
            .background(active ? Theme.accent : Theme.surface2)
            .clipShape(Circle())
            .overlay(Circle().stroke(active ? Theme.accent : Theme.border, lineWidth: 1.5))
    }
}
