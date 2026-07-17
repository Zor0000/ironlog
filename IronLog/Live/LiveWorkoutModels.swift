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

/// One exercise in the live (lock-screen) workout.
struct LiveExercise: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var bodyweight: Bool
    var timed: Bool
    var sets: [LiveSet]

    init(id: UUID = UUID(), name: String, bodyweight: Bool = false, timed: Bool = false, sets: [LiveSet] = []) {
        self.id = id
        self.name = name
        self.bodyweight = bodyweight
        self.timed = timed
        self.sets = sets
    }
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
        guard !exercise.bodyweight, !exercise.timed else { return state }
        let current = parseDouble(state.exercises[ei.exercise].sets[ei.set].weight)
        let next = max(0, current + Double(direction) * state.weightStep)
        state.exercises[ei.exercise].sets[ei.set].weight = formatWeight(next)
        return state
    }

    /// Nudge the current set's reps (or seconds) by one.
    static func adjustReps(_ state: LiveWorkoutState, by direction: Int) -> LiveWorkoutState {
        var state = state
        guard let ei = currentEditableIndices(state) else { return state }
        let current = Int(state.exercises[ei.exercise].sets[ei.set].reps) ?? 0
        let next = max(0, current + direction)
        state.exercises[ei.exercise].sets[ei.set].reps = String(next)
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

    private static func currentEditableIndices(_ state: LiveWorkoutState) -> (exercise: Int, set: Int)? {
        guard state.exercises.indices.contains(state.currentExerciseIndex),
              let setIndex = state.currentSetIndex else { return nil }
        return (state.currentExerciseIndex, setIndex)
    }

    static func isValid(_ set: LiveSet, in exercise: LiveExercise) -> Bool {
        guard let reps = Int(set.reps), reps > 0 else { return false }
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

    /// Renders a weight without a trailing ".0" so the stepper reads "60" not
    /// "60.0", but keeps a half-plate as "62.5".
    static func formatWeight(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
