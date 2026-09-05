import SwiftUI

private struct PendingDeleteSet: Equatable {
    let exerciseID: UUID
    let setID: UUID
}

struct LogView: View {
    @EnvironmentObject private var app: AppState
    @State private var showDiscardConfirmation = false
    @State private var pendingDelete: ActiveExercise?
    @State private var pendingDeleteSet: PendingDeleteSet?
    @State private var showSaveRoutine = false
    @State private var showFinishConfirmation = false
    @State private var routineName = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TimerCard()
                if !app.hasActiveWorkout {
                    emptyState
                } else {
                    activeLog
                }
            }
            .padding(18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .keepsNoteVisible(proxy, focused: noteFocused, text: app.workoutNote)
        .animation(AppMotion.quick, value: app.todayExercises)
        .animation(AppMotion.quick, value: app.showAddExerciseForm)
        .discardWorkoutOverlay(isPresented: $showDiscardConfirmation)
        .alert("Remove exercise?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { exercise in
            Button("Keep It", role: .cancel) { pendingDelete = nil }
            Button("Remove Exercise", role: .destructive) { app.removeExercise(exercise.id); pendingDelete = nil }
        } message: { exercise in
            Text("\(exercise.name) and all its sets will be removed from this workout.")
        }
        .animation(AppMotion.quick, value: pendingDelete)
        .alert("Remove set?", isPresented: Binding(get: { pendingDeleteSet != nil }, set: { if !$0 { pendingDeleteSet = nil } }), presenting: pendingDeleteSet) { target in
            Button("Keep It", role: .cancel) { pendingDeleteSet = nil }
            Button("Remove Set", role: .destructive) {
                app.removeSet(exerciseID: target.exerciseID, setID: target.setID)
                pendingDeleteSet = nil
            }
        } message: { _ in Text(deleteSetMessage) }
        .animation(AppMotion.quick, value: pendingDeleteSet)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "dumbbell")
                .font(.largeTitle)
                .foregroundStyle(Theme.muted)
            Text("No workout started yet.\nGo to Workouts and pick your muscles.")
                .font(.subheadline)
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
                LogExerciseCard(exercise: exercise, onConfirmDelete: { pendingDelete = exercise }, onConfirmDeleteSet: { exerciseID, setID in pendingDeleteSet = PendingDeleteSet(exerciseID: exerciseID, setID: setID) })
                    .entrance(index)
            }

            addExerciseBlock

            VStack(alignment: .leading, spacing: 10) {
                Text("Session Note (optional)")
                    .cardLabel()
                TextEditor(text: Binding(
                    get: { app.workoutNote },
                    set: { app.updateWorkoutNote($0) }
                ))
                    .focused($noteFocused)
                    .accessibilityLabel("Session note")
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            }
            .cardStyle()
            .id(sessionNoteAnchor)

            Button {
                if app.todayExercises.contains(where: { $0.sets.contains(where: { !$0.done }) }) {
                    showFinishConfirmation = true
                } else {
                    Task { await app.finishWorkout(note: app.workoutNote) }
                }
            } label: {
                Label("Finish & Save Workout", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("finish-workout-button")
            .disabled(app.validCompletedSetCount == 0)

            Text(app.validCompletedSetCount == 0
                 ? "Enter reps or duration and mark at least one set done to save. Weighted exercises also need a weight."
                 : "Only completed sets are saved. Unfinished sets will be left out.")
                .font(.footnote)
                .foregroundStyle(Theme.muted2)

            if !app.todayExercises.isEmpty {
                Button {
                    NativeFeedback.selection()
                    // Prefill when this workout came from a routine, so the
                    // common case — tweaking your staple — updates it in place
                    // instead of quietly making a near-duplicate.
                    routineName = app.matchingRoutineName ?? ""
                    showSaveRoutine = true
                } label: {
                    Label("Save as Routine", systemImage: "bookmark")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("save-routine-button")
            }
        }
        .sheet(isPresented: $showSaveRoutine) {
            NavigationStack {
                Form {
                    Section("Routine name") {
                        TextField("e.g. Leg Day", text: $routineName)
                            .accessibilityIdentifier("routine-name-field")
                    }
                    Section {
                        Text(routineExists
                             ? "Replace the exercises and set counts in the existing routine named \(routineName)?"
                             : "Keep these \(app.todayExercises.count) exercises to start again from Workouts.")
                        Button(routineExists ? "Replace Routine" : "Save Routine", role: routineExists ? .destructive : nil) {
                            app.saveRoutine(name: routineName)
                            showSaveRoutine = false
                            routineName = ""
                        }
                        .disabled(routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle("Save as Routine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSaveRoutine = false; routineName = "" }
                    }
                }
            }
            .keyboardDismissControl()
            .presentationDetents([.medium, .large])
        }
        .alert("Finish with unfinished sets?", isPresented: $showFinishConfirmation) {
            Button("Keep Logging", role: .cancel) { }
            Button("Save Completed Sets", role: .destructive) {
                Task { await app.finishWorkout(note: app.workoutNote) }
            }
        } message: {
            Text("Save \(app.validCompletedSetCount) completed sets? Unfinished sets will be discarded.")
        }


    }

    private var routineExists: Bool {
        app.routines.contains { $0.name.caseInsensitiveCompare(routineName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
    }

    private var deleteSetMessage: String {
        guard let target = pendingDeleteSet,
              let exercise = app.todayExercises.first(where: { $0.id == target.exerciseID }),
              let index = exercise.sets.firstIndex(where: { $0.id == target.setID }) else { return "Remove this set?" }
        return "Set \(index + 1) of \(exercise.name) and its entered values will be removed."
    }

    private var logHeader: some View {
        AdaptiveStack(spacing: 8) {
            Text("Today").sectionTitle()
            Pill(text: contextLabel)
            Spacer()
            Button {
                NativeFeedback.selection()
                showDiscardConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Theme.danger)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityLabel("Discard workout")
        }
    }

    /// Muscle label + split, deduped — a free workout has both equal to "Free Workout".
    private var contextLabel: String {
        let muscle = app.selectedWorkoutMuscleLabel
        let split = app.selectedSplit ?? ""
        return split.isEmpty || split == muscle ? muscle : "\(muscle) · \(split)"
    }

    private var progressCard: some View {
        let totalSets = app.todayExercises.reduce(0) { $0 + $1.sets.count }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(app.validCompletedSetCount)/\(totalSets)")
                    .font(.title.weight(.black))
                    .fontWidth(.condensed)
                    .foregroundStyle(Theme.accent)
                Text("valid sets ready to save")
                    .font(.caption)
                    .foregroundStyle(Theme.muted2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(app.todayExercises.count)")
                    .font(.title.weight(.black))
                    .fontWidth(.condensed)
                    .foregroundStyle(Theme.text)
                Text("exercises")
                    .font(.caption)
                    .foregroundStyle(Theme.muted2)
            }
        }
        .cardStyle()
    }

    private var addExerciseBlock: some View {
        Group {
            if app.showAddExerciseForm {
                addExerciseForm
                    .cardStyle()
                    // Fade in place — see LogExerciseCard: translating a
                    // collapsing card drags its content across its neighbours.
                    .transition(.opacity)
            } else {
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) {
                        app.beginAddingExercise()
                    }
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
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

    private var addExerciseForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add Exercise")
                    .cardLabel()
                Spacer()
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) { app.cancelAddingExercise() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Theme.muted2)
                        .background(Theme.surface2)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.border))
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel("Close add exercise")
            }

            ExerciseCatalogPicker(
                library: app.library,
                initialMuscle: app.singleTargetMuscle
            ) { template in
                withAnimation(AppMotion.quick) { app.addExercise(template: template) }
            }

            customExerciseSection
        }
    }

    /// The weighted choice stays in the draft, so it survives a relaunch
    /// mid-workout — hence the binding through `setAddExerciseWeighted`.
    private var customExerciseSection: some View {
        CustomExerciseField(
            weighted: Binding(
                get: { app.addExerciseWeighted },
                set: { app.setAddExerciseWeighted($0) }
            )
        ) { name in
            app.addExercise(name: name)
        }
    }
}

struct TimerCard: View {
    @EnvironmentObject private var app: AppState
    private var progress: Double {
        guard app.timerMax > 0 else { return 0 }
        return Double(app.timerSecs) / Double(app.timerMax)
    }

    var body: some View {
        AdaptiveStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Rest Timer")
                    .font(.caption)
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted2)
                Text(formatDuration(app.timerSecs))
                    .font(.largeTitle.weight(.black))
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
                .accessibilityLabel(app.timerRunning ? "Pause rest timer" : "Start rest timer")
                Button {
                    NativeFeedback.light()
                    withAnimation(AppMotion.quick) {
                        app.resetTimer()
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .timerButton()
                .accessibilityLabel("Reset rest timer")
                Menu {
                    ForEach(restTimerPresets, id: \.self) { value in
                        Button(formatDuration(value)) {
                            NativeFeedback.selection()
                            app.setTimerPreset(value)
                        }
                    }
                } label: {
                    Text(formatDuration(app.timerMax))
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
                .foregroundStyle(Theme.text)
                .accessibilityLabel("Rest duration")
                .accessibilityValue(formatDuration(app.timerMax))
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
}

struct LogExerciseCard: View {
    @EnvironmentObject private var app: AppState
    let exercise: ActiveExercise
    /// All exercise removals require an explicit confirmation.
    var onConfirmDelete: () -> Void = {}
    /// Called when the user taps the minus-circle button to remove a set.
    var onConfirmDeleteSet: (UUID, UUID) -> Void = { _, _ in }

    var body: some View {
        // Previous-set reference for this exercise (most recent prior session).
        let reference = app.lastPerformance(exerciseName: exercise.name)
        return VStack(spacing: 0) {
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
                                    .font(.subheadline.weight(.semibold))
                                if exercise.bodyweight {
                                    SmallBadge("Bodyweight")
                                }
                                if exercise.timed {
                                    SmallBadge("Timed")
                                }
                            }
                            Text("\(exercise.sets.filter(\.done).count)/\(exercise.sets.count) \(exercise.sets.count == 1 ? "set" : "sets") done")
                                .font(.caption)
                                .foregroundStyle(Theme.muted2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.muted2)
                            .rotationEffect(.degrees(exercise.expanded ? 90 : 0))
                    }
                    .frame(maxWidth: .infinity)
                }
                .foregroundStyle(Theme.text)
                .buttonStyle(TactileButtonStyle())

                Button {
                    NativeFeedback.selection()
                    onConfirmDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.muted2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel("Remove \(exercise.name)")
                .accessibilityIdentifier("remove-exercise-button")
            }
            .padding(14)

            if exercise.expanded {
                VStack(spacing: 8) {
                    ForEach(exercise.sets) { set in
                        setRow(set, reference: reference)
                    }
                    Button {
                        NativeFeedback.light()
                        withAnimation(AppMotion.quick) {
                            app.addSet(to: exercise.id)
                        }
                    } label: {
                        Label("Add Set", systemImage: "plus")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .frame(minHeight: 44)
                            .foregroundStyle(Theme.muted2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5])))
                    }
                    .buttonStyle(TactileButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 13)
                // Fade in place — the card's own height change does the
                // collapsing. Translating the rows (e.g. .move(edge: .top))
                // slides them through the header text mid-animation.
                .transition(.opacity)
            }
        }
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(exercise.expanded ? Theme.accent.opacity(0.24) : Theme.border))
        .animation(AppMotion.quick, value: exercise.expanded)
    }

    private func setRow(_ set: WorkoutSet, reference: LoggedExercise?) -> some View {
        let index = exercise.sets.firstIndex(where: { $0.id == set.id }) ?? 0
        // Same set index from last time, falling back to that session's last set.
        let refSet = reference.map { $0.sets.indices.contains(index) ? $0.sets[index] : $0.sets.last } ?? nil

        return VStack(alignment: .leading, spacing: 3) {
            AdaptiveStack {
                Text("Set \(index + 1)").font(.subheadline.weight(.semibold))
                Spacer()
                SetTypeMenu(type: Binding(
                    get: { set.type },
                    set: { app.setType(exerciseID: exercise.id, setID: set.id, to: $0) }
                ))
                Button(role: .destructive) {
                    onConfirmDeleteSet(exercise.id, set.id)
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
                .disabled(exercise.sets.count <= 1)
                .accessibilityLabel("Remove set \(index + 1) of \(exercise.name)")
                .accessibilityIdentifier("remove-set-button")
                .accessibilityHint(exercise.sets.count <= 1 ? "Keep one set, or remove the exercise." : "Asks for confirmation.")
            }
            .foregroundStyle(Theme.muted2)
            HStack(alignment: .bottom, spacing: 8) {
                if !exercise.timed {
                    // Label + reference placeholder follow the display unit;
                    // typed input converts back to kg at the save boundary.
                    // Bodyweight exercises get the field too — walking lunges,
                    // pull-ups and dips are routinely loaded.
                    SmallInput(label: currentWeightUnit.fieldLabel, value: set.weight, placeholder: exercise.bodyweight ? "BW" : "0", keyboard: .decimalPad, identifier: "set-weight-input", context: "\(exercise.name), set \(index + 1),") { value in
                        app.updateSet(exerciseID: exercise.id, setID: set.id, weight: value)
                    }
                }
                // Decimal pad only where halves mean something — a timed set's
                // field is seconds/minutes, and `updateSet` strips the point.
                SmallInput(label: exercise.timed ? durationFieldLabel(minutes: exercise.usesMinutes) : "REPS", value: set.reps, placeholder: "0", keyboard: exercise.timed ? .numberPad : .decimalPad, identifier: "set-reps-input", context: "\(exercise.name), set \(index + 1),") { value in
                    app.updateSet(exerciseID: exercise.id, setID: set.id, reps: value)
                }
                Button {
                    NativeFeedback.selection()
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation(AppMotion.quick) {
                        app.toggleDone(exerciseID: exercise.id, setID: set.id)
                    }
                } label: {
                    Image(systemName: set.done ? "checkmark" : "circle")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(set.done ? .black : Theme.muted2)
                        .background(set.done ? Theme.success : .clear)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(set.done ? Theme.success : Theme.border, lineWidth: 1.5))
                        .symbolEffect(.bounce, value: set.done)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityIdentifier("set-done-button")
                .accessibilityLabel("Set \(index + 1) of \(exercise.name), \(set.done ? "mark not done" : "mark done")")
                .accessibilityValue(set.done ? "Completed" : "Not completed")

            }

            if let subtitle = setSubtitle(set, refSet) {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(set.type == nil ? Theme.muted : Theme.accent.opacity(0.85))
                    .accessibilityIdentifier("set-reference")
            }
        }
    }

    /// The set's tag and last time's numbers share one line, so a tag costs no
    /// vertical space in a row that already had none to give.
    private func setSubtitle(_ set: WorkoutSet, _ refSet: LoggedSet?) -> String? {
        let parts = [set.type?.label, referenceLabel(refSet)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Muted "Last: …" hint mirroring the web client's `.set-ref` line.
    private func referenceLabel(_ refSet: LoggedSet?) -> String? {
        guard let refSet else { return nil }
        if exercise.timed { return "Last: \(formatLoggedDuration(Int(refSet.reps), minutes: exercise.usesMinutes))" }
        // Weight presence decides, not the bodyweight flag — a loaded lunge
        // logs its weight and should show it back.
        guard let weight = refSet.weight, weight > 0 else { return "Last: \(clean(refSet.reps)) reps" }
        return "Last: \(formatWeight(weight)) × \(clean(refSet.reps))"
    }
}

/// Tag a set as a warm-up, drop set and so on. A `Picker` inside the menu
/// checkmarks the current choice and carries "Normal set" as the way back, so
/// there is no separate clear action to find.
///
/// Takes a plain `Binding` so the live log (which writes through `AppState`)
/// and the session editor (which writes into its own draft) share one menu.
struct SetTypeMenu: View {
    @Binding var type: SetType?

    var body: some View {
        Menu {
            Picker("Set type", selection: Binding(
                get: { type },
                set: { newValue in
                    NativeFeedback.selection()
                    type = newValue
                }
            )) {
                Text("Normal set").tag(SetType?.none)
                ForEach(SetType.allCases, id: \.self) { type in
                    Label(type.label, systemImage: type.icon).tag(SetType?.some(type))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(type?.label ?? "Type", systemImage: "tag")
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
                .foregroundStyle(type == nil ? Theme.muted2 : Theme.accent)
        }
        .accessibilityIdentifier("set-type-button")
        .accessibilityLabel(type.map { "Set type: \($0.label)" } ?? "Set type")
    }
}

struct SmallInput: View {
    let label: String
    let value: String
    var placeholder: String = "0"
    var keyboard: UIKeyboardType = .numberPad
    var identifier: String?
    var context = ""
    let onChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Every input keeps a label, including repeated rows.
            if !label.isEmpty {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted2)
            }
            TextField(placeholder, text: Binding(get: { value }, set: onChange))
                .keyboardType(keyboard)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .padding(8)
                .frame(minHeight: 44)
                .accessibilityLabel("\(context) \(label)".trimmingCharacters(in: .whitespaces))
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                .accessibilityIdentifier(identifier ?? "\(label.lowercased())-input")
        }
    }
}

/// "Or add your own" — free-text name plus a reps-only / weight+reps choice,
/// shared by the live log and the session editor. The caller owns where the
/// exercise lands and how the weighted choice is persisted (the live log routes
/// it through the workout draft; the editor keeps it in view state).
struct CustomExerciseField: View {
    @Binding var weighted: Bool
    let onAdd: (String) -> Void

    @State private var name = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Rectangle().fill(Theme.border).frame(height: 1)
                Text("Or add your own")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
                Rectangle().fill(Theme.border).frame(height: 1)
            }

            TextField("Custom exercise name", text: $name)
                .fieldStyle()
                .submitLabel(.done)
                .accessibilityIdentifier("new-exercise-name-field")

            HStack(spacing: 8) {
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) { weighted = false }
                } label: {
                    Pill(text: "Reps only", isActive: !weighted)
                }
                .buttonStyle(TactileButtonStyle())
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) { weighted = true }
                } label: {
                    Pill(text: "Weight + Reps", isActive: weighted)
                }
                .buttonStyle(TactileButtonStyle())
                Spacer(minLength: 0)
            }

            Button {
                NativeFeedback.light()
                withAnimation(AppMotion.quick) {
                    onAdd(trimmedName)
                    name = ""
                }
            } label: {
                Label("Add Custom Exercise", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(trimmedName.isEmpty)
            .animation(AppMotion.quick, value: trimmedName.isEmpty)
            .accessibilityIdentifier("confirm-add-exercise-button")
        }
    }
}

/// Catalog browser shared by the live log and the session editor: search field,
/// muscle chips and result rows. Owns its own query state and hands the chosen
/// template back — the caller decides where the exercise lands.
struct ExerciseCatalogPicker: View {
    let library: ExerciseLibrary
    /// Muscle chip pre-selected on first appearance (the workout's target), if
    /// that muscle has catalog entries.
    var initialMuscle: String?
    let onSelect: (ExerciseTemplate) -> Void

    @State private var search = ""
    @State private var filter: String?
    @State private var didPrime = false
    @FocusState private var searchFocused: Bool

    @State private var resultLimit = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchField
            muscleFilterChips
            if showResults {
                resultsList
            } else {
                hint
            }
        }
        .onAppear(perform: prime)
        .onChange(of: search) { _, _ in resultLimit = 24 }
        .onChange(of: filter) { _, _ in resultLimit = 24 }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.muted2)
            TextField("Search exercises — e.g. walking lunges", text: $search)
                .font(.subheadline)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
            if !search.isEmpty {
                Button {
                    NativeFeedback.selection()
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 44, height: 44)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(searchFocused ? Theme.accent.opacity(0.5) : Theme.border))
        .accessibilityIdentifier("exercise-template-search-field")
    }

    private var muscleFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                filterChip(title: "All", id: nil)
                ForEach(library.catalogMuscles) { muscle in
                    filterChip(title: muscle.label, id: muscle.id, icon: muscle.systemImage)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func filterChip(title: String, id: String?, icon: String? = nil) -> some View {
        Button {
            NativeFeedback.selection()
            withAnimation(AppMotion.quick) { filter = id }
        } label: {
            Pill(text: title, icon: icon, isActive: filter == id)
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel("\(title) exercises")
        .accessibilityAddTraits(filter == id ? .isSelected : [])
    }

    private var resultsList: some View {
        let results = self.results
        return VStack(spacing: 7) {
            ForEach(results.prefix(resultLimit)) { item in
                Button {
                    NativeFeedback.light()
                    onSelect(item.template)
                    search = ""
                    searchFocused = false
                } label: {
                    row(item)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityIdentifier("exercise-template-\(item.template.name)")
            }

            if results.isEmpty {
                VStack(spacing: 4) {
                    Text("No matching exercises")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("Try fewer words — search covers the whole library.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else if results.count > resultLimit {
                Button("Show more exercises (\(results.count - resultLimit) remaining)") { resultLimit += 24 }
                    .frame(minHeight: 44)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
        }
        .transition(.opacity)
    }

    private func row(_ item: CatalogExercise) -> some View {
        let template = item.template
        let icon = template.timed ? "timer" : (template.bodyweight ? "figure.strengthtraining.functional" : "dumbbell")
        return HStack(spacing: 11) {
            ZStack {
                Circle().fill(Theme.accentDim).frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    if filter == nil {
                        Text(item.muscle.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.muted2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.bg.opacity(0.5))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                    }
                }
                Text(meta(template))
                    .font(.caption)
                    .foregroundStyle(Theme.muted2)
            }
            Spacer(minLength: 6)
            Image(systemName: "plus.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.accent)
        }
        .padding(11)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border.opacity(0.8)))
    }

    private var hint: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text("Search or tap a muscle group to browse the full exercise library.")
                .font(.footnote)
                .foregroundStyle(Theme.muted2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showResults: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != nil
    }

    private var results: [CatalogExercise] {
        library.catalogExercises(muscleID: filter, query: search)
    }

    private func meta(_ template: ExerciseTemplate) -> String {
        var parts = ["\(template.sets)×\(template.reps) \(template.timed ? (template.minutes ? "min" : "sec") : "reps")"]
        if template.bodyweight || template.timed {
            parts.append(template.timed ? "Timed" : "Bodyweight")
        }
        return parts.joined(separator: " · ")
    }

    private func prime() {
        guard !didPrime else { return }
        didPrime = true
        if filter == nil, let muscle = initialMuscle, library.library[muscle] != nil {
            filter = muscle
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
            .font(.caption2.weight(.semibold))
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
            .frame(width: 44, height: 44)
            .foregroundStyle(active ? .black : Theme.text)
            .background(active ? Theme.accent : Theme.surface2)
            .clipShape(Circle())
            .overlay(Circle().stroke(active ? Theme.accent : Theme.border, lineWidth: 1.5))
    }
}
