import XCTest
@testable import IronLog

@MainActor
final class AppStateTests: XCTestCase {
    func testCommaDecimalWeightIsNotMultipliedByTen() {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Bench Press")
        let exercise = app.todayExercises[0]
        app.updateSet(exerciseID: exercise.id, setID: exercise.sets[0].id, weight: "60,5", reps: "8")
        XCTAssertEqual(app.todayExercises[0].sets[0].weight, "60.5")
    }

    func testEditorRejectsInvalidRowWithoutLosingSavedSets() async {
        let app = AppState()
        let session = WorkoutSession(userID: nil, createdAt: Date(), muscle: nil, split: nil, note: "original", exercises: [
            LoggedExercise(name: "Push Ups", bodyweight: true, timed: false, sets: [LoggedSet(weight: nil, reps: 12)])
        ], syncState: .localOnly)
        app.sessions = [session]
        let edited = [ActiveExercise(name: "Push Ups", bodyweight: true, timed: false, sets: [
            WorkoutSet(reps: "15", done: true), WorkoutSet(reps: "", done: true)
        ])]
        let saved = await app.updateSession(id: session.id, exercises: edited, note: "changed")
        XCTAssertFalse(saved)
        XCTAssertEqual(app.sessions[0].note, "original")
        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].reps, 12)
        XCTAssertTrue(app.sessionValidationMessage(edited)?.contains("set 2") == true)
    }

    func testEditorRejectsMalformedOptionalWeight() {
        let app = AppState()
        let edited = [ActiveExercise(name: "Pull Ups", bodyweight: true, timed: false, sets: [
            WorkoutSet(weight: "12..5", reps: "8", done: true)
        ])]
        XCTAssertNotNil(app.sessionValidationMessage(edited))
    }

    func testManualCardioRejectsMalformedOptionalValuesAndNonfiniteNumbers() {
        XCTAssertNil(manualCardio(kind: .run, minutes: "30", distance: "abc"))
        XCTAssertNil(manualCardio(kind: .run, minutes: "30", distance: "-5"))
        XCTAssertNil(manualCardio(kind: .run, minutes: "30", distance: "", elevation: "-1"))
        XCTAssertNil(manualCardio(kind: .run, minutes: "1e300", distance: ""))
        XCTAssertNil(decimalEntry("nan"))
        XCTAssertNil(decimalEntry("inf"))
        XCTAssertNotNil(manualCardio(kind: .walk, minutes: "30,5", distance: ""))
    }

    func testCancelledToastDoesNotClearNewerMessage() async {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(name: "")
        app.saveRoutine(name: "")
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(app.toast, "Name the routine first")
    }

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

    /// Loaded calisthenics: weight is optional on a bodyweight move, not
    /// forbidden — a weighted walking lunge must keep its load through save.
    func testBodyweightExerciseKeepsTypedWeight() async {
        let app = AppState()
        app.startFreeWorkout()
        let lunge = app.library
            .catalogExercises(muscleID: "legs", query: "walking lunges")
            .first { $0.template.name == "Walking Lunges" }!
        app.addExercise(template: lunge.template)

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        XCTAssertTrue(app.todayExercises[0].bodyweight)

        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "20")
        app.updateSet(exerciseID: exerciseID, setID: setID, reps: "12")
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        XCTAssertTrue(app.todayExercises[0].sets[0].done)

        await app.finishWorkout(note: "")

        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].weight, 20)
        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].reps, 12)
        // Loaded work counts toward volume and sets a real PR.
        XCTAssertEqual(app.stats.volume, 240)
        XCTAssertEqual(app.personalRecords["Walking Lunges"]?.weight, 20)
    }

    /// Cardio machines are typed in whole minutes but stored in canonical
    /// seconds, and stay out of the PR table — "BW x 1200" reads as nonsense.
    func testCardioMinutesStoreAsSecondsAndSkipRecords() async {
        let app = AppState()
        app.startFreeWorkout()
        let bike = app.library
            .catalogExercises(muscleID: "cardio", query: "stationary bike")
            .first { $0.template.name == "Stationary Bike" }!
        XCTAssertTrue(bike.template.timed)
        XCTAssertTrue(bike.template.minutes)
        app.addExercise(template: bike.template)

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, reps: "20")
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        XCTAssertTrue(app.todayExercises[0].sets[0].done)

        await app.finishWorkout(note: "")

        let logged = app.sessions[0].exercises[0]
        XCTAssertTrue(logged.usesMinutes)
        XCTAssertEqual(logged.sets[0].reps, 1200)
        XCTAssertNil(logged.sets[0].weight)
        // No weight means no volume, and timed work earns no personal record.
        XCTAssertEqual(app.stats.volume, 0)
        XCTAssertNil(app.personalRecords["Stationary Bike"])
    }

    /// The seconds-based timed moves (holds, rope intervals) must be untouched
    /// by the minutes conversion.
    func testSecondsBasedTimedExerciseStoresRawSeconds() async {
        let app = AppState()
        app.startFreeWorkout()
        let plank = app.library
            .catalogExercises(muscleID: "core", query: "plank")
            .first { $0.template.name == "Plank" }!
        XCTAssertFalse(plank.template.minutes)
        app.addExercise(template: plank.template)

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, reps: "45")
        app.toggleDone(exerciseID: exerciseID, setID: setID)

        await app.finishWorkout(note: "")

        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].reps, 45)
        XCTAssertFalse(app.sessions[0].exercises[0].usesMinutes)
    }

    /// The unloaded case must still work: blank weight stays bodyweight rather
    /// than blocking the set the way a weighted exercise would.
    func testBodyweightExerciseStillLogsWithoutWeight() async {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(name: "Pull Ups")

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, reps: "10")
        app.toggleDone(exerciseID: exerciseID, setID: setID)

        await app.finishWorkout(note: "")

        XCTAssertNil(app.sessions[0].exercises[0].sets[0].weight)
        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].reps, 10)
    }

    func testCatalogSearchIgnoresWordOrderPluralsAndGymShorthand() {
        let library = ExerciseLibrary.bundled
        func names(_ query: String) -> [String] {
            library.catalogExercises(muscleID: nil, query: query).map(\.template.name)
        }

        // "DB" in the catalog, "dumbbell" in the query — and vice versa.
        XCTAssertTrue(names("dumbbell shoulder press").contains("Seated DB Shoulder Press"))
        XCTAssertTrue(names("db row").contains("Single-Arm Dumbbell Row"))
        // Plural query against a singular catalog name.
        XCTAssertTrue(names("lateral raises").contains("Dumbbell Lateral Raise"))
        // Word order and punctuation must not matter.
        XCTAssertTrue(names("press shoulder").contains("Seated DB Shoulder Press"))
        XCTAssertTrue(names("leg press").contains("Leg Press (Machine)"))
        // An empty query still returns the whole catalog; nonsense returns none.
        XCTAssertEqual(names("").count, names(" ").count)
        XCTAssertFalse(names("").isEmpty)
        XCTAssertTrue(names("zercher").isEmpty)
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

    func testEachSplitRoutesToItsCorrectWizardStep() {
        // Every split is day-based except Full Body (whole body in one session);
        // none reach the muscle-grid step anymore.
        let cases: [(split: String, step: WorkoutStep)] = [
            ("Full Body", .workout),
            ("PPL", .day),
            ("Upper/Lower", .day),
            ("Single Muscle", .day)    // one muscle per named day
        ]
        for c in cases {
            let app = AppState()
            app.selectSplit(c.split)
            XCTAssertEqual(app.workoutStep, c.step, c.split)
        }
    }

    func testSingleMuscleDayLoadsOneMuscleSession() {
        let app = AppState()
        app.selectSplit("Single Muscle")
        app.selectDay("Chest")

        XCTAssertEqual(app.workoutStep, .workout)
        XCTAssertEqual(app.selectedWorkoutMuscleIDs, ["chest"])
        XCTAssertEqual(app.singleTargetMuscle, "chest")   // history chip / catalog filter
        XCTAssertFalse(app.activeExerciseTemplates.isEmpty)
    }

    func testFullBodySkipsMuscleStepAndLoadsWholeBody() {
        let app = AppState()
        app.selectSplit("Full Body")

        // No single-muscle step — straight to the multi-muscle workout.
        XCTAssertEqual(app.workoutStep, .workout)
        XCTAssertEqual(app.singleTargetMuscle, nil)   // whole body has no single target
        XCTAssertEqual(app.selectedWorkoutMuscleIDs, ExerciseLibrary.fullBodyMuscleIDs)
        XCTAssertEqual(app.selectedWorkoutMuscleLabel, "Full Body")

        app.startWorkout()

        let muscles = Set(ExerciseLibrary.fullBodyMuscleIDs.compactMap { app.library.muscle($0) })
        XCTAssertGreaterThan(muscles.count, 1)
        XCTAssertFalse(app.todayExercises.isEmpty)
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
        XCTAssertNil(snapshot.bodyWeight)
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

    // MARK: - Half reps

    /// The grid itself. Anything typed between two halves lands on the nearer
    /// one, so the field can never hold a value that would be rejected later.
    func testTypedRepsSnapToTheNearestHalf() {
        XCTAssertEqual(snapReps("7"), "7")
        XCTAssertEqual(snapReps("7.5"), "7.5")
        XCTAssertEqual(snapReps("7.2"), "7", "below the midpoint falls back to the whole rep")
        XCTAssertEqual(snapReps("7.4"), "7.5", "above the midpoint climbs to the half")
        XCTAssertEqual(snapReps("7.7"), "7.5")
        XCTAssertEqual(snapReps("7.8"), "8", "a high fraction rounds up to the next whole")
        XCTAssertEqual(snapReps("12"), "12")
        XCTAssertEqual(snapReps(""), "")
    }

    /// A trailing "." must survive, or the user could never type the decimal
    /// point: snapping "7." to "7" on the keystroke makes "7.5" unreachable.
    func testARepsFieldMidDecimalIsLeftAlone() {
        XCTAssertEqual(snapReps("7."), "7.")
        XCTAssertEqual(snapReps("7,"), "7.", "the comma keyboards give still opens a decimal")
        XCTAssertEqual(snapReps("7,5"), "7.5")
    }

    /// Junk and over-typing cannot get through: one separator, one decimal
    /// digit, digits only.
    func testRepsInputRejectsAnythingOffTheGrid() {
        XCTAssertEqual(snapReps("7.55"), "7.5", "a second decimal key is dead — the grid is already full")
        XCTAssertEqual(snapReps("7.5.5"), "7.5")
        XCTAssertEqual(snapReps("7a.5b"), "7.5")
    }

    func testHalfRepIsSnappedOnEntryAndSurvivesToTheSavedSession() async {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Pull Ups")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id

        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "100", reps: "7.4")
        XCTAssertEqual(app.todayExercises[0].sets[0].reps, "7.5", "the field shows the snapped value immediately")

        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "")

        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].reps, 7.5)
        XCTAssertEqual(app.stats.volume, 750, "half a rep is half the volume")
        XCTAssertEqual(app.personalRecords["Pull Ups"]?.reps, 7.5)
    }

    /// `reps` doubles as seconds for a timed move, where halves are noise.
    func testTimedSetsStayWholeNumbers() {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(template: ExerciseTemplate(name: "Plank", sets: 1, reps: "45", tip: "",
                                                   bodyweight: true, timed: true))
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id

        app.updateSet(exerciseID: exerciseID, setID: setID, reps: "45.5")
        XCTAssertEqual(app.todayExercises[0].sets[0].reps, "455", "the decimal point is stripped, not snapped")
    }

    /// `LocalStore.load` turns any decode failure into an empty snapshot, so
    /// widening `reps` from Int to Double had to stay readable — otherwise the
    /// first launch after the update silently wipes every saved workout.
    func testSnapshotsWrittenWithWholeRepsStillDecode() throws {
        let payload = """
        {"sessions":[{"id":"\(UUID().uuidString)","createdAt":"2026-03-01T18:20:00Z","muscle":"back","split":"PPL",
          "exercises":[{"id":"\(UUID().uuidString)","name":"Row","bodyweight":false,"timed":false,
                        "sets":[{"id":"\(UUID().uuidString)","weight":60,"reps":8}]}],
          "syncState":"synced"}],
         "personalRecords":[{"exerciseName":"Row","weight":60,"reps":8,"achievedAt":"2026-03-01T18:20:00Z"}],
         "waterByDay":{}}
        """
        // Same configuration `LocalStore` reads saved snapshots with.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AppSnapshot.self, from: Data(payload.utf8))

        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.sessions[0].exercises[0].sets[0].reps, 8)
        XCTAssertEqual(snapshot.personalRecords[0].reps, 8)
    }

    // MARK: - PR toast

    /// The toast fires when a record actually breaks — once. `personalRecords`
    /// stays on the pre-workout best until the session is saved, so without the
    /// de-dupe every back-off set at the same new weight re-announces the same PR.
    func testPRToastFiresOncePerRecordAndNotAtAll() async {
        let app = AppState()

        // Session one: no record to beat, so nothing is announced.
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Bench Press")
        var exerciseID = app.todayExercises[0].id
        app.updateSet(exerciseID: exerciseID, setID: app.todayExercises[0].sets[0].id, weight: "90", reps: "8")
        app.toast = nil // "Free workout started"
        app.toggleDone(exerciseID: exerciseID, setID: app.todayExercises[0].sets[0].id)
        XCTAssertNil(app.toast, "a first-ever set beats nothing")
        await app.finishWorkout(note: "")

        // Session two: three sets at a heavier weight — one PR, not three.
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Bench Press")
        exerciseID = app.todayExercises[0].id
        app.toast = nil
        var toasts = 0
        for index in 0..<3 {
            if index > 0 { app.addSet(to: exerciseID) }
            let setID = app.todayExercises[0].sets[index].id
            app.updateSet(exerciseID: exerciseID, setID: setID, weight: "100", reps: "8")
            app.toggleDone(exerciseID: exerciseID, setID: setID)
            if app.toast == "New PR on Bench Press" { toasts += 1 }
            app.toast = nil
        }

        XCTAssertEqual(toasts, 1, "100 kg was a PR once, not once per set")
    }

    // MARK: - Set types

    /// A warm-up must not inflate the day's tonnage, and must not be able to
    /// claim a personal record — those are the only two things the tag changes,
    /// so if they do not hold the tag is decoration.
    func testWarmUpSetsAreExcludedFromVolumeAndRecords() async {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Squat")
        let exerciseID = app.todayExercises[0].id
        let warmUpID = app.todayExercises[0].sets[0].id

        app.updateSet(exerciseID: exerciseID, setID: warmUpID, weight: "60", reps: "10")
        app.setType(exerciseID: exerciseID, setID: warmUpID, to: .warmup)
        app.toggleDone(exerciseID: exerciseID, setID: warmUpID)

        app.addSet(to: exerciseID)
        let workingID = app.todayExercises[0].sets[1].id
        app.updateSet(exerciseID: exerciseID, setID: workingID, weight: "100", reps: "5")
        app.toggleDone(exerciseID: exerciseID, setID: workingID)

        await app.finishWorkout(note: "")

        XCTAssertEqual(app.stats.volume, 500, "600 kg of warm-up is not the day's work")
        XCTAssertEqual(app.personalRecords["Squat"]?.weight, 100)
        XCTAssertEqual(app.personalRecords["Squat"]?.reps, 5)
        XCTAssertEqual(app.stats.sets, 2, "the set is still logged — only the maths skips it")
    }

    /// A heavier warm-up than any working set still cannot take the record.
    func testAWarmUpNeverBecomesAPersonalRecord() async {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Deadlift")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id

        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "200", reps: "1")
        app.setType(exerciseID: exerciseID, setID: setID, to: .warmup)
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "")

        XCTAssertNil(app.personalRecords["Deadlift"])
        XCTAssertEqual(app.stats.volume, 0)
    }

    /// Drop sets and sets to failure are working sets — harder ones. Only the
    /// warm-up is excluded.
    func testOtherSetTypesStillCount() async {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Curl")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id

        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "20", reps: "10")
        app.setType(exerciseID: exerciseID, setID: setID, to: .failure)
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "")

        XCTAssertEqual(app.stats.volume, 200)
        XCTAssertEqual(app.personalRecords["Curl"]?.weight, 20)
    }

    func testSetTypeSurvivesSaveAndReopeningForEdit() async {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Bench")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id

        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "40", reps: "12")
        app.setType(exerciseID: exerciseID, setID: setID, to: .drop)
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "")

        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].type, .drop)

        // The edit sheet round-trips through ActiveExercise/WorkoutSet.
        let reopened = [ActiveExercise(name: "Bench", bodyweight: false, timed: false,
                                       sets: [WorkoutSet(weight: "40", reps: "12", done: true, type: .drop)])]
        await app.updateSession(id: app.sessions[0].id, exercises: reopened, note: "")
        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].type, .drop, "editing must not strip the tag")
    }

    /// Clearing the tag puts the set back into the working maths.
    func testClearingTheTagRestoresTheSetToVolume() async {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Row")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id

        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "50", reps: "10")
        app.setType(exerciseID: exerciseID, setID: setID, to: .warmup)
        app.setType(exerciseID: exerciseID, setID: setID, to: nil)
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "")

        XCTAssertEqual(app.stats.volume, 500)
    }

    /// Drafts and sessions written before set types existed have no key at all.
    /// A non-Optional field would throw, and `LocalStore.load` turns that into
    /// an empty snapshot.
    func testSetsWithoutATypeStillDecode() throws {
        let workoutSet = try JSONDecoder().decode(
            WorkoutSet.self,
            from: Data(#"{"id":"\#(UUID().uuidString)","weight":"60","reps":"8","done":true}"#.utf8)
        )
        XCTAssertNil(workoutSet.type)

        let logged = try JSONDecoder().decode(
            LoggedSet.self,
            from: Data(#"{"id":"\#(UUID().uuidString)","weight":60,"reps":8}"#.utf8)
        )
        XCTAssertNil(logged.type)
        XCTAssertTrue(logged.isWorkingSet, "an untagged set is ordinary work")
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

    /// Tagging the wrong set must not be permanent: the editor writes the type
    /// straight into its draft, so `updateSession` has to carry the change and
    /// recompute the volume the tag was suppressing.
    func testEditingASessionCanRetagASet() async {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Squat")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "100", reps: "5")
        app.setType(exerciseID: exerciseID, setID: setID, to: .warmup)
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "")
        XCTAssertEqual(app.stats.volume, 0, "a warm-up is not the day's work")

        let corrected = [ActiveExercise(name: "Squat", bodyweight: false, timed: false,
                                        sets: [WorkoutSet(weight: "100", reps: "5", done: true, type: .drop)])]
        await app.updateSession(id: app.sessions[0].id, exercises: corrected, note: "")

        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].type, .drop)
        XCTAssertEqual(app.stats.volume, 500, "a drop set is work the warm-up tag was hiding")
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

    /// A finished bodyweight set legitimately has no weight. Seeding the stepper
    /// used to target the last *completed* set on a finished exercise, writing a
    /// PR weight into it — and `reconcileFromLiveActivity` folded that invented
    /// load back into the session on the next foreground.
    func testFinishedBodyweightSetIsNotSeededWithAPersonalRecord() {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(name: "Pull Ups")
        app.personalRecords["Pull Ups"] = PersonalRecord(
            exerciseName: "Pull Ups", weight: 20, reps: 6, achievedAt: Date()
        )

        // Log every set unloaded, so the exercise is finished and weight-free.
        let exerciseID = app.todayExercises[0].id
        for set in app.todayExercises[0].sets {
            app.updateSet(exerciseID: exerciseID, setID: set.id, reps: "10")
            app.toggleDone(exerciseID: exerciseID, setID: set.id)
        }
        XCTAssertTrue(app.todayExercises[0].sets.allSatisfy(\.done))

        let live = app.buildLiveState()

        XCTAssertTrue(live.exercises[0].sets.allSatisfy { $0.weight.isEmpty },
                      "A completed bodyweight set must not gain a weight it was never performed with")
    }

    /// Undo and Next/Prev both clear rest on the lock screen and cancel its
    /// notification. Reconcile only ever *resumed* a countdown, never stopped
    /// one, so the in-app timer kept counting against a rest that no longer
    /// existed — and would never alert, the notification having already gone.
    func testReconcileStopsAnInAppRestTheLockScreenCleared() async {
        let app = AppState()
        let spy = SpyNotifier()
        app.notifier = spy
        app.startFreeWorkout()
        app.addExercise(name: "Squat")
        app.startTimer()
        XCTAssertTrue(app.timerRunning)
        XCTAssertNotNil(spy.scheduledAt)

        var live = app.buildLiveState()
        live.restEndsAt = nil // what Undo / navigating exercises leaves behind
        LiveWorkoutEngine.shared.sync(live)
        await LiveWorkoutEngine.shared.waitForPendingOperations()

        app.reconcileFromLiveActivity()

        XCTAssertFalse(app.timerRunning, "the in-app countdown must not outlive the rest the lock screen cleared")
        XCTAssertNil(spy.scheduledAt, "and it must not be left waiting on a notification nobody will send")

        LiveWorkoutEngine.shared.end()
        await LiveWorkoutEngine.shared.waitForPendingOperations()
    }

    /// The wizard transition pushes left-to-right or right-to-left off this
    /// flag. It used to be hardcoded forward, so tapping Back slid the previous
    /// screen in from the wrong side and read as another step forward.
    func testWizardStepDirectionTracksForwardAndBack() {
        let app = AppState()
        XCTAssertFalse(app.steppingBack)

        app.selectSplit("PPL")
        XCTAssertEqual(app.workoutStep, .day)
        XCTAssertFalse(app.steppingBack, "split → day is forward")

        app.selectDay("Push")
        XCTAssertFalse(app.steppingBack, "day → workout is forward")

        // What the Back button does — it assigns the step directly.
        app.workoutStep = .day
        XCTAssertTrue(app.steppingBack, "workout → day is back")

        app.workoutStep = .split
        XCTAssertTrue(app.steppingBack, "day → split is back")

        // Full Body skips the day step; a two-step jump is still forward.
        app.workoutStep = .workout
        XCTAssertFalse(app.steppingBack, "split → workout skips a step but is forward")
    }

    // MARK: - Saved routines

    /// Builds the free workout someone runs every week, so it can be saved.
    private func stapleWorkout() -> AppState {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Barbell Squat")
        app.setAddExerciseWeighted(false)
        app.addExercise(name: "Pull Ups")

        // Three sets of squats, logged.
        let squatID = app.todayExercises[0].id
        app.addSet(to: squatID)
        app.addSet(to: squatID)
        for set in app.todayExercises[0].sets {
            app.updateSet(exerciseID: squatID, setID: set.id, weight: "100", reps: "5")
        }
        return app
    }

    func testSavingARoutineCapturesTheExercisesAndTheirShape() {
        let app = stapleWorkout()
        app.saveRoutine(name: "Anshul's Leg Day")

        XCTAssertEqual(app.routines.count, 1)
        let routine = app.routines[0]
        XCTAssertEqual(routine.name, "Anshul's Leg Day")
        XCTAssertEqual(routine.exercises.map(\.name), ["Barbell Squat", "Pull Ups"])

        let squat = routine.exercises[0]
        XCTAssertEqual(squat.sets, 3, "set count carries over so the routine starts the same shape")
        XCTAssertEqual(squat.reps, "5", "the reps actually logged become the target")
        XCTAssertFalse(squat.bodyweight)
        XCTAssertTrue(routine.exercises[1].bodyweight, "a bodyweight move stays bodyweight")
    }

    func testStartingARoutineStocksTheLogWithEmptySets() {
        let app = stapleWorkout()
        app.saveRoutine(name: "Anshul's Leg Day")
        let routine = app.routines[0]
        app.discardWorkout()
        XCTAssertFalse(app.hasActiveWorkout)

        app.startRoutine(routine)

        XCTAssertEqual(app.todayExercises.map(\.name), ["Barbell Squat", "Pull Ups"])
        XCTAssertEqual(app.todayExercises[0].sets.count, 3)
        XCTAssertEqual(app.selectedTab, .log)
        XCTAssertEqual(app.selectedSplit, "Anshul's Leg Day", "the routine names the session in History")
        XCTAssertEqual(app.selectedWorkoutMuscleLabel, "Anshul's Leg Day")
        // Sets arrive blank — a routine is a plan, not last week's numbers.
        XCTAssertTrue(app.todayExercises.allSatisfy { $0.sets.allSatisfy { $0.weight.isEmpty && $0.reps.isEmpty } })
        XCTAssertTrue(app.todayExercises.allSatisfy { !$0.expanded })
    }

    /// The staple gets tweaked over months; re-saving under the same name has to
    /// replace it, or the list fills with near-duplicates.
    func testResavingUnderTheSameNameReplacesTheRoutine() {
        let app = stapleWorkout()
        app.saveRoutine(name: "Anshul's Leg Day")
        app.addExercise(name: "Calf Raise")
        app.saveRoutine(name: "anshul's leg day") // and casing must not matter

        XCTAssertEqual(app.routines.count, 1)
        XCTAssertEqual(app.routines[0].exercises.count, 3)
        XCTAssertEqual(app.routines[0].name, "Anshul's Leg Day", "the original name and its casing stand")
    }

    func testMultipleRoutinesCoexist() {
        let app = stapleWorkout()
        app.saveRoutine(name: "Anshul's Leg Day")
        app.discardWorkout()
        app.startFreeWorkout()
        app.addExercise(name: "Barbell Row")
        app.saveRoutine(name: "Anshul's Pull Day")

        XCTAssertEqual(app.routines.map(\.name), ["Anshul's Leg Day", "Anshul's Pull Day"])

        app.deleteRoutine(app.routines[0].id)
        XCTAssertEqual(app.routines.map(\.name), ["Anshul's Pull Day"])
    }

    func testRoutineIsRejectedWithoutANameOrExercises() {
        let app = stapleWorkout()
        app.saveRoutine(name: "   ")
        XCTAssertTrue(app.routines.isEmpty)

        app.discardWorkout()
        app.saveRoutine(name: "Empty")
        XCTAssertTrue(app.routines.isEmpty, "nothing in the log means nothing to save")
    }

    func testStartingARoutineIsBlockedByAnActiveWorkout() {
        let app = stapleWorkout()
        app.saveRoutine(name: "Anshul's Leg Day")
        let routine = app.routines[0]

        // Still mid-workout: starting the routine must not wipe it.
        app.startRoutine(routine)

        XCTAssertEqual(app.todayExercises.count, 2)
        XCTAssertTrue(app.todayExercises[0].sets.contains { $0.weight == "100" }, "logged work survives")
    }

    /// The save sheet prefills from this, so tweaking your staple updates it
    /// instead of quietly creating "Leg Day 2".
    func testActiveWorkoutReportsTheRoutineItCameFrom() {
        let app = stapleWorkout()
        app.saveRoutine(name: "Anshul's Leg Day")
        let routine = app.routines[0]
        app.discardWorkout()
        XCTAssertNil(app.matchingRoutineName)

        app.startRoutine(routine)
        XCTAssertEqual(app.matchingRoutineName, "Anshul's Leg Day")
    }

    func testRoutinesSurviveASnapshotRoundTrip() throws {
        let routine = SavedRoutine(name: "Anshul's Pull Day", exercises: [
            ExerciseTemplate(name: "Barbell Row", sets: 4, reps: "8", tip: "")
        ])
        let snapshot = AppSnapshot(routines: [routine])
        let decoded = try JSONDecoder().decode(
            AppSnapshot.self, from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded.routines?.first?.name, "Anshul's Pull Day")
        XCTAssertEqual(decoded.routines?.first?.exercises.first?.sets, 4)
    }

    // MARK: - Manual cardio & calories

    /// ACSM running equation on the flat: VO₂ = 0.2·(166.67 m/min) + 3.5 =
    /// 36.83 mL/kg/min, which for 70 kg over 30 min converts through ~5 kcal
    /// per litre of O₂ to ≈ 387 kcal.
    func testRunningCaloriesFollowTheACSMEquation() {
        XCTAssertEqual(
            estimateCalories(kind: .run, durationSeconds: 1_800, distanceMetres: 5_000, elevationGainMetres: 0, bodyWeightKg: 70),
            387
        )
    }

    /// Climbing is extra work: 45 m over 5 km is a 0.9% grade, which the
    /// vertical term prices in.
    func testElevationGainAddsCalories() {
        XCTAssertEqual(
            estimateCalories(kind: .run, durationSeconds: 1_800, distanceMetres: 5_000, elevationGainMetres: 45, bodyWeightKg: 70),
            401
        )
    }

    /// The walking equation is cheaper per metre at the same speed.
    func testWalkingCostsLessThanRunningForTheSameWork() {
        let run = estimateCalories(kind: .run, durationSeconds: 1_800, distanceMetres: 5_000, elevationGainMetres: 0, bodyWeightKg: 70)
        let walk = estimateCalories(kind: .walk, durationSeconds: 1_800, distanceMetres: 5_000, elevationGainMetres: 0, bodyWeightKg: 70)
        XCTAssertEqual(walk, 212)
        XCTAssertLessThan(walk ?? 0, run ?? 0)
    }

    /// No distance means no speed for the ACSM equation, so published MET
    /// values stand in: 9.8 for running, 3.8 for walking.
    func testTimeOnlyEntriesFallBackToMETValues() {
        XCTAssertEqual(
            estimateCalories(kind: .run, durationSeconds: 1_800, distanceMetres: 0, elevationGainMetres: 0, bodyWeightKg: 70),
            343
        )
        XCTAssertEqual(
            estimateCalories(kind: .walk, durationSeconds: 2_700, distanceMetres: 0, elevationGainMetres: 0, bodyWeightKg: 70),
            200
        )
    }

    /// An estimate without a body weight or a duration would be a made-up
    /// number presented as one — both must refuse.
    func testCalorieEstimateNeedsABodyWeightAndADuration() {
        XCTAssertNil(estimateCalories(kind: .run, durationSeconds: 1_800, distanceMetres: 5_000, elevationGainMetres: 0, bodyWeightKg: 0))
        XCTAssertNil(estimateCalories(kind: .run, durationSeconds: 0, distanceMetres: 5_000, elevationGainMetres: 0, bodyWeightKg: 70))
    }

    /// The manual logger records elevation and terrain and attaches an
    /// estimate computed from the current body weight.
    func testManualCardioStoresElevationTerrainAndCalories() {
        currentWeightUnit = .kg
        currentBodyWeight = 70
        let activity = manualCardio(kind: .run, minutes: "30", distance: "5", elevation: "45", terrain: .trail)

        XCTAssertEqual(activity?.elevationGain, 45)
        XCTAssertEqual(activity?.terrain, .trail)
        XCTAssertEqual(activity?.calories, 401)

        // Blank elevation and terrain stay nil rather than zeroing, and a
        // time-only walk prices through the MET fallback (3.8 × 70 kg × ⅓ h).
        let plain = manualCardio(kind: .walk, minutes: "20", distance: "", elevation: "", terrain: nil)
        XCTAssertNil(plain?.elevationGain)
        XCTAssertNil(plain?.terrain)
        XCTAssertEqual(plain?.calories, 89)
    }

    /// The Settings field is the only way the estimates learn the user's size;
    /// it persists and mirrors into the global the helpers read.
    func testBodyWeightSettingDrivesTheEstimates() {
        let app = AppState()
        app.setBodyWeight(70.44)
        XCTAssertEqual(app.bodyWeight ?? 0, 70.4, accuracy: 0.01)
        XCTAssertEqual(currentBodyWeight, 70.4, accuracy: 0.01)
        XCTAssertEqual(
            manualCardio(kind: .run, minutes: "30", distance: "5")?.calories,
            estimateCalories(kind: .run, durationSeconds: 1_800, distanceMetres: 5_000, elevationGainMetres: 0, bodyWeightKg: 70.4)
        )

        app.setBodyWeight(nil)
        XCTAssertNil(app.bodyWeight)
        XCTAssertEqual(currentBodyWeight, 0)
        XCTAssertNil(manualCardio(kind: .run, minutes: "30", distance: "5")?.calories)
    }

    func testBodyWeightSurvivesASnapshotRoundTrip() throws {
        let snapshot = AppSnapshot(bodyWeight: 72.5)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: data)
        XCTAssertEqual(decoded.bodyWeight, 72.5)
    }

    /// A saved run joins the History timeline and the streak, contributes no
    /// sets or volume, and stays out of the cloud queue.
    func testSavedRunBecomesALocalCardioSession() {
        let app = AppState()
        app.saveRun(CardioActivity(kind: .run, duration: 1_800, distance: 5_000, route: []))

        XCTAssertEqual(app.sessions.count, 1)
        let session = app.sessions[0]
        XCTAssertTrue(session.isCardio)
        XCTAssertEqual(session.activity?.distance, 5_000)
        XCTAssertEqual(session.split, "Run")
        XCTAssertTrue(session.exercises.isEmpty)
        // No account is signed in here, so the session stays local-only.
        XCTAssertEqual(session.syncState, .localOnly)
        XCTAssertEqual(app.stats.sets, 0)
        XCTAssertEqual(app.stats.volume, 0)
        XCTAssertEqual(app.stats.streak, 1)
    }

    func testPaceIsPerDisplayUnitAndGuardsAgainstNonsense() {
        currentWeightUnit = .kg
        // 5 km in 30 min = 6:00 / km.
        XCTAssertEqual(formatPace(seconds: 1_800, metres: 5_000), "6:00")
        // Too little distance to mean anything yet.
        XCTAssertEqual(formatPace(seconds: 10, metres: 3), "--:--")
        XCTAssertEqual(formatPace(seconds: 0, metres: 5_000), "--:--")
    }

    /// Speed is the treadmill's favourite number and the complement of pace.
    func testSpeedIsPerDisplayUnit() {
        currentWeightUnit = .kg
        XCTAssertEqual(formatSpeed(seconds: 1_800, metres: 5_000), "10.0")
        XCTAssertEqual(speedUnitLabel, "km/h")

        currentWeightUnit = .lb
        XCTAssertEqual(formatSpeed(seconds: 1_800, metres: 5_000), "6.2")
        XCTAssertEqual(speedUnitLabel, "mph")
        currentWeightUnit = .kg

        XCTAssertEqual(formatSpeed(seconds: 1_800, metres: 3), "--")
    }

    func testElapsedGrowsIntoHours() {
        XCTAssertEqual(formatElapsed(65), "1:05")
        XCTAssertEqual(formatElapsed(1_450), "24:10")
        XCTAssertEqual(formatElapsed(3_862), "1:04:22")
    }

    /// Every activity needs its own tile, label and icon in the picker.
    func testEveryCardioKindIsSelectable() {
        XCTAssertEqual(CardioKind.allCases, [.run, .walk])
        for kind in CardioKind.allCases {
            XCTAssertFalse(kind.label.isEmpty)
            XCTAssertFalse(kind.icon.isEmpty)
        }
        XCTAssertEqual(CardioTerrain.allCases, [.road, .trail, .treadmill, .track])
        for terrain in CardioTerrain.allCases {
            XCTAssertFalse(terrain.label.isEmpty)
            XCTAssertFalse(terrain.icon.isEmpty)
        }
    }

    /// The manual logger needs a duration and nothing else. Distance is typed
    /// in the display unit and is optional — a treadmill showing only a clock
    /// still produces a session worth keeping.
    func testManualEntryNeedsTimeButNotDistance() {
        currentWeightUnit = .kg
        XCTAssertNil(manualCardio(kind: .run, minutes: "", distance: "5"))
        XCTAssertNil(manualCardio(kind: .run, minutes: "0", distance: "5"))

        let timeOnly = manualCardio(kind: .walk, minutes: "45", distance: "")
        XCTAssertEqual(timeOnly?.duration, 2_700)
        XCTAssertEqual(timeOnly?.distance, 0)
        XCTAssertEqual(timeOnly?.kind, .walk)

        // Typed in the display unit, stored as metres — and a comma separator
        // is what most of the world's keyboards produce.
        XCTAssertEqual(manualCardio(kind: .run, minutes: "30", distance: "5,5")?.distance, 5_500)

        currentWeightUnit = .lb
        XCTAssertEqual(manualCardio(kind: .run, minutes: "30", distance: "3")?.distance ?? 0, 4_828, accuracy: 1)
        currentWeightUnit = .kg
    }

    /// A back-dated manual run belongs where its date puts it, not on top.
    func testBackDatedRunSortsIntoTheTimeline() {
        let app = AppState()
        app.saveRun(CardioActivity(kind: .run, duration: 600, distance: 2_000, route: []))
        app.saveRun(
            CardioActivity(kind: .walk, duration: 1_800, distance: 3_000, route: []),
            at: Date().addingTimeInterval(-86_400)
        )

        XCTAssertEqual(app.sessions.count, 2)
        XCTAssertEqual(app.sessions.first?.activity?.kind, .run)
        XCTAssertEqual(app.sessions.last?.activity?.kind, .walk)
    }

    /// Sessions saved under the removed "cycle" kind must still decode. A throw
    /// here costs the user everything: `LocalStore.load` drops the whole
    /// snapshot — every workout, routine and setting — on any decode error.
    func testRetiredCardioKindStillDecodes() throws {
        let json = Data(#"{"kind":"cycle","duration":2640,"distance":12400,"route":[]}"#.utf8)
        let activity = try JSONDecoder().decode(CardioActivity.self, from: json)

        XCTAssertEqual(activity.kind, .walk)
        XCTAssertEqual(activity.distance, 12_400)
        XCTAssertEqual(activity.duration, 2_640)
        XCTAssertNil(activity.elevationGain)
        XCTAssertNil(activity.terrain)
        XCTAssertNil(activity.calories)
    }

    /// An unknown terrain string must not be able to wipe the snapshot — see
    /// `CardioTerrain.init(from:)` for the same rationale as `CardioKind`.
    func testUnknownTerrainStillDecodes() throws {
        let json = Data(#"{"kind":"run","duration":600,"distance":2000,"route":[],"terrain":"swamp"}"#.utf8)
        let activity = try JSONDecoder().decode(CardioActivity.self, from: json)
        XCTAssertEqual(activity.terrain, .road)
    }
}
