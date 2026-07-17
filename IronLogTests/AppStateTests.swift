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

    func testClearingValueOnCompletedSetUnmarksItDone() {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Bench Press")

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "60", reps: "8")
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        XCTAssertTrue(app.todayExercises[0].sets[0].done)
        XCTAssertEqual(app.validCompletedSetCount, 1)

        // Clearing the weight on an already-completed set must drop the done flag
        // so the checkmark and the saved session can never disagree.
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "")

        XCTAssertFalse(app.todayExercises[0].sets[0].done)
        XCTAssertEqual(app.validCompletedSetCount, 0)
    }

    func testEditingCompletedSetToAnotherValidValueKeepsItDone() {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Squat")

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "100", reps: "5")
        app.toggleDone(exerciseID: exerciseID, setID: setID)

        // A correction that stays valid must not clear the completed state.
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "105")

        XCTAssertTrue(app.todayExercises[0].sets[0].done)
        XCTAssertEqual(app.todayExercises[0].sets[0].weight, "105")
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

    func testCompletingSetRestartsRestTimerFromPreset() {
        let app = AppState()
        app.setTimerPreset(120)
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Bench Press")

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "60", reps: "8")

        // Simulate a rest timer already partway through from a previous set.
        app.timerSecs = 30
        app.toggleDone(exerciseID: exerciseID, setID: setID)

        XCTAssertTrue(app.timerRunning)
        XCTAssertEqual(app.timerSecs, app.timerMax)
        XCTAssertEqual(app.timerMax, 120)

        app.resetTimer()
    }

    func testExerciseCatalogIsGlobalAndIncludesBasics() {
        let app = AppState()
        let muscleIDs = app.library.catalogMuscles.map(\.id)
        XCTAssertTrue(muscleIDs.contains("legs"))
        XCTAssertTrue(muscleIDs.contains("biceps"))
        XCTAssertTrue(muscleIDs.contains("triceps"))

        let legs = app.library.catalogExercises(muscleID: "legs", query: "")
        XCTAssertTrue(legs.contains { $0.template.name == "Walking Lunges" })
        XCTAssertTrue(legs.contains { $0.template.name == "Goblet Squat" })
        XCTAssertTrue(legs.contains { $0.template.name == "Glute Bridge" })

        // Search spans the whole catalog, independent of the active split/muscle.
        let lunges = app.library.catalogExercises(muscleID: nil, query: "lunge")
        XCTAssertTrue(lunges.contains { $0.template.name == "Walking Lunges" })
        XCTAssertGreaterThanOrEqual(lunges.count, 3)
    }

    func testCatalogBodyweightExerciseAddsAsBodyweight() {
        let app = AppState()
        app.startFreeWorkout()
        let lunge = app.library
            .catalogExercises(muscleID: "legs", query: "walking lunges")
            .first { $0.template.name == "Walking Lunges" }!

        app.addExercise(template: lunge.template)

        XCTAssertEqual(app.todayExercises.last?.name, "Walking Lunges")
        XCTAssertEqual(app.todayExercises.last?.bodyweight, true)
        XCTAssertFalse(app.showAddExerciseForm)
    }

    func testSplitDayStartsAllMusclesInOneWorkout() {
        let app = AppState()
        app.selectSplit("PPL")
        app.selectDay("Push")

        XCTAssertEqual(app.workoutStep, .workout)
        XCTAssertEqual(app.selectedWorkoutMuscleIDs, ["chest", "shoulders", "triceps"])
        XCTAssertTrue(app.activeExerciseTemplates.contains { $0.name == "Barbell Bench Press" })
        XCTAssertTrue(app.activeExerciseTemplates.contains { $0.name == "Seated DB Shoulder Press" })
        XCTAssertTrue(app.activeExerciseTemplates.contains { $0.name == "Overhead Tricep Extension" })

        app.startWorkout()

        XCTAssertTrue(app.todayExercises.contains { $0.name == "Barbell Bench Press" })
        XCTAssertTrue(app.todayExercises.contains { $0.name == "Seated DB Shoulder Press" })
        XCTAssertTrue(app.todayExercises.contains { $0.name == "Overhead Tricep Extension" })
        XCTAssertEqual(app.selectedTab, .log)
    }

    func testTemplateExerciseCanBeAddedToActiveWorkout() {
        let app = AppState()
        app.selectSplit("Upper/Lower")
        app.selectDay("Upper")
        let template = app.activeExerciseTemplates.first { $0.name == "Barbell Bench Press" }!

        app.startFreeWorkout()
        app.selectedSplit = "Upper/Lower"
        app.selectedDay = "Upper"
        app.beginAddingExercise()
        app.addExercise(template: template)

        XCTAssertEqual(app.todayExercises.last?.name, "Barbell Bench Press")
        XCTAssertEqual(app.todayExercises.last?.sets.count, template.sets)
        XCTAssertFalse(app.todayExercises.last?.bodyweight ?? true)
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

    // MARK: - Shared helpers (Phase 0)

    func testFormatWeightRendersKgWithCleanNumber() {
        XCTAssertEqual(formatWeight(60), "60 kg")
        XCTAssertEqual(formatWeight(100.0), "100 kg")
        XCTAssertEqual(formatWeight(62.5), "62.5 kg")
    }

    func testLastPerformanceReturnsMostRecentPriorSessionByExactName() {
        let app = AppState()
        let older = WorkoutSession(
            createdAt: Date(timeIntervalSince1970: 1_000),
            muscle: nil, split: nil, note: nil,
            exercises: [LoggedExercise(name: "Bench Press", bodyweight: false, timed: false,
                                       sets: [LoggedSet(weight: 60, reps: 8)])]
        )
        let newer = WorkoutSession(
            createdAt: Date(timeIntervalSince1970: 2_000),
            muscle: nil, split: nil, note: nil,
            exercises: [LoggedExercise(name: "Bench Press", bodyweight: false, timed: false,
                                       sets: [LoggedSet(weight: 65, reps: 6), LoggedSet(weight: 65, reps: 5)])]
        )
        // AppState keeps `sessions` newest-first.
        app.sessions = [newer, older]

        let reference = app.lastPerformance(exerciseName: "Bench Press")
        XCTAssertEqual(reference?.sets.count, 2)
        XCTAssertEqual(reference?.sets.first?.weight, 65)
        XCTAssertNil(app.lastPerformance(exerciseName: "Deadlift"))
    }

    // MARK: - Units (kg / lb)

    func testWeightUnitConversionRoundTripsWithinEpsilon() {
        currentWeightUnit = .lb
        defer { currentWeightUnit = .kg }

        let kg = 100.0
        let lb = displayWeight(kg)             // 220.5 (nearest 0.5 lb)
        XCTAssertEqual(lb, 220.5)
        XCTAssertEqual(displayWeightToKg(lb), kg, accuracy: 0.05)
        XCTAssertEqual(formatWeight(kg), "220.5 lb")
    }

    func testTypedPoundsAreStoredAsKg() async {
        let app = AppState()
        app.setUnitPreference(.lb)
        defer { app.setUnitPreference(.kg) }

        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Bench Press")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "225", reps: "5")
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "")

        // 225 lb → 102.06 kg canonical storage.
        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].weight ?? 0, 102.06, accuracy: 0.05)
    }

    func testSwitchingUnitsConvertsInFlightDraftWeights() {
        let app = AppState()
        app.setUnitPreference(.kg)
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Squat")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "100")

        app.setUnitPreference(.lb)
        defer { app.setUnitPreference(.kg) }

        XCTAssertEqual(Double(app.todayExercises[0].sets[0].weight) ?? 0, 220.5, accuracy: 0.01)
    }

    func testOldSnapshotWithoutNewFieldsStillDecodes() throws {
        let json = #"{"sessions":[],"personalRecords":[],"waterByDay":{}}"#
        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.unitPreference)
        XCTAssertNil(snapshot.hasOnboarded)
        XCTAssertNil(snapshot.timerPreset)
    }

    // MARK: - Account deletion

    func testDeleteAccountWipesLocalStateAndReturnsToAuthChoice() async {
        let app = AppState()
        app.continueLocally()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Bench Press")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "60", reps: "8")
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "keep?")
        XCTAssertEqual(app.sessions.count, 1)
        XCTAssertFalse(app.personalRecords.isEmpty)

        let deleted = await app.deleteAccount()

        XCTAssertTrue(deleted)
        XCTAssertTrue(app.sessions.isEmpty)
        XCTAssertTrue(app.personalRecords.isEmpty)
        XCTAssertTrue(app.waterByDay.isEmpty)
        XCTAssertFalse(app.hasActiveWorkout)
        XCTAssertTrue(app.showingAuth)
    }

    // MARK: - Rest notification

    final class SpyNotifier: RestTimerNotifier {
        var scheduledAt: Date?
        override func schedule(at endsAt: Date) { scheduledAt = endsAt }
        override func cancel() { scheduledAt = nil }
    }

    func testTimerStartSchedulesRestNotificationAndResetCancelsIt() {
        let app = AppState()
        let spy = SpyNotifier()
        app.notifier = spy
        app.setTimerPreset(120)

        app.startTimer()
        XCTAssertNotNil(spy.scheduledAt)
        XCTAssertEqual(
            spy.scheduledAt!.timeIntervalSinceNow, 120, accuracy: 2,
            "notification should fire when the rest period ends"
        )

        app.resetTimer()
        XCTAssertNil(spy.scheduledAt)
        XCTAssertFalse(app.timerRunning)
    }

    // MARK: - Edit past session

    func testEditingSessionUpdatesVolumeAndPRAndReentersSyncQueue() async {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Squat")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "100", reps: "5")
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "")
        XCTAssertEqual(app.stats.volume, 500)
        XCTAssertEqual(app.personalRecords["Squat"]?.weight, 100)

        let edited = [ActiveExercise(name: "Squat", bodyweight: false, timed: false,
                                     sets: [WorkoutSet(weight: "110", reps: "5", done: true)])]
        await app.updateSession(id: app.sessions[0].id, exercises: edited, note: "corrected")

        XCTAssertEqual(app.stats.volume, 550)
        XCTAssertEqual(app.personalRecords["Squat"]?.weight, 110)
        XCTAssertEqual(app.sessions[0].note, "corrected")
        XCTAssertNotEqual(app.sessions[0].syncState, .synced)
    }

    // MARK: - Onboarding

    func testFinishOnboardingHidesIntroAndRoutesTheChoice() {
        let app = AppState()
        app.showingOnboarding = true
        app.finishOnboarding(createAccount: false)
        XCTAssertFalse(app.showingOnboarding)
        XCTAssertEqual(app.user?.isLocal, true)

        let app2 = AppState()
        app2.showingOnboarding = true
        app2.finishOnboarding(createAccount: true)
        XCTAssertFalse(app2.showingOnboarding)
        XCTAssertTrue(app2.showingAuth)
    }

}
