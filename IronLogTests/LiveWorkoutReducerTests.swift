import XCTest
@testable import IronLog

final class LiveWorkoutReducerTests: XCTestCase {
    private func weightedWorkout() -> LiveWorkoutState {
        LiveWorkoutState(
            title: "Chest day",
            exercises: [
                LiveExercise(
                    name: "Bench Press",
                    sets: [
                        LiveSet(weight: "60", reps: "8"),
                        LiveSet(weight: "", reps: ""),
                        LiveSet(weight: "", reps: "")
                    ]
                ),
                LiveExercise(
                    name: "Incline DB Press",
                    sets: [LiveSet(weight: "24", reps: "10")]
                )
            ],
            restSeconds: 90,
            weightStep: 2.5
        )
    }

    func testCurrentSetIsFirstOpenSet() {
        let state = weightedWorkout()
        XCTAssertEqual(state.currentSetNumber, 1)
        XCTAssertEqual(state.currentSet?.weight, "60")
    }

    func testAdjustWeightStepsByConfiguredIncrement() {
        var state = weightedWorkout()
        state = LiveWorkoutReducer.adjustWeight(state, by: 1)
        XCTAssertEqual(state.currentSet?.weight, "62.5")
        state = LiveWorkoutReducer.adjustWeight(state, by: -1)
        XCTAssertEqual(state.currentSet?.weight, "60")
    }

    func testAdjustWeightNeverGoesNegative() {
        var state = weightedWorkout()
        state.exercises[0].sets[0].weight = "1"
        state = LiveWorkoutReducer.adjustWeight(state, by: -1)
        XCTAssertEqual(state.currentSet?.weight, "0")
    }

    func testAdjustRepsClampsAtZero() {
        var state = weightedWorkout()
        state.exercises[0].sets[0].reps = "1"
        state = LiveWorkoutReducer.adjustReps(state, by: -1)
        XCTAssertEqual(state.currentSet?.reps, "0")
        state = LiveWorkoutReducer.adjustReps(state, by: -1)
        XCTAssertEqual(state.currentSet?.reps, "0")
    }

    func testLogSetMarksDoneStartsRestAndAdvancesToNextSet() {
        let now = Date(timeIntervalSince1970: 1_000)
        var state = weightedWorkout()
        state = LiveWorkoutReducer.logCurrentSet(state, at: now)

        XCTAssertTrue(state.exercises[0].sets[0].done)
        XCTAssertEqual(state.restEndsAt, now.addingTimeInterval(90))
        // Now working on set 2, pre-filled from the set just logged.
        XCTAssertEqual(state.currentSetNumber, 2)
        XCTAssertEqual(state.currentSet?.weight, "60")
        XCTAssertEqual(state.currentSet?.reps, "8")
    }

    func testLogSetIsRejectedWithoutReps() {
        var state = weightedWorkout()
        state.exercises[0].sets[0].reps = ""
        state = LiveWorkoutReducer.logCurrentSet(state)
        XCTAssertFalse(state.exercises[0].sets[0].done)
        XCTAssertNil(state.restEndsAt)
    }

    func testLogSetRequiresWeightForWeightedExercise() {
        var state = weightedWorkout()
        state.exercises[0].sets[0].weight = ""
        state = LiveWorkoutReducer.logCurrentSet(state)
        XCTAssertFalse(state.exercises[0].sets[0].done)
    }

    func testBodyweightExerciseLogsWithoutWeight() {
        var state = LiveWorkoutState(
            title: "Pull day",
            exercises: [LiveExercise(name: "Pull Ups", bodyweight: true, sets: [LiveSet(reps: "10")])]
        )
        state = LiveWorkoutReducer.logCurrentSet(state)
        XCTAssertTrue(state.exercises[0].sets[0].done)
    }

    func testNextAndPreviousExerciseClampToBounds() {
        var state = weightedWorkout()
        XCTAssertEqual(state.currentExerciseIndex, 0)
        state = LiveWorkoutReducer.previousExercise(state)
        XCTAssertEqual(state.currentExerciseIndex, 0) // already first

        state = LiveWorkoutReducer.nextExercise(state)
        XCTAssertEqual(state.currentExerciseIndex, 1)
        XCTAssertEqual(state.currentExercise?.name, "Incline DB Press")

        state = LiveWorkoutReducer.nextExercise(state)
        XCTAssertEqual(state.currentExerciseIndex, 1) // already last
    }

    func testNextExerciseClearsRunningRest() {
        var state = weightedWorkout()
        state = LiveWorkoutReducer.logCurrentSet(state)
        XCTAssertNotNil(state.restEndsAt)
        state = LiveWorkoutReducer.nextExercise(state)
        XCTAssertNil(state.restEndsAt)
    }

    func testCompletingAllSetsMarksWorkoutComplete() {
        var state = LiveWorkoutState(
            title: "Quick",
            exercises: [LiveExercise(name: "Curl", sets: [LiveSet(weight: "20", reps: "10")])]
        )
        XCTAssertFalse(state.isComplete)
        state = LiveWorkoutReducer.logCurrentSet(state)
        XCTAssertTrue(state.isComplete)
    }

    func testUndoReopensLastCompletedSet() {
        var state = weightedWorkout()
        state = LiveWorkoutReducer.logCurrentSet(state)
        XCTAssertTrue(state.exercises[0].sets[0].done)
        state = LiveWorkoutReducer.unlogCurrentSet(state)
        XCTAssertFalse(state.exercises[0].sets[0].done)
    }

    func testHalfPlateWeightFormatsWithoutTrailingZeros() {
        XCTAssertEqual(LiveWorkoutReducer.formatWeight(62.5), "62.5")
        XCTAssertEqual(LiveWorkoutReducer.formatWeight(60.0), "60")
        XCTAssertEqual(LiveWorkoutReducer.formatWeight(100), "100")
    }

    // MARK: - Navigating back to a finished exercise

    /// Exercise 0 fully logged, exercise 1 still open, sitting on exercise 0 —
    /// exactly what "go back one exercise" lands you in.
    private func finishedFirstExercise() -> LiveWorkoutState {
        var state = weightedWorkout()
        for index in state.exercises[0].sets.indices {
            state.exercises[0].sets[index].weight = "60"
            state.exercises[0].sets[index].reps = "8"
            state.exercises[0].sets[index].done = true
        }
        state.currentExerciseIndex = 0
        return state
    }

    /// The reported bug: on a finished exercise, `Log set` re-logged its last
    /// completed set and restarted the rest period from full.
    func testLoggingOnAFinishedExerciseDoesNotRestartRest() {
        var state = finishedFirstExercise()
        state.restEndsAt = nil

        state = LiveWorkoutReducer.logCurrentSet(state)

        XCTAssertNil(state.restEndsAt, "A finished exercise has nothing to log, so rest must not restart")
    }

    /// The steppers stayed bound to the last completed set, so ± silently
    /// rewrote work the user had already logged.
    func testSteppersCannotRewriteAFinishedExercise() {
        var state = finishedFirstExercise()

        state = LiveWorkoutReducer.adjustWeight(state, by: 1)
        state = LiveWorkoutReducer.adjustReps(state, by: 1)

        XCTAssertEqual(state.exercises[0].sets[2].weight, "60")
        XCTAssertEqual(state.exercises[0].sets[2].reps, "8")
    }

    /// Undo is the one action that must still work there — it is how you reopen
    /// a set you finished by mistake.
    func testUndoStillWorksOnAFinishedExercise() {
        var state = finishedFirstExercise()
        state = LiveWorkoutReducer.unlogCurrentSet(state)
        XCTAssertFalse(state.exercises[0].sets[2].done)

        // And once reopened, the steppers own it again.
        state = LiveWorkoutReducer.adjustReps(state, by: 1)
        XCTAssertEqual(state.exercises[0].sets[2].reps, "9")
    }

    /// Display still points at the last set, so the card reads "Set 3/3" rather
    /// than snapping back to "Set 1/3" on a finished exercise.
    func testFinishedExerciseStillDisplaysItsLastSet() {
        let state = finishedFirstExercise()
        XCTAssertEqual(state.currentSetNumber, 3)
        XCTAssertNil(state.editableSetIndex)
        XCTAssertTrue(state.isCurrentExerciseComplete)
    }

    // MARK: - Which exercise the card follows

    /// `previous` is the last synced index, not just one a Next/Prev tap made,
    /// so honouring it unconditionally pinned the card to exercise 1 for the
    /// whole workout.
    func testCardAdvancesOnceAnExerciseIsFinished() {
        let exercises = finishedFirstExercise().exercises
        XCTAssertEqual(LiveWorkoutReducer.exerciseIndex(for: exercises, previous: 0), 1)
    }

    /// Navigating to an exercise that still has work is respected.
    func testCardStaysWhereTheUserNavigated() {
        var state = weightedWorkout()
        state.exercises[0].sets[0].done = true
        XCTAssertEqual(LiveWorkoutReducer.exerciseIndex(for: state.exercises, previous: 1), 1)
        XCTAssertEqual(LiveWorkoutReducer.exerciseIndex(for: state.exercises, previous: nil), 0)
    }

    /// An index left over from a deleted exercise must not crash or stick.
    func testOutOfBoundsPreviousIndexFallsBack() {
        let exercises = weightedWorkout().exercises
        XCTAssertEqual(LiveWorkoutReducer.exerciseIndex(for: exercises, previous: 99), 0)
    }

    /// With everything logged there is no open set to move to; hold on the last.
    func testFullyLoggedWorkoutHoldsOnTheLastExercise() {
        var state = weightedWorkout()
        for ei in state.exercises.indices {
            for si in state.exercises[ei].sets.indices {
                state.exercises[ei].sets[si].done = true
            }
        }
        XCTAssertEqual(LiveWorkoutReducer.exerciseIndex(for: state.exercises, previous: 0), 1)
    }
}

@MainActor
final class LiveWorkoutEngineTests: XCTestCase {
    override func setUp() async throws {
        LiveWorkoutEngine.shared.end()
        await LiveWorkoutEngine.shared.waitForPendingOperations()
    }

    override func tearDown() async throws {
        LiveWorkoutEngine.shared.end()
        await LiveWorkoutEngine.shared.waitForPendingOperations()
    }

    private func sample() -> LiveWorkoutState {
        LiveWorkoutState(
            title: "Arms",
            exercises: [
                LiveExercise(name: "Curl", sets: [LiveSet(weight: "20", reps: "10"), LiveSet()])
            ]
        )
    }

    func testSyncPersistsStateAndMutateAdvancesSet() async {
        let engine = LiveWorkoutEngine.shared
        engine.sync(sample())
        await engine.waitForPendingOperations()
        XCTAssertEqual(engine.currentState?.currentSet?.reps, "10")

        await engine.mutate { LiveWorkoutReducer.logCurrentSet($0) }
        XCTAssertEqual(engine.currentState?.exercises.first?.sets.first?.done, true)
        XCTAssertEqual(engine.currentState?.currentSetNumber, 2)
        XCTAssertEqual(engine.currentState?.currentSet?.weight, "20") // carried over
    }

    func testEndClearsPersistedState() async {
        let engine = LiveWorkoutEngine.shared
        engine.sync(sample())
        await engine.waitForPendingOperations()
        XCTAssertNotNil(engine.currentState)

        engine.end()
        await engine.waitForPendingOperations()
        XCTAssertNil(engine.currentState)
    }

    /// Reproduces the finish race: a `sync` built from the active workout is
    /// immediately followed by `end()`. FIFO serialization must leave no state
    /// behind (i.e. no orphan activity resurrected after the finish).
    func testSyncFollowedByEndLeavesNoState() async {
        let engine = LiveWorkoutEngine.shared
        engine.sync(sample())
        engine.end()
        await engine.waitForPendingOperations()
        XCTAssertNil(engine.currentState)
    }

    func testMutateWithoutStateIsNoOp() async {
        let engine = LiveWorkoutEngine.shared
        await engine.mutate { LiveWorkoutReducer.nextExercise($0) }
        XCTAssertNil(engine.currentState)
    }
}
