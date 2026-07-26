import Foundation

/// Bridges the in-app workout (`AppState`) and the lock-screen Live Activity.
///
/// The app is the source of truth while it is in the foreground; the engine's
/// persisted snapshot becomes authoritative for any edits the user makes from
/// the Lock Screen while the app is backgrounded. `reconcileFromLiveActivity`
/// folds those edits back in when the app returns to the foreground.
extension AppState {
    /// Weight stepper increment used on the lock screen, in the user's unit.
    private var liveWeightStep: Double { 2.5 }

    /// Snapshot the active workout for the Live Activity, seeding the current
    /// set's weight from the personal record so the stepper starts somewhere
    /// useful instead of zero.
    func buildLiveState() -> LiveWorkoutState {
        let previousIndex = LiveWorkoutEngine.shared.currentState?.currentExerciseIndex

        let exercises = todayExercises.map { exercise in
            LiveExercise(
                id: exercise.id,
                name: exercise.name,
                bodyweight: exercise.bodyweight,
                timed: exercise.timed,
                sets: exercise.sets.map { LiveSet(id: $0.id, weight: $0.weight, reps: $0.reps, done: $0.done) }
            )
        }

        // Prefer the first not-yet-finished exercise, but keep whatever the user
        // navigated to from the lock screen if it is still valid.
        let firstIncomplete = exercises.firstIndex { ex in ex.sets.contains { !$0.done } }
        var index = firstIncomplete ?? max(exercises.count - 1, 0)
        if let previousIndex, exercises.indices.contains(previousIndex) {
            index = previousIndex
        }

        let restEndsAt: Date? = timerRunning ? Date().addingTimeInterval(TimeInterval(timerSecs)) : nil

        var state = LiveWorkoutState(
            title: selectedWorkoutMuscleLabel,
            exercises: exercises,
            currentExerciseIndex: index,
            restEndsAt: restEndsAt,
            restSeconds: timerMax,
            weightStep: liveWeightStep
        )
        seedCurrentSet(&state)
        return state
    }

    /// Fill the active set's empty fields with sensible suggestions so the
    /// lock-screen stepper is immediately usable.
    private func seedCurrentSet(_ state: inout LiveWorkoutState) {
        guard state.exercises.indices.contains(state.currentExerciseIndex),
              let setIndex = state.currentSetIndex else { return }
        let exerciseIndex = state.currentExerciseIndex
        let exercise = state.exercises[exerciseIndex]

        if state.exercises[exerciseIndex].sets[setIndex].reps.isEmpty {
            state.exercises[exerciseIndex].sets[setIndex].reps = LiveWorkoutReducer.defaultReps
        }
        // `pr.weight > 0` already excludes never-loaded moves, so bodyweight
        // exercises seed only once they've actually been loaded.
        if !exercise.timed,
           state.exercises[exerciseIndex].sets[setIndex].weight.isEmpty,
           let pr = personalRecords[exercise.name], pr.weight > 0 {
            // PR is stored in kg; the stepper string lives in the display unit.
            state.exercises[exerciseIndex].sets[setIndex].weight = formatWeightValue(pr.weight)
        }
    }

    /// Push the current workout to the Live Activity, or tear it down when the
    /// workout is finished/discarded. Called from `persistAll`.
    func updateLiveActivity(clearedDraft: Bool) {
        if clearedDraft || !hasActiveWorkout {
            LiveWorkoutEngine.shared.end()
        } else {
            LiveWorkoutEngine.shared.sync(buildLiveState(), weightUnit: unitPreference.fieldLabel)
        }
    }

    /// Fold any edits made from the Lock Screen back into the in-app workout.
    /// Safe to call on every foreground transition.
    func reconcileFromLiveActivity() {
        guard hasActiveWorkout, let live = LiveWorkoutEngine.shared.currentState else { return }

        for liveExercise in live.exercises {
            guard let ei = todayExercises.firstIndex(where: { $0.id == liveExercise.id }) else { continue }
            for liveSet in liveExercise.sets {
                guard let si = todayExercises[ei].sets.firstIndex(where: { $0.id == liveSet.id }) else { continue }
                todayExercises[ei].sets[si].weight = liveSet.weight
                todayExercises[ei].sets[si].reps = liveSet.reps
                todayExercises[ei].sets[si].done = liveSet.done
            }
        }

        // Expand whichever exercise the lock screen left active.
        if live.exercises.indices.contains(live.currentExerciseIndex) {
            let activeID = live.exercises[live.currentExerciseIndex].id
            for i in todayExercises.indices {
                todayExercises[i].expanded = todayExercises[i].id == activeID
            }
        }

        // Resume the in-app rest countdown from where the lock screen left it —
        // an absolute end date, so a lock-screen-restarted rest replaces any
        // stale in-app countdown (and its notification) exactly.
        if let endsAt = live.restEndsAt, endsAt > Date() {
            timerMax = live.restSeconds
            resumeTimer(until: endsAt)
        }

        // Persist so lock-screen navigation (Next/Prev) and set edits both survive,
        // and re-sync the activity (coalesced, so a no-op change costs nothing).
        persistDraft()
    }
}
