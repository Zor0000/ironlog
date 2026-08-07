import Foundation

/// A single set as represented on the lock screen. Mirrors `WorkoutSet` but is
/// a self-contained value so the widget extension does not need to compile the
/// rest of the app's models.
struct LiveSet: Codable, Hashable, Identifiable {
    var id: UUID
    var weight: String
    var reps: String
    var done: Bool

    init(id: UUID = UUID(), weight: String = "", reps: String = "", done: Bool = false) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.done = done
    }
}

/// The unit label for a timed exercise's duration field. Lives in this shared
/// file (rather than beside the other duration helpers in `Models.swift`)
/// because the widget extension does not compile `Models.swift`, and the app and
/// lock screen must never disagree about what the field means.
func durationFieldLabel(minutes: Bool) -> String {
    minutes ? "MINS" : "SECS"
}

/// One exercise in the live (lock-screen) workout.
struct LiveExercise: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var bodyweight: Bool
    var timed: Bool
    /// Optional so an engine snapshot written before cardio existed still
    /// decodes — synthesized `Decodable` has no default-value fallback.
    var minutes: Bool?
    var sets: [LiveSet]

    init(id: UUID = UUID(), name: String, bodyweight: Bool = false, timed: Bool = false, minutes: Bool? = nil, sets: [LiveSet] = []) {
        self.id = id
        self.name = name
        self.bodyweight = bodyweight
        self.timed = timed
        self.minutes = minutes
        self.sets = sets
    }

    /// See `ActiveExercise.usesMinutes` — the two surfaces must agree.
    var usesMinutes: Bool { minutes == true }
}

/// The full state shared between the app and the lock-screen Live Activity.
///
/// It is intentionally a flat, `Codable` snapshot so it can round-trip through
/// `UserDefaults` and be handed to ActivityKit without dragging in `AppState`.
struct LiveWorkoutState: Codable, Hashable {
    /// Headline shown on the lock screen, e.g. "Chest day" or "Push · PPL".
    var title: String
    var exercises: [LiveExercise]
    var currentExerciseIndex: Int
    /// Wall-clock time the current rest period ends. `nil` when no rest running.
    var restEndsAt: Date?
    /// The rest preset (seconds) so a freshly logged set knows how long to rest.
    var restSeconds: Int
    /// Weight increment used by the lock-screen stepper, in the user's unit.
    var weightStep: Double

    init(
        title: String,
        exercises: [LiveExercise],
        currentExerciseIndex: Int = 0,
        restEndsAt: Date? = nil,
        restSeconds: Int = 90,
        weightStep: Double = 2.5
    ) {
        self.title = title
        self.exercises = exercises
        self.currentExerciseIndex = currentExerciseIndex.clamped(to: 0...(max(exercises.count - 1, 0)))
        self.restEndsAt = restEndsAt
        self.restSeconds = restSeconds
        self.weightStep = weightStep
    }
}

// MARK: - Derived accessors

extension LiveWorkoutState {
    var currentExercise: LiveExercise? {
        guard exercises.indices.contains(currentExerciseIndex) else { return nil }
        return exercises[currentExerciseIndex]
    }

    /// Index of the set the user is currently working on within the current
    /// exercise: the first not-yet-done set, or the last set once all are done.
    var currentSetIndex: Int? {
        guard let exercise = currentExercise, !exercise.sets.isEmpty else { return nil }
        if let firstOpen = exercise.sets.firstIndex(where: { !$0.done }) {
            return firstOpen
        }
        return exercise.sets.count - 1
    }

    var currentSet: LiveSet? {
        guard let exercise = currentExercise, let index = currentSetIndex else { return nil }
        return exercise.sets[index]
    }

    /// The set that may actually be *changed*: the first not-yet-done one. Nil
    /// once every set in the exercise is finished.
    ///
    /// Deliberately not the same as `currentSetIndex`, which falls back to the
    /// last set so a finished exercise still reads "Set 3/3" instead of snapping
    /// back to "Set 1/3". Using that fallback as an edit target meant navigating
    /// back to a finished exercise left the steppers rewriting already-logged
    /// work, and `Log set` re-logging its last set and restarting rest from full.
    var editableSetIndex: Int? {
        currentExercise?.sets.firstIndex(where: { !$0.done })
    }

    /// True when the exercise on screen has no set left to log.
    var isCurrentExerciseComplete: Bool {
        guard let exercise = currentExercise, !exercise.sets.isEmpty else { return false }
        return exercise.sets.allSatisfy(\.done)
    }

    var isComplete: Bool {
        !exercises.isEmpty && exercises.allSatisfy { exercise in
            exercise.sets.allSatisfy(\.done)
        }
    }

    /// 1-based number of the current set, for display.
    var currentSetNumber: Int { (currentSetIndex ?? 0) + 1 }

    var currentExerciseDoneCount: Int {
        currentExercise?.sets.filter(\.done).count ?? 0
    }
}

// MARK: - Reducer

/// Pure, side-effect-free transformations of `LiveWorkoutState`. Both the
/// in-app glue and the lock-screen intents funnel through here so the two
/// surfaces can never drift in behaviour.
enum LiveWorkoutReducer {
    static let defaultReps = "8"

    /// Nudge the current set's weight by `weightStep` (only for weighted moves).
    static func adjustWeight(_ state: LiveWorkoutState, by direction: Int) -> LiveWorkoutState {
        var state = state
        guard let ei = currentEditableIndices(state) else { return state }
        let exercise = state.exercises[ei.exercise]
        guard !exercise.timed else { return state }
        let current = parseDouble(state.exercises[ei.exercise].sets[ei.set].weight)
        let next = max(0, current + Double(direction) * state.weightStep)
        state.exercises[ei.exercise].sets[ei.set].weight = formatNumber(next)
        return state
    }

    /// Nudge the current set's reps (or seconds) by one.
    ///
    /// Whole steps only — a half typed in the app is carried along (7.5 → 8.5)
    /// but the lock screen has no way to enter one.
    /// ponytail: add a long-press half-step if anyone asks for it on the widget.
    static func adjustReps(_ state: LiveWorkoutState, by direction: Int) -> LiveWorkoutState {
        var state = state
        guard let ei = currentEditableIndices(state) else { return state }
        let current = parseDouble(state.exercises[ei.exercise].sets[ei.set].reps)
        let next = max(0, current + Double(direction))
        state.exercises[ei.exercise].sets[ei.set].reps = formatNumber(next)
        return state
    }

    /// Mark the current set done and start a fresh rest period. Carries the
    /// logged weight/reps into the next empty set of the same exercise so the
    /// common "same weight again" flow is a single tap.
    static func logCurrentSet(_ state: LiveWorkoutState, at now: Date = .now) -> LiveWorkoutState {
        var state = state
        guard let ei = currentEditableIndices(state) else { return state }
        let set = state.exercises[ei.exercise].sets[ei.set]
        guard isValid(set, in: state.exercises[ei.exercise]) else { return state }

        state.exercises[ei.exercise].sets[ei.set].done = true
        state.restEndsAt = now.addingTimeInterval(TimeInterval(state.restSeconds))

        // Pre-fill the next open set in this exercise from the one just logged.
        let sets = state.exercises[ei.exercise].sets
        if let nextOpen = sets.indices.first(where: { $0 > ei.set && !sets[$0].done }) {
            if state.exercises[ei.exercise].sets[nextOpen].weight.isEmpty {
                state.exercises[ei.exercise].sets[nextOpen].weight = set.weight
            }
            if state.exercises[ei.exercise].sets[nextOpen].reps.isEmpty {
                state.exercises[ei.exercise].sets[nextOpen].reps = set.reps
            }
        }
        return state
    }

    /// Undo the most recently completed set in the current exercise.
    static func unlogCurrentSet(_ state: LiveWorkoutState) -> LiveWorkoutState {
        var state = state
        guard let exercise = state.currentExercise,
              let lastDone = exercise.sets.lastIndex(where: \.done) else { return state }
        state.exercises[state.currentExerciseIndex].sets[lastDone].done = false
        state.restEndsAt = nil
        return state
    }

    /// Which exercise the card should show, given the last synced index.
    ///
    /// Pure and separate from `buildLiveState` so the rule is testable: it is
    /// the choice that decides whether the activity follows the workout or gets
    /// stuck on a finished exercise.
    static func exerciseIndex(for exercises: [LiveExercise], previous: Int?) -> Int {
        func hasOpenSet(_ index: Int) -> Bool {
            exercises[index].sets.contains { !$0.done }
        }
        if let previous, exercises.indices.contains(previous), hasOpenSet(previous) {
            return previous
        }
        return exercises.indices.first(where: hasOpenSet) ?? max(exercises.count - 1, 0)
    }

    static func nextExercise(_ state: LiveWorkoutState) -> LiveWorkoutState {
        move(state, by: 1)
    }

    static func previousExercise(_ state: LiveWorkoutState) -> LiveWorkoutState {
        move(state, by: -1)
    }

    private static func move(_ state: LiveWorkoutState, by direction: Int) -> LiveWorkoutState {
        var state = state
        let target = (state.currentExerciseIndex + direction).clamped(to: 0...(max(state.exercises.count - 1, 0)))
        state.currentExerciseIndex = target
        state.restEndsAt = nil
        return state
    }

    // MARK: helpers

    /// The one gate every mutating transform goes through, so a finished
    /// exercise is read-only on all of them at once rather than each having to
    /// remember the check.
    private static func currentEditableIndices(_ state: LiveWorkoutState) -> (exercise: Int, set: Int)? {
        guard state.exercises.indices.contains(state.currentExerciseIndex),
              let setIndex = state.editableSetIndex else { return nil }
        return (state.currentExerciseIndex, setIndex)
    }

    static func isValid(_ set: LiveSet, in exercise: LiveExercise) -> Bool {
        guard let reps = parseDoubleOptional(set.reps), reps > 0 else { return false }
        if exercise.bodyweight || exercise.timed { return true }
        guard let weight = parseDoubleOptional(set.weight), weight >= 0 else { return false }
        return true
    }
}

// MARK: - Number formatting

extension LiveWorkoutReducer {
    static func parseDouble(_ value: String) -> Double {
        parseDoubleOptional(value) ?? 0
    }

    static func parseDoubleOptional(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }

    /// Renders a stepper value without a trailing ".0" — "60" not "60.0" — while
    /// keeping a half-plate as "62.5" and a half-rep as "7.5".
    static func formatNumber(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
