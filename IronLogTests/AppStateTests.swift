import XCTest
@testable import IronLog

@MainActor
final class AppStateTests: XCTestCase {
    func testBlankBodyweightSetCannotBeCompleted() {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(name: "Push Ups")

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.toggleDone(exerciseID: exerciseID, setID: setID)

        XCTAssertFalse(app.todayExercises[0].sets[0].done)
        XCTAssertEqual(app.validCompletedSetCount, 0)
        XCTAssertEqual(app.toast, "Enter reps before marking the set done")
    }

    func testWeightedSetRequiresWeightAndSanitizesDecimalInput() {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Bench Press")

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, reps: "8")
        app.toggleDone(exerciseID: exerciseID, setID: setID)

        XCTAssertFalse(app.todayExercises[0].sets[0].done)
        XCTAssertEqual(app.toast, "Enter weight and reps before marking the set done")

        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "100..5kg")
        app.toggleDone(exerciseID: exerciseID, setID: setID)

        XCTAssertEqual(app.todayExercises[0].sets[0].weight, "100.5")
        XCTAssertTrue(app.todayExercises[0].sets[0].done)
        XCTAssertEqual(app.validCompletedSetCount, 1)
    }

    func testDiscardWorkoutClearsActiveStateAndTimer() {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(name: "Pull Ups")
        app.updateWorkoutNote("Felt strong")
        app.startTimer()

        app.discardWorkout()

        XCTAssertFalse(app.hasActiveWorkout)
        XCTAssertTrue(app.todayExercises.isEmpty)
        XCTAssertFalse(app.showAddExerciseForm)
        XCTAssertEqual(app.workoutNote, "")
        XCTAssertFalse(app.timerRunning)
        XCTAssertEqual(app.timerSecs, app.timerMax)
    }

    func testFinishWorkoutSavesOnlyValidCompletedSets() async {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(name: "Dips")

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, reps: "12")
        app.toggleDone(exerciseID: exerciseID, setID: setID)

        await app.finishWorkout(note: "Controlled tempo")

        XCTAssertEqual(app.sessions.count, 1)
        XCTAssertEqual(app.sessions[0].note, "Controlled tempo")
        XCTAssertEqual(app.sessions[0].exercises.count, 1)
        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].reps, 12)
        XCTAssertFalse(app.hasActiveWorkout)
        XCTAssertEqual(app.selectedTab, .history)
    }

    func testWorkoutDraftRoundTripsNavigationAndNoteContext() throws {
        let draft = WorkoutDraft(
            exercises: [
                ActiveExercise(
                    name: "Squat",
                    bodyweight: false,
                    timed: false,
                    sets: [WorkoutSet(weight: "120", reps: "5", done: true)]
                )
            ],
            muscle: "legs",
            split: "PPL",
            day: "Legs",
            step: .workout,
            showAddExerciseForm: true,
            addExerciseWeighted: true,
            note: "Paused reps"
        )

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(WorkoutDraft.self, from: data)

        XCTAssertEqual(decoded.exercises.count, 1)
        XCTAssertEqual(decoded.muscle, "legs")
        XCTAssertEqual(decoded.split, "PPL")
        XCTAssertEqual(decoded.day, "Legs")
        XCTAssertEqual(decoded.step, .workout)
        XCTAssertEqual(decoded.showAddExerciseForm, true)
        XCTAssertEqual(decoded.addExerciseWeighted, true)
        XCTAssertEqual(decoded.note, "Paused reps")
    }
}
