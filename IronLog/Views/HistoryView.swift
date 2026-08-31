import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    @State private var deleteTarget: WorkoutSession?
    @State private var editTarget: WorkoutSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TitleBlock(title: "History", subtitle: "All your past sessions")
                HStack(spacing: 10) {
                    Text(app.syncMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted2)
                    Spacer()
                    Button {
                        NativeFeedback.selection()
                        Task { await app.syncNow() }
                    } label: {
                        Label(app.user?.isLocal == true ? "Set Up Sync" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(Theme.text)
                            .background(Theme.surface2)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                    }
                    .buttonStyle(TactileButtonStyle())
                }

                if app.sessions.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(app.sessions.enumerated()), id: \.element.id) { index, session in
                        HistoryCard(session: session, deleteTarget: $deleteTarget, editTarget: $editTarget)
                            .entrance(index)
                    }
                }
            }
            .padding(18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .animation(AppMotion.quick, value: app.sessions)
        .animation(AppMotion.quick, value: deleteTarget)
        .overlay {
            if let target = deleteTarget {
                ConfirmActionModal(
                    title: "Delete this session?",
                    message: "\(target.createdAt.displayDay) will be permanently removed from your history\(target.cloudID != nil ? " and the cloud" : ""). This can't be undone.",
                    confirmTitle: "Delete Session",
                    cancelTitle: "Keep It",
                    systemImage: "trash"
                ) {
                    withAnimation(AppMotion.smooth) {
                        deleteTarget = nil
                    }
                    Task { await app.deleteSession(target.id) }
                } cancel: {
                    withAnimation(AppMotion.quick) {
                        deleteTarget = nil
                    }
                }
            }
        }
        .sheet(item: $editTarget) { session in
            EditSessionSheet(session: session)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundStyle(Theme.muted)
            Text("No sessions yet.\nComplete your first workout.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }
}

struct HistoryCard: View {
    @EnvironmentObject private var app: AppState
    let session: WorkoutSession
    @Binding var deleteTarget: WorkoutSession?
    @Binding var editTarget: WorkoutSession?
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) {
                        expanded.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.createdAt.displayDay)
                                .font(.system(size: 15, weight: .semibold))
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted2)
                        }
                        Spacer()
                        if let muscle = app.library.muscle(session.muscle) {
                            Pill(text: muscle.label)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted2)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .frame(maxWidth: .infinity)
                }
                .foregroundStyle(Theme.text)
                .buttonStyle(TactileButtonStyle())
                .accessibilityIdentifier("history-card-toggle")
                .accessibilityLabel("\(session.createdAt.displayDay), \(session.split ?? "Workout"), \(expanded ? "collapse" : "expand")")

                // A run has no sets to edit, and the editor would refuse to save
                // it ("Keep at least one valid set").
                if !session.isCardio {
                    Button {
                        NativeFeedback.selection()
                        editTarget = session
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(Theme.muted2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    }
                    .buttonStyle(TactileButtonStyle())
                    .accessibilityIdentifier("edit-session-button")
                    .accessibilityLabel("Edit session from \(session.createdAt.displayDay)")
                }

                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) {
                        deleteTarget = session
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(Theme.muted2)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel("Delete session from \(session.createdAt.displayDay)")
            }
            .padding(14)

            if expanded {
                VStack(spacing: 0) {
                    if let activity = session.activity {
                        cardioDetail(activity)
                    }
                    ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                        HStack(alignment: .top) {
                            Text(exercise.name)
                                .font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 12)
                            // One line per set, not a comma-joined run-on: a set
                            // tag ("Warm-up · 60 kg x 10") makes that string long
                            // enough to wrap into an unreadable block.
                            VStack(alignment: .trailing, spacing: 3) {
                                ForEach(exercise.sets) { set in
                                    Text(setLabel(set, in: exercise))
                                        .font(.system(size: 12))
                                        .foregroundStyle(set.type == nil ? Theme.muted2 : Theme.accent.opacity(0.85))
                                }
                            }
                            .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .top)
                        .entrance(index, offset: 8)
                    }

                    if let note = session.note, !note.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "note.text")
                            Text(note)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .top)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(expanded ? Theme.accent.opacity(0.24) : Theme.border))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(AppMotion.quick, value: expanded)
    }

    private var setCount: Int {
        session.exercises.reduce(0) { $0 + $1.sets.count }
    }

    /// A run's headline is its distance, not its (zero) set count. An indoor
    /// session with no distance at all leads with the time instead of "0.00 km".
    private var subtitle: String {
        if let activity = session.activity {
            let head = activity.distance > 0
                ? "\(formatDistance(activity.distance)) \(currentDistanceUnit.label) · "
                : ""
            return "\(head)\(formatElapsed(activity.duration)) · \(syncText)"
        }
        return "\(setCount) \(setCount == 1 ? "set" : "sets") · \(session.split ?? "Workout") · \(syncText)"
    }

    private func cardioDetail(_ activity: CardioActivity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if activity.distance > 0 {
                    cardioMetric(formatDistance(activity.distance), currentDistanceUnit.label)
                    Spacer()
                }
                cardioMetric(formatElapsed(activity.duration), "time")
                Spacer()
                cardioMetric(formatPace(seconds: activity.duration, metres: activity.distance), "/\(currentDistanceUnit.label)")
            }
            cardioFacts(activity)
            // A two-point "route" is a straight line through nothing — not worth
            // the map tiles.
            if activity.route.count > 2 {
                RouteMap(route: activity.route)
            }
        }
        .padding(14)
        .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .top)
    }

    /// Everything beyond distance/time/pace: calories, ascent, terrain and the
    /// speed figure treadmill runners think in. Collapses away entirely for
    /// sessions saved before these fields existed.
    @ViewBuilder
    private func cardioFacts(_ activity: CardioActivity) -> some View {
        let hasSpeed = activity.distance > 20
        if activity.calories != nil || activity.elevationGain != nil || activity.terrain != nil || hasSpeed {
            VStack(alignment: .leading, spacing: 8) {
                if let calories = activity.calories {
                    Label("~\(calories) kcal burned", systemImage: "flame.fill")
                        .foregroundStyle(Theme.accent)
                }
                HStack(spacing: 14) {
                    if let elevation = activity.elevationGain, elevation > 0 {
                        Label("\(elevation) m", systemImage: "arrow.up.right")
                    }
                    if let terrain = activity.terrain {
                        Label(terrain.label, systemImage: terrain.icon)
                    }
                    if hasSpeed {
                        Label("\(formatSpeed(seconds: activity.duration, metres: activity.distance)) \(speedUnitLabel)", systemImage: "speedometer")
                    }
                }
                .foregroundStyle(Theme.muted2)
            }
            .font(.system(size: 12, weight: .medium))
        }
    }

    private func cardioMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .fontWidth(.condensed)
            Text(label)
                .font(.system(size: 10))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted2)
        }
    }

    private var syncText: String {
        switch session.syncState {
        case .synced: "synced"
        case .failed: "local"
        case .pending: "pending"
        case .localOnly: "local"
        }
    }

    private func setLabel(_ set: LoggedSet, in exercise: LoggedExercise) -> String {
        // A timed set's `reps` are seconds, not repetitions — showing "BW x 1800"
        // for a 30-minute ride reads as nonsense.
        let tag = set.type.map { "\($0.label) · " } ?? ""
        if exercise.timed {
            return tag + formatLoggedDuration(Int(set.reps), minutes: exercise.usesMinutes)
        }
        if let weight = set.weight, weight > 0 {
            return "\(tag)\(formatWeight(weight)) x \(clean(set.reps))"
        }
        return "\(tag)BW x \(clean(set.reps))"
    }
}

/// Edit a saved session: weight/reps per set, add/remove sets, note. Edits in
/// the same String-field model the live log uses (weights in the display
/// unit); saving routes through `AppState.updateSession`, which re-validates,
/// converts back to kg, recomputes PRs and re-enters the pending-sync queue.
struct EditSessionSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    private let sessionID: WorkoutSession.ID
    private let title: String
    @State private var exercises: [ActiveExercise]
    @State private var note: String
    @State private var showAddExercise = false
    /// View-only, unlike the live log's copy — a saved session has no draft.
    @State private var customWeighted = false
    @FocusState private var noteFocused: Bool

    init(session: WorkoutSession) {
        sessionID = session.id
        title = session.createdAt.displayDay
        _exercises = State(initialValue: session.exercises.map { exercise in
            ActiveExercise(
                name: exercise.name,
                bodyweight: exercise.bodyweight,
                timed: exercise.timed,
                minutes: exercise.minutes,
                sets: exercise.sets.map { set in
                    WorkoutSet(
                        weight: set.weight.map { formatWeightValue($0) } ?? "",
                        // Stored seconds back into the field's own unit, mirroring
                        // the kg → display-unit conversion on the line above.
                        reps: exercise.timed
                            ? String(displayDuration(Int(set.reps), minutes: exercise.usesMinutes))
                            : clean(set.reps),
                        done: true,
                        type: set.type
                    )
                }
            )
        })
        _note = State(initialValue: session.note ?? "")
    }

    var body: some View {
        ZStack {
            NativeBackground()
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        TitleBlock(title: "Edit Session", subtitle: title)
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
                        .accessibilityLabel("Close editor")
                    }

                    ForEach($exercises) { $exercise in
                        exerciseCard($exercise)
                    }

                    addExerciseBlock

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Session Note")
                            .cardLabel()
                        TextEditor(text: $note)
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
                            await app.updateSession(id: sessionID, exercises: exercises, note: note)
                            dismiss()
                        }
                    } label: {
                        Label("Save Changes", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("save-session-edits-button")
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .keepsNoteVisible(proxy, focused: noteFocused, text: note)
            }
        }
        .foregroundStyle(Theme.text)
    }

    /// Add a forgotten exercise to an already-saved session. Mirrors the live
    /// log's add flow, but new sets start `done` like the rest of a saved
    /// session — `updateSession` still drops any left without valid reps.
    @ViewBuilder private var addExerciseBlock: some View {
        if showAddExercise {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Add Exercise").cardLabel()
                    Spacer()
                    Button {
                        NativeFeedback.selection()
                        withAnimation(AppMotion.quick) { showAddExercise = false }
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

                ExerciseCatalogPicker(library: app.library) { template in
                    NativeFeedback.light()
                    withAnimation(AppMotion.quick) {
                        append(
                            name: template.name,
                            bodyweight: template.bodyweight,
                            timed: template.timed,
                            minutes: template.minutes
                        )
                    }
                }

                CustomExerciseField(weighted: $customWeighted) { name in
                    append(name: name, bodyweight: !customWeighted, timed: false, custom: true)
                }
            }
            .cardStyle()
            .transition(.opacity)
        } else {
            Button {
                NativeFeedback.selection()
                withAnimation(AppMotion.quick) { showAddExercise = true }
            } label: {
                Label("Add Exercise", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(Theme.muted2)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5])))
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityIdentifier("edit-show-add-exercise-button")
        }
    }

    /// New sets start `done` like the rest of a saved session; `updateSession`
    /// still drops any left without valid reps.
    private func append(name: String, bodyweight: Bool, timed: Bool, minutes: Bool = false, custom: Bool = false) {
        exercises.append(ActiveExercise(
            name: name,
            bodyweight: bodyweight,
            timed: timed,
            minutes: minutes,
            custom: custom,
            sets: [WorkoutSet(done: true)]
        ))
        showAddExercise = false
    }

    private func exerciseCard(_ exercise: Binding<ActiveExercise>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(exercise.wrappedValue.name)
                    .font(.system(size: 15, weight: .semibold))
                if exercise.wrappedValue.bodyweight { SmallBadge("Bodyweight") }
                if exercise.wrappedValue.timed { SmallBadge("Timed") }
                Spacer()
            }
            ForEach(Array(exercise.wrappedValue.sets.enumerated()), id: \.element.id) { index, set in
                // Mirrors the live log's row: no set-number column, so the
                // set-type button has the width it needs.
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .bottom, spacing: 8) {
                        if !exercise.wrappedValue.timed {
                            SmallInput(label: index == 0 ? currentWeightUnit.fieldLabel : "", value: set.weight, keyboard: .decimalPad, identifier: "edit-weight-input") { value in
                                exercise.wrappedValue.sets[index].weight = value.filter { $0.isNumber || $0 == "." }
                            }
                        }
                        SmallInput(label: index == 0 ? (exercise.wrappedValue.timed ? durationFieldLabel(minutes: exercise.wrappedValue.usesMinutes) : "REPS") : "", value: set.reps, keyboard: exercise.wrappedValue.timed ? .numberPad : .decimalPad, identifier: "edit-reps-input") { value in
                            exercise.wrappedValue.sets[index].reps = exercise.wrappedValue.timed
                                ? value.filter(\.isNumber)
                                : snapReps(value)
                        }
                        SetTypeMenu(type: exercise.sets[index].type)
                        Button {
                            NativeFeedback.selection()
                            withAnimation(AppMotion.quick) {
                                exercise.wrappedValue.sets.remove(at: index)
                                // Removing the last set removes the exercise.
                                if exercise.wrappedValue.sets.isEmpty {
                                    exercises.removeAll { $0.id == exercise.wrappedValue.id }
                                }
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 30, height: 34)
                                .foregroundStyle(Theme.muted2)
                        }
                        .buttonStyle(TactileButtonStyle())
                        .accessibilityLabel("Remove set")
                    }
                    if let label = set.type?.label {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent.opacity(0.85))
                    }
                }
            }
            Button {
                NativeFeedback.light()
                withAnimation(AppMotion.quick) {
                    // New sets start done — everything in a saved session is logged.
                    exercise.wrappedValue.sets.append(WorkoutSet(done: true))
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
        .cardStyle()
    }
}
