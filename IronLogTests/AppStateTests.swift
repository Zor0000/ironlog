import XCTest
import CoreLocation
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

    // MARK: - Run tracking

    /// Metres north of a base point, as a fix the tracker will accept.
    private func fix(metresNorth: Double, secondsLater: Double, accuracy: CLLocationAccuracy = 8) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 51.5 + metresNorth / 111_320, longitude: -0.12),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 4,
            timestamp: Date(timeIntervalSince1970: 1_000_000 + secondsLater)
        )
    }

    /// GPS wanders a couple of metres while you stand at a traffic light. Left
    /// unfiltered that drift is counted as distance and inflates every run.
    func testSubThresholdDriftIsNotCountedAsDistance() {
        let anchor = fix(metresNorth: 0, secondsLater: 0)
        let jitter = fix(metresNorth: 2, secondsLater: 2)
        XCTAssertEqual(RunTracker.verdict(from: anchor, to: jitter, kind: .run), .noise)
    }

    /// Crucially, drift must not advance the anchor either — otherwise slow
    /// walking is discarded one sub-threshold step at a time. Three 2m steps
    /// away from a kept anchor eventually clear the floor and count once.
    func testSlowMovementStillAccumulatesAgainstTheKeptAnchor() {
        let anchor = fix(metresNorth: 0, secondsLater: 0)
        XCTAssertEqual(RunTracker.verdict(from: anchor, to: fix(metresNorth: 2, secondsLater: 2), kind: .run), .noise)
        guard case .counted(let metres) = RunTracker.verdict(from: anchor, to: fix(metresNorth: 6, secondsLater: 6), kind: .run) else {
            return XCTFail("6m from the retained anchor should count")
        }
        XCTAssertEqual(metres, 6, accuracy: 0.5)
    }

    func testImplausibleSpeedIsRejectedAsAJump() {
        let anchor = fix(metresNorth: 0, secondsLater: 0)
        let teleport = fix(metresNorth: 500, secondsLater: 1)
        XCTAssertEqual(RunTracker.verdict(from: anchor, to: teleport, kind: .run), .jump)
    }

    func testRealStrideIsCounted() {
        let anchor = fix(metresNorth: 0, secondsLater: 0)
        guard case .counted(let metres) = RunTracker.verdict(from: anchor, to: fix(metresNorth: 10, secondsLater: 3), kind: .run) else {
            return XCTFail("10m in 3s is a run, not noise")
        }
        XCTAssertEqual(metres, 10, accuracy: 0.5)
    }

    func testInaccurateAndStaleFixesAreDistrusted() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Negative accuracy means CoreLocation has no fix at all.
        XCTAssertFalse(RunTracker.isTrustworthy(fix(metresNorth: 0, secondsLater: 0, accuracy: -1), now: now))
        XCTAssertFalse(RunTracker.isTrustworthy(fix(metresNorth: 0, secondsLater: 0, accuracy: 50), now: now))
        XCTAssertFalse(RunTracker.isTrustworthy(fix(metresNorth: 0, secondsLater: -60), now: now))
        XCTAssertTrue(RunTracker.isTrustworthy(fix(metresNorth: 0, secondsLater: 0), now: now))
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
        // Never queued for backup: the schema has nowhere to put the run.
        XCTAssertEqual(session.syncState, .localOnly)
        XCTAssertEqual(app.stats.sets, 0)
        XCTAssertEqual(app.stats.volume, 0)
        XCTAssertEqual(app.stats.streak, 1)
    }

    func testFinishingARunWithNothingTrackedSavesNothing() {
        let app = AppState()
        app.saveRun(nil)

        XCTAssertTrue(app.sessions.isEmpty)
        XCTAssertEqual(app.toast, "Nothing tracked yet — give it a few metres")
    }

    func testPaceIsPerDisplayUnitAndGuardsAgainstNonsense() {
        currentWeightUnit = .kg
        // 5 km in 30 min = 6:00 / km.
        XCTAssertEqual(formatPace(seconds: 1_800, metres: 5_000), "6:00")
        // Too little distance to mean anything yet.
        XCTAssertEqual(formatPace(seconds: 10, metres: 3), "--:--")
        XCTAssertEqual(formatPace(seconds: 0, metres: 5_000), "--:--")
    }

    func testElapsedGrowsIntoHours() {
        XCTAssertEqual(formatElapsed(65), "1:05")
        XCTAssertEqual(formatElapsed(1_450), "24:10")
        XCTAssertEqual(formatElapsed(3_862), "1:04:22")
    }

    /// The speed gate must scale with the activity. A cyclist at 20 m/s
    /// (72 km/h) on a descent is normal; judging that against a runner's ceiling
    /// would discard the fastest part of every ride, silently and with nothing
    /// in the UI to show for it.
    func testSpeedGateScalesWithTheActivity() {
        let anchor = fix(metresNorth: 0, secondsLater: 0)
        let fast = fix(metresNorth: 20, secondsLater: 1)

        XCTAssertEqual(RunTracker.verdict(from: anchor, to: fast, kind: .run), .jump)
        guard case .counted(let metres) = RunTracker.verdict(from: anchor, to: fast, kind: .cycle) else {
            return XCTFail("20 m/s is an ordinary descent on a bike")
        }
        XCTAssertEqual(metres, 20, accuracy: 0.5)
    }

    /// A brisk 4 m/s is a jog, believable inside a "walk"; 20 m/s is not.
    func testWalkGateIsTighterThanRunning() {
        let anchor = fix(metresNorth: 0, secondsLater: 0)
        guard case .counted = RunTracker.verdict(from: anchor, to: fix(metresNorth: 8, secondsLater: 2), kind: .walk) else {
            return XCTFail("4 m/s is a jog, not a teleport")
        }
        XCTAssertEqual(RunTracker.verdict(from: anchor, to: fix(metresNorth: 40, secondsLater: 2), kind: .walk), .jump)
    }

    /// A run recovered from disk must come back paused, keeping its distance and
    /// its elapsed time, and must say why it is paused.
    func testRestoredRunComesBackPausedAndIntact() {
        let tracker = RunTracker.shared
        tracker.discard()
        defer { tracker.discard() }

        tracker.restore(from: RunDraft(
            kind: .cycle,
            distance: 12_400,
            elapsed: 2_640,
            route: [RoutePoint(lat: 51.5, lon: -0.12), RoutePoint(lat: 51.51, lon: -0.12)],
            startedAt: Date(timeIntervalSince1970: 1_000_000)
        ))

        XCTAssertEqual(tracker.phase, .paused)
        XCTAssertEqual(tracker.interruption, .restored)
        XCTAssertEqual(tracker.kind, .cycle)
        XCTAssertEqual(tracker.distance, 12_400)
        XCTAssertEqual(tracker.elapsed, 2_640)
        XCTAssertEqual(tracker.route.count, 2)
        // Recovered work is savable straight away.
        XCTAssertEqual(tracker.activity?.distance, 12_400)
    }

    /// Discarding must leave nothing behind for the next run to inherit.
    func testDiscardClearsEverything() {
        let tracker = RunTracker.shared
        tracker.restore(from: RunDraft(kind: .run, distance: 500, elapsed: 120, route: [], startedAt: Date()))
        tracker.discard()

        XCTAssertEqual(tracker.phase, .idle)
        XCTAssertEqual(tracker.distance, 0)
        XCTAssertEqual(tracker.elapsed, 0)
        XCTAssertNil(tracker.interruption)
        XCTAssertNil(tracker.activity)
        XCTAssertFalse(tracker.hasActiveRun)
    }

    /// Every activity needs its own tile, label and icon in the picker.
    func testEveryCardioKindIsSelectable() {
        XCTAssertEqual(CardioKind.allCases, [.run, .walk, .cycle])
        for kind in CardioKind.allCases {
            XCTAssertFalse(kind.label.isEmpty)
            XCTAssertFalse(kind.icon.isEmpty)
            XCTAssertGreaterThan(kind.maxSpeed, 0)
        }
    }
}
