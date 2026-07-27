import SwiftUI

struct LogView: View {
    @EnvironmentObject private var app: AppState
    @State private var showDiscardConfirmation = false
    @State private var pendingDelete: ActiveExercise?
    @FocusState private var noteFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
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
        .keepsNoteVisible(proxy, focused: noteFocused, text: app.workoutNote)
        .animation(AppMotion.quick, value: app.todayExercises)
        .animation(AppMotion.quick, value: app.showAddExerciseForm)
        .discardWorkoutOverlay(isPresented: $showDiscardConfirmation)
        .overlay {
            if let pendingDelete {
                ConfirmActionModal(
                    title: "Remove exercise?",
                    message: "\(pendingDelete.name) and its logged sets will be removed from this workout.",
                    confirmTitle: "Remove Exercise",
                    cancelTitle: "Keep It",
                    systemImage: "trash"
                ) {
                    withAnimation(AppMotion.smooth) {
                        app.removeExercise(pendingDelete.id)
                        self.pendingDelete = nil
                    }
                } cancel: {
                    withAnimation(AppMotion.quick) { self.pendingDelete = nil }
                }
            }
        }
        .animation(AppMotion.quick, value: pendingDelete)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "dumbbell")
                .font(.system(size: 46))
                .foregroundStyle(Theme.muted)
            Text("No workout started yet.\nGo to Workouts and pick your muscles.")
                .font(.system(size: 14))
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
                LogExerciseCard(exercise: exercise, onConfirmDelete: { pendingDelete = exercise })
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
            Pill(text: contextLabel)
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
                    .font(.system(size: 28, weight: .black))
                    .fontWidth(.condensed)
                    .foregroundStyle(Theme.accent)
                Text("valid sets ready to save")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(app.todayExercises.count)")
                    .font(.system(size: 28, weight: .black))
                    .fontWidth(.condensed)
                    .foregroundStyle(Theme.text)
                Text("exercises")
                    .font(.system(size: 11))
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
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
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
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Rest Timer")
                    .font(.system(size: 11))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted2)
                Text(formatDuration(app.timerSecs))
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
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(height: 38)
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
    /// Called instead of deleting outright when the exercise already has logged work.
    var onConfirmDelete: () -> Void = {}

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
                                    .font(.system(size: 15, weight: .semibold))
                                if exercise.bodyweight {
                                    SmallBadge("Bodyweight")
                                }
                                if exercise.timed {
                                    SmallBadge("Timed")
                                }
                            }
                            Text("\(exercise.sets.filter(\.done).count)/\(exercise.sets.count) \(exercise.sets.count == 1 ? "set" : "sets") done")
                                .font(.system(size: 12))
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
                    if exercise.hasLoggedData {
                        onConfirmDelete()
                    } else {
                        withAnimation(AppMotion.quick) {
                            app.removeExercise(exercise.id)
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.muted2)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel("Remove \(exercise.name)")
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
        let hasRefWeight = (refSet?.weight ?? 0) > 0
        // Bodyweight moves hint "BW" — blank keeps the set unloaded, a number loads it.
        let weightPlaceholder = hasRefWeight
            ? formatWeightValue(refSet!.weight!)
            : (exercise.bodyweight ? "BW" : "0")

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 20, height: 34, alignment: .bottom)

                if !exercise.timed {
                    // Label + reference placeholder follow the display unit;
                    // typed input converts back to kg at the save boundary.
                    // Bodyweight exercises get the field too — walking lunges,
                    // pull-ups and dips are routinely loaded.
                    SmallInput(label: index == 0 ? currentWeightUnit.fieldLabel : "", value: set.weight, placeholder: weightPlaceholder, keyboard: .decimalPad, identifier: "set-weight-input") { value in
                        app.updateSet(exerciseID: exercise.id, setID: set.id, weight: value)
                    }
                }
                SmallInput(label: index == 0 ? (exercise.timed ? "SECS" : "REPS") : "", value: set.reps, placeholder: refSet.map { String($0.reps) } ?? "0", keyboard: .numberPad, identifier: "set-reps-input") { value in
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
                .accessibilityLabel(set.done ? "Mark set not done" : "Mark set done")

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
                .accessibilityLabel("Remove set")
            }

            if let refText = referenceLabel(refSet) {
                Text(refText)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 28)
                    .accessibilityIdentifier("set-reference")
            }
        }
    }

    /// Muted "Last: …" hint mirroring the web client's `.set-ref` line.
    private func referenceLabel(_ refSet: LoggedSet?) -> String? {
        guard let refSet else { return nil }
        if exercise.timed { return "Last: \(refSet.reps)s" }
        // Weight presence decides, not the bodyweight flag — a loaded lunge
        // logs its weight and should show it back.
        guard let weight = refSet.weight, weight > 0 else { return "Last: \(refSet.reps) reps" }
        return "Last: \(formatWeight(weight)) × \(refSet.reps)"
    }
}

struct SmallInput: View {
    let label: String
    let value: String
    var placeholder: String = "0"
    var keyboard: UIKeyboardType = .numberPad
    var identifier: String?
    let onChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Empty label = no header row; callers show it on the first set only.
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted2)
            }
            TextField(placeholder, text: Binding(get: { value }, set: onChange))
                .keyboardType(keyboard)
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
                    .font(.system(size: 10, weight: .semibold))
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
            // PrimaryButtonStyle has no disabled look, so dim it here — and the
            // editor's sheet covers the toast layer, so a blocked tap there
            // would otherwise give no feedback at all.
            .opacity(trimmedName.isEmpty ? 0.45 : 1)
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

    private let resultLimit = 24

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
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted2)
            TextField("Search exercises — e.g. walking lunges", text: $search)
                .font(.system(size: 14))
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
                        .font(.system(size: 15))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Try fewer words — search covers the whole library.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else if results.count > resultLimit {
                Text("+\(results.count - resultLimit) more — keep typing to narrow")
                    .font(.system(size: 12))
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
                Circle().fill(Theme.accentDim).frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if filter == nil {
                        Text(item.muscle.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.bg.opacity(0.5))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                    }
                }
                Text(meta(template))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted2)
            }
            Spacer(minLength: 6)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 19, weight: .bold))
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Search or tap a muscle group to browse the full exercise library.")
                .font(.system(size: 13))
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
        var parts = ["\(template.sets)×\(template.reps) \(template.timed ? "sec" : "reps")"]
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
            .font(.system(size: 10, weight: .semibold))
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
