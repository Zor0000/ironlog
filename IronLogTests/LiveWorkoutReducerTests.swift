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
}
