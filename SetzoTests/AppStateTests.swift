import XCTest
import AuthenticationServices
@testable import Setzo

@MainActor
final class AppStateTests: XCTestCase {
    func testCancellingGoogleSignInPreservesLocalWorkoutAndClearsBusyState() async {
        let cloud = OfflineCloud()
        cloud.googleSignInError = NSError(domain: ASWebAuthenticationSessionErrorDomain,
                                         code: ASWebAuthenticationSessionError.canceledLogin.rawValue)
        let app = AppState(supabase: cloud, allowDebugSeeds: false)
        app.startFreeWorkout()
        app.addExercise(name: "Push Ups")
        let exerciseID = app.todayExercises[0].id
        app.authMessage = "Previous sign-in failed"

        await app.signInWithGoogle()

        XCTAssertFalse(app.isBusy)
        XCTAssertNil(app.authMessage)
        XCTAssertNil(app.user)
        XCTAssertEqual(app.todayExercises.first?.id, exerciseID)
    }

    func testGoogleSignInFailureStillShowsTheError() async {
        let cloud = OfflineCloud()
        cloud.googleSignInError = URLError(.notConnectedToInternet)
        let app = AppState(supabase: cloud, allowDebugSeeds: false)

        await app.signInWithGoogle()

        XCTAssertFalse(app.isBusy)
        XCTAssertEqual(app.authMessage, URLError(.notConnectedToInternet).localizedDescription)
        XCTAssertNil(app.user)
    }

    func testExerciseCanMoveUpAndDownWithoutLosingItsLoggedWork() {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(name: "Squat")
        app.addExercise(name: "Bench Press")
        app.addExercise(name: "Deadlift")

        let squatID = app.todayExercises[0].id
        let squatSetID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: squatID, setID: squatSetID, reps: "5")

        app.moveExercise(squatID, to: 2)

        XCTAssertEqual(app.todayExercises.map(\.name), ["Bench Press", "Deadlift", "Squat"])
        XCTAssertEqual(app.todayExercises[2].id, squatID)
        XCTAssertEqual(app.todayExercises[2].sets[0].id, squatSetID)
        XCTAssertEqual(app.todayExercises[2].sets[0].reps, "5")

        app.moveExercise(squatID, to: 0)
        XCTAssertEqual(app.todayExercises.map(\.name), ["Squat", "Bench Press", "Deadlift"])
    }

    func testExerciseMoveClampsDestinationAndIgnoresUnknownExercise() {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(name: "Pull Ups")
        app.addExercise(name: "Dips")
        let pullUpID = app.todayExercises[0].id

        app.moveExercise(pullUpID, to: 99)
        XCTAssertEqual(app.todayExercises.map(\.name), ["Dips", "Pull Ups"])

        app.moveExercise(UUID(), to: 0)
        XCTAssertEqual(app.todayExercises.map(\.name), ["Dips", "Pull Ups"])
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
        XCTAssertEqual(app.toast, "Enter 0.5–1,000 reps before marking the set done")
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
        XCTAssertEqual(app.toast, "Enter 0–1,000 kg and 0.5–1,000 reps before marking the set done")

        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "100..5kg")
        app.toggleDone(exerciseID: exerciseID, setID: setID)

        XCTAssertEqual(app.todayExercises[0].sets[0].weight, "100.5")
        XCTAssertTrue(app.todayExercises[0].sets[0].done)
        XCTAssertEqual(app.validCompletedSetCount, 1)
    }

    func testCommaDecimalWeightIsNormalizedAndSavedWithoutChangingItsValue() async {
        let app = AppState()
        app.startFreeWorkout()
        app.setAddExerciseWeighted(true)
        app.addExercise(name: "Bench Press")

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, weight: "60,5", reps: "8")

        XCTAssertEqual(app.todayExercises[0].sets[0].weight, "60.5")
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "")

        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].weight, 60.5)
    }

    func testCustomSetRemarkIsTrimmedAndSaved() async {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(name: "Push Ups")

        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, reps: "12")
        app.setRemark(exerciseID: exerciseID, setID: setID, to: "  Slow eccentric  ")
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        await app.finishWorkout(note: "")

        XCTAssertEqual(app.sessions[0].exercises[0].sets[0].remark, "Slow eccentric")
    }

    func testOnlyCompletelyEmptySetSkipsDeletionConfirmation() {
        XCTAssertFalse(WorkoutSet().hasEnteredData)
        XCTAssertFalse(WorkoutSet(done: true).hasEnteredData)
        XCTAssertFalse(WorkoutSet(remark: "   ").hasEnteredData)
        XCTAssertTrue(WorkoutSet(weight: "20").hasEnteredData)
        XCTAssertTrue(WorkoutSet(type: .warmup).hasEnteredData)
        XCTAssertTrue(WorkoutSet(remark: "Form broke").hasEnteredData)
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
        XCTAssertEqual(app.selectedTab, .progress)
        XCTAssertEqual(app.progressSection, .history)
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

    func testExpandedCatalogIncludesCommonMachineAndConditioningOptions() {
        let library = ExerciseLibrary.bundled
        let minimumCounts = [
            "chest": 18,
            "back": 20,
            "legs": 28,
            "shoulders": 18,
            "biceps": 15,
            "triceps": 16,
            "core": 22,
            "cardio": 20
        ]

        for (muscleID, minimum) in minimumCounts {
            XCTAssertGreaterThanOrEqual(library.library[muscleID]?.count ?? 0, minimum, "\(muscleID) catalog")
        }

        XCTAssertTrue(library.catalogExercises(muscleID: "chest", query: "smith machine bench press").contains {
            $0.template.name == "Smith Machine Bench Press"
        })
        XCTAssertTrue(library.catalogExercises(muscleID: "legs", query: "hack squat machine").contains {
            $0.template.name == "Hack Squat (Machine)"
        })
        XCTAssertTrue(library.catalogExercises(muscleID: "cardio", query: "arc trainer").contains {
            $0.template.name == "Arc Trainer"
        })
    }

    private func finderLibrary(_ names: [String], bodyweight: Set<String> = []) -> ExerciseLibrary {
        let shoulder = Muscle(id: "shoulders", label: "Shoulders", systemImage: "figure.arms.open")
        let templates = names.map {
            ExerciseTemplate(name: $0, sets: 3, reps: "8–10", tip: "", bodyweight: bodyweight.contains($0))
        }
        return ExerciseLibrary(
            splits: [],
            muscles: [shoulder],
            splitDays: [:],
            workouts: [:],
            library: ["shoulders": templates]
        )
    }

    private func finderSession(_ names: [String], daysAgo: Int, now: Date) -> WorkoutSession {
        WorkoutSession(
            createdAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            muscle: "shoulders",
            split: nil,
            note: nil,
            exercises: names.map { LoggedExercise(name: $0, bodyweight: false, timed: false, sets: []) }
        )
    }

    func testExerciseFinderStaysWithinMuscleAndExcludesCurrentWorkout() {
        let app = AppState()
        let engine = ExerciseRecommendationEngine(
            library: app.library,
            sessions: [],
            currentExerciseNames: ["Barbell Overhead Press"]
        )

        let matches = engine.candidates(for: "shoulders")

        XCTAssertEqual(matches.count, (app.library.library["shoulders"]?.count ?? 0) - 1)
        XCTAssertTrue(matches.allSatisfy { $0.muscle.id == "shoulders" })
        XCTAssertFalse(matches.contains { $0.template.name == "Barbell Overhead Press" })
        XCTAssertEqual(Set(matches.map(\.id)).count, matches.count)
        XCTAssertTrue(matches.allSatisfy { (0...1).contains($0.score) })
    }

    func testExerciseFinderScoresAreNotDrivenByCatalogPosition() {
        // Identical history for every entry: the catalog order must not decide
        // the ranking, only names (as a stable tie-break) and factors.
        let library = finderLibrary(["Zulu Raise", "Alpha Raise", "Mid Raise"])
        let engine = ExerciseRecommendationEngine(library: library, sessions: [], currentExerciseNames: [])

        let candidates = engine.candidates(for: "shoulders")

        XCTAssertEqual(Set(candidates.map(\.score)).count, 1)
        XCTAssertEqual(candidates.map(\.template.name), ["Alpha Raise", "Mid Raise", "Zulu Raise"])
        XCTAssertTrue(candidates.allSatisfy { $0.factors == [.neverLogged] })
    }

    func testExerciseFinderRotatesAwayFromVeryRecentExercise() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let library = finderLibrary(["Primary Raise", "Alternate Raise"])
        let recent = finderSession(["Primary Raise"], daysAgo: 1, now: now)

        let rotated = ExerciseRecommendationEngine(
            library: library,
            sessions: [recent],
            currentExerciseNames: [],
            now: now
        ).candidates(for: "shoulders")

        XCTAssertEqual(rotated.first?.template.name, "Alternate Raise")
        XCTAssertEqual(rotated.last?.factors, [.trainedRecently(days: 1)])
        XCTAssertLessThan(rotated.last!.score, rotated.first!.score)
    }

    func testExerciseFinderReasonsMatchFactors() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let library = finderLibrary(["Rested Press", "Fresh Raise", "Busy Raise"])
        let sessions = [
            finderSession(["Rested Press"], daysAgo: 21, now: now),
            finderSession(["Busy Raise"], daysAgo: 4, now: now),
            finderSession(["Busy Raise"], daysAgo: 9, now: now),
            finderSession(["Busy Raise"], daysAgo: 15, now: now)
        ]
        let candidates = ExerciseRecommendationEngine(
            library: library,
            sessions: sessions,
            currentExerciseNames: [],
            now: now
        ).candidates(for: "shoulders")
        let byName = Dictionary(uniqueKeysWithValues: candidates.map { ($0.template.name, $0) })

        XCTAssertEqual(byName["Rested Press"]?.factors, [.restedFor(days: 21), .addsCompound])
        XCTAssertEqual(byName["Rested Press"]?.reason, "Back in rotation after 21 days.")
        XCTAssertEqual(byName["Fresh Raise"]?.factors, [.neverLogged])
        XCTAssertEqual(byName["Fresh Raise"]?.reason, "A fresh pick you haven't logged yet.")
        XCTAssertEqual(byName["Busy Raise"]?.factors, [.trainedRecently(days: 4), .frequentlyUsed(count: 3)])
        XCTAssertEqual(ExerciseRecommendationFactor.frequentlyUsed(count: 3).label, "Used 3× in 30 days")
        // Only negative factors: the copy falls back to a neutral line rather
        // than inventing a reason.
        XCTAssertEqual(byName["Busy Raise"]?.reason, "A solid shoulders option from your library.")
    }

    func testExerciseFinderComplementsCurrentWorkout() {
        let library = finderLibrary(["Overhead Press", "Lateral Raise", "Arnold Press"])
        let withoutCompound = ExerciseRecommendationEngine(library: library, sessions: [], currentExerciseNames: [])
            .candidates(for: "shoulders")
        let withCompound = ExerciseRecommendationEngine(library: library, sessions: [], currentExerciseNames: ["Arnold Press"])
            .candidates(for: "shoulders")

        XCTAssertEqual(withoutCompound.first?.movementStyle, "Compound")
        XCTAssertTrue(withoutCompound.first!.factors.contains(.addsCompound))
        XCTAssertEqual(withoutCompound.last?.template.name, "Lateral Raise")
        XCTAssertEqual(withCompound.map(\.template.name), ["Lateral Raise", "Overhead Press"])
        XCTAssertTrue(withCompound.first!.factors.contains(.complementsCompound))
        XCTAssertFalse(withCompound.last!.factors.contains(.addsCompound))
    }

    func testExerciseFinderSelectorHandlesEmptyAndSinglePools() {
        var selector = ExerciseFinderSelector(generator: SeededRandomNumberGenerator(seed: 1))
        XCTAssertNil(selector.select(from: []))

        let single = ExerciseRecommendationEngine(library: finderLibrary(["Only Raise"]), sessions: [], currentExerciseNames: [])
            .candidates(for: "shoulders")
        for _ in 0..<3 {
            let result = selector.select(from: single)
            XCTAssertEqual(result?.selected.template.name, "Only Raise")
            XCTAssertEqual(result?.alternates, [])
            XCTAssertEqual(result?.poolSize, 1)
        }
    }

    func testExerciseFinderSelectorTraversesPoolBeforeRepeating() {
        let names = ["A Raise", "B Raise", "C Raise", "D Raise", "E Raise"]
        let candidates = ExerciseRecommendationEngine(library: finderLibrary(names), sessions: [], currentExerciseNames: [])
            .candidates(for: "shoulders")
        var selector = ExerciseFinderSelector(generator: SeededRandomNumberGenerator(seed: 7))

        var firstCycle: [String] = []
        for _ in names.indices {
            let result = selector.select(from: candidates)!
            XCTAssertFalse(result.cycleRestarted)
            XCTAssertEqual(result.poolSize, names.count)
            XCTAssertEqual(result.alternates.count, names.count - 1)
            XCTAssertFalse(result.alternates.contains(result.selected))
            firstCycle.append(result.selected.template.name)
        }
        XCTAssertEqual(Set(firstCycle), Set(names), "every viable candidate is shown before any repeat")

        let restarted = selector.select(from: candidates)!
        XCTAssertTrue(restarted.cycleRestarted)
        XCTAssertNotEqual(restarted.selected.template.name, firstCycle.last, "no immediate repeat on restart")
    }

    func testExerciseFinderSelectorKeepsTiedCandidatesAtTheCutoff() {
        // Eight never-logged isolation moves all score the same: the pool must
        // hold all eight, and Try another must reach every one of them.
        let names = (1...8).map { "Raise \($0)" }
        let candidates = ExerciseRecommendationEngine(library: finderLibrary(names), sessions: [], currentExerciseNames: [])
            .candidates(for: "shoulders")
        XCTAssertEqual(Set(candidates.map(\.score)).count, 1)

        let pool = ExerciseFinderSelector<SeededRandomNumberGenerator>.qualifiedPool(from: candidates, limit: 5, margin: 0.35)
        XCTAssertEqual(pool.count, 8)

        var selector = ExerciseFinderSelector(generator: SeededRandomNumberGenerator(seed: 9))
        let firstCycle = Set((0..<8).map { _ in selector.select(from: candidates)!.selected.template.name })
        XCTAssertEqual(firstCycle, Set(names))

        // A genuinely lower-scoring tail is still cut.
        let now = Date(timeIntervalSince1970: 2_000_000)
        let mixed = ExerciseRecommendationEngine(
            library: finderLibrary(names + ["Stale Raise"]),
            sessions: [finderSession(["Stale Raise"], daysAgo: 1, now: now)],
            currentExerciseNames: [],
            now: now
        ).candidates(for: "shoulders")
        let mixedPool = ExerciseFinderSelector<SeededRandomNumberGenerator>.qualifiedPool(from: mixed, limit: 5, margin: 0.35)
        XCTAssertEqual(mixedPool.count, 8)
        XCTAssertFalse(mixedPool.contains { $0.template.name == "Stale Raise" })
    }

    func testExerciseFinderSelectorIsReproducibleForSameSeed() {
        let names = ["A Raise", "B Raise", "C Raise", "D Raise"]
        let candidates = ExerciseRecommendationEngine(library: finderLibrary(names), sessions: [], currentExerciseNames: [])
            .candidates(for: "shoulders")

        func run(seed: UInt64) -> [String] {
            var selector = ExerciseFinderSelector(generator: SeededRandomNumberGenerator(seed: seed))
            return (0..<8).map { _ in selector.select(from: candidates)!.selected.template.name }
        }

        XCTAssertEqual(run(seed: 42), run(seed: 42))
        XCTAssertNotEqual(run(seed: 42), run(seed: 43))
    }

    func testExerciseFinderSelectorVariesAcrossSeeds() {
        let names = ["A Raise", "B Raise", "C Raise", "D Raise", "E Raise"]
        let candidates = ExerciseRecommendationEngine(library: finderLibrary(names), sessions: [], currentExerciseNames: [])
            .candidates(for: "shoulders")

        let firstPicks = Set((0..<40).map { seed -> String in
            var selector = ExerciseFinderSelector(generator: SeededRandomNumberGenerator(seed: UInt64(seed)))
            return selector.select(from: candidates)!.selected.template.name
        })

        XCTAssertGreaterThan(firstPicks.count, 1, "the first pick is not tied to catalog order")
    }

    func testExerciseFinderSelectorResetForgetsHistory() {
        let candidates = ExerciseRecommendationEngine(library: finderLibrary(["A Raise", "B Raise", "C Raise"]), sessions: [], currentExerciseNames: [])
            .candidates(for: "shoulders")
        var selector = ExerciseFinderSelector(generator: SeededRandomNumberGenerator(seed: 3))
        for _ in 0..<3 { _ = selector.select(from: candidates) }

        selector.reset()

        XCTAssertFalse(selector.select(from: candidates)!.cycleRestarted)
    }

    func testExerciseFinderSelectorNeverLeavesTheViablePool() {
        // The excluded exercise is filtered before selection and can't re-enter.
        let library = finderLibrary(["A Raise", "B Raise", "C Raise", "Excluded Raise"])
        let candidates = ExerciseRecommendationEngine(library: library, sessions: [], currentExerciseNames: ["Excluded Raise"])
            .candidates(for: "shoulders")
        var selector = ExerciseFinderSelector(generator: SeededRandomNumberGenerator(seed: 11))

        for _ in 0..<12 {
            let result = selector.select(from: candidates)!
            XCTAssertNotEqual(result.selected.template.name, "Excluded Raise")
            XCTAssertFalse(result.alternates.contains { $0.template.name == "Excluded Raise" })
        }
    }

    func testExerciseFinderSelectorChoosesAlternateOnlyFromPool() {
        let candidates = ExerciseRecommendationEngine(library: finderLibrary(["A Raise", "B Raise", "C Raise"]), sessions: [], currentExerciseNames: [])
            .candidates(for: "shoulders")
        var selector = ExerciseFinderSelector(generator: SeededRandomNumberGenerator(seed: 5))
        let result = selector.select(from: candidates)!
        let alternate = result.alternates[0]

        let chosen = selector.choose(alternate, from: candidates)
        XCTAssertEqual(chosen?.selected, alternate)
        XCTAssertFalse(chosen!.alternates.contains(alternate))

        let outsider = ExerciseRecommendation(
            template: ExerciseTemplate(name: "Outsider", sets: 3, reps: "10", tip: ""),
            muscle: alternate.muscle,
            score: 1,
            movementStyle: "Isolation",
            factors: []
        )
        XCTAssertNil(selector.choose(outsider, from: candidates))
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

    func testDeleteWorkoutDataWipesWorkoutStateAndKeepsCurrentProfile() async {
        let app = AppState()
        app.continueLocally()
        app.saveNutritionPassport(NutritionPassport())
        XCTAssertNotNil(app.nutritionPassport)
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

        let deleted = await app.deleteWorkoutData()

        XCTAssertTrue(deleted)
        XCTAssertTrue(app.sessions.isEmpty)
        XCTAssertTrue(app.personalRecords.isEmpty)
        XCTAssertTrue(app.waterByDay.isEmpty)
        XCTAssertNil(app.nutritionPassport)
        XCTAssertFalse(app.hasActiveWorkout)
        XCTAssertFalse(app.showingAuth)
        XCTAssertEqual(app.user?.id, "local")
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

    /// A pasted decimal must not silently become ten times longer. Seconds
    /// remain whole; minutes can represent a half-minute exactly.
    func testTimedSecondsRejectFractionsInsteadOfChangingTheirValue() {
        let app = AppState()
        app.startFreeWorkout()
        app.addExercise(template: ExerciseTemplate(name: "Plank", sets: 1, reps: "45", tip: "",
                                                   bodyweight: true, timed: true))
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id

        app.updateSet(exerciseID: exerciseID, setID: setID, reps: "45.5")
        XCTAssertEqual(app.todayExercises[0].sets[0].reps, "45.5")
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        XCTAssertFalse(app.todayExercises[0].sets[0].done)
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

    func testMultipleRoutinesCoexist() async {
        let app = stapleWorkout()
        app.saveRoutine(name: "Anshul's Leg Day")
        app.discardWorkout()
        app.startFreeWorkout()
        app.addExercise(name: "Barbell Row")
        app.saveRoutine(name: "Anshul's Pull Day")

        XCTAssertEqual(app.routines.map(\.name), ["Anshul's Leg Day", "Anshul's Pull Day"])

        await app.deleteRoutine(app.routines[0].id)
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
    func testSavedRunBecomesALocalCardioSession() async {
        let app = AppState()
        await app.saveRun(CardioActivity(kind: .run, duration: 1_800, distance: 5_000, route: []))

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
    func testBackDatedRunSortsIntoTheTimeline() async {
        let app = AppState()
        await app.saveRun(CardioActivity(kind: .run, duration: 600, distance: 2_000, route: []))
        await app.saveRun(
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

    func testLocalStoreKeepsGuestAndAccountsIsolated() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SetzoLocalStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStore(directory: directory)

        func snapshot(_ label: String) -> AppSnapshot {
            AppSnapshot(sessions: [WorkoutSession(createdAt: Date(), split: label, exercises: [])])
        }

        try await store.save(snapshot("Guest"), ownerID: nil)
        try await store.save(snapshot("Account A"), ownerID: "user-a")
        try await store.save(snapshot("Account B"), ownerID: "user-b")

        let guest = try await store.load(ownerID: nil)
        let accountA = try await store.load(ownerID: "user-a")
        let accountB = try await store.load(ownerID: "user-b")
        XCTAssertEqual(guest.sessions.first?.split, "Guest")
        XCTAssertEqual(accountA.sessions.first?.split, "Account A")
        XCTAssertEqual(accountB.sessions.first?.split, "Account B")

        try await store.clear(ownerID: "user-a")
        let clearedAccountA = try await store.load(ownerID: "user-a")
        let unchangedAccountB = try await store.load(ownerID: "user-b")
        XCTAssertTrue(clearedAccountA.sessions.isEmpty)
        XCTAssertEqual(unchangedAccountB.sessions.first?.split, "Account B")
    }

    func testLegacyStoreMigrationClaimsDataOnlyForFirstAccountStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SetzoLegacyStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStore(directory: directory)
        let legacy = AppSnapshot(sessions: [WorkoutSession(createdAt: Date(), split: "Legacy", exercises: [])])

        try await store.save(legacy, ownerID: nil)
        try await store.migrateLegacyStoreIfNeeded(to: "user-a")

        let migratedGuest = try await store.load(ownerID: nil)
        let migratedAccount = try await store.load(ownerID: "user-a")
        XCTAssertTrue(migratedGuest.sessions.isEmpty)
        XCTAssertEqual(migratedAccount.sessions.first?.split, "Legacy")

        let newGuest = AppSnapshot(sessions: [WorkoutSession(createdAt: Date(), split: "New Guest", exercises: [])])
        try await store.save(newGuest, ownerID: nil)
        try await store.migrateLegacyStoreIfNeeded(to: "user-a")

        let retainedGuest = try await store.load(ownerID: nil)
        let retainedAccount = try await store.load(ownerID: "user-a")
        XCTAssertEqual(retainedGuest.sessions.first?.split, "New Guest")
        XCTAssertEqual(retainedAccount.sessions.first?.split, "Legacy")

        // An account with only a recovery copy is still an existing account;
        // migrating the guest over it would misattribute two people's data.
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        let firstB = AppSnapshot(sessions: [WorkoutSession(createdAt: Date(), split: "Account B recovery", exercises: [])])
        try await store.save(firstB, ownerID: "user-b")
        try await store.save(AppSnapshot(sessions: []), ownerID: "user-b")
        let added = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)).subtracting(before)
        let accountBPrimary = try XCTUnwrap(added.first { $0.hasPrefix("store-") && $0.hasSuffix(".json") })
        try FileManager.default.removeItem(at: directory.appendingPathComponent(accountBPrimary))
        try await store.migrateLegacyStoreIfNeeded(to: "user-b")
        let recoveredB = try await store.load(ownerID: "user-b")
        let untouchedGuest = try await store.load(ownerID: nil)
        XCTAssertEqual(recoveredB.sessions.first?.split, "Account B recovery")
        XCTAssertEqual(untouchedGuest.sessions.first?.split, "New Guest")
    }
}

private final class OfflineCloud: SupabaseService {
    var googleSignInError: Error?
    var profile: UserProfile?
    var offline = false
    var remoteSessions: [WorkoutSession] = []
    var remoteRoutines: [SavedRoutine] = []
    var deletedSessionIDs: [String] = []
    var deletedRoutineIDs: [UUID] = []
    var uploadedRecordSets: [[PersonalRecord]] = []
    var uploadError: Error?
    var loseNextUploadResponse = false
    var loseDeleteResponses = 0
    var loseWorkoutWipeResponses = 0
    var workoutWipeCalls = 0
    var accountDeletionError: Error?
    var manualRevocationRequired = false
    var accountDeletionCalls = 0
    var guestDeletionCalls = 0

    @MainActor
    override func deleteAccount(allowManualAppleRevocation: Bool = false) async throws -> Bool {
        accountDeletionCalls += 1
        if let accountDeletionError { throw accountDeletionError }
        profile = nil
        return manualRevocationRequired
    }

    override func deleteFuelBuddyGuestAccountIfPresent() async throws {
        guestDeletionCalls += 1
    }

    override var currentUser: UserProfile? { profile }
    override var isAuthenticated: Bool { profile != nil }
    override func restoreSessionIfNeeded() async {}
    override func signOut() async { profile = nil }
    override func signInWithGoogle() async throws -> UserProfile {
        if let googleSignInError { throw googleSignInError }
        return try XCTUnwrap(profile)
    }
    override func pullSessions() async throws -> [WorkoutSession] {
        if offline { throw URLError(.notConnectedToInternet) }
        return remoteSessions
    }
    override func pullRoutines() async throws -> [SavedRoutine] {
        if offline { throw URLError(.notConnectedToInternet) }
        return remoteRoutines
    }
    override func deleteCloudSession(_ cloudID: String) async throws {
        if offline { throw URLError(.notConnectedToInternet) }
        deletedSessionIDs.append(cloudID)
        remoteSessions.removeAll { $0.cloudID == cloudID }
        if loseDeleteResponses > 0 {
            loseDeleteResponses -= 1
            throw URLError(.networkConnectionLost)
        }
    }
    override func deleteCloudRoutine(_ id: UUID) async throws {
        if offline { throw URLError(.notConnectedToInternet) }
        deletedRoutineIDs.append(id)
        remoteRoutines.removeAll { $0.id == id }
    }
    override func backup(session local: WorkoutSession, records: [PersonalRecord]) async throws -> String {
        if let uploadError { throw uploadError }
        if offline { throw URLError(.notConnectedToInternet) }
        let id = local.cloudID ?? local.id.uuidString.lowercased()
        remoteSessions.removeAll { $0.cloudID == id }
        var remote = local
        remote.cloudID = id
        remote.syncState = .synced
        remoteSessions.append(remote)
        if loseNextUploadResponse {
            loseNextUploadResponse = false
            throw URLError(.networkConnectionLost)
        }
        return id
    }
    override func backup(routine: SavedRoutine) async throws {
        if offline { throw URLError(.notConnectedToInternet) }
        remoteRoutines.removeAll { $0.id == routine.id }
        remoteRoutines.append(routine)
    }
    override func replacePersonalRecords(_ records: [PersonalRecord]) async throws {
        if offline { throw URLError(.notConnectedToInternet) }
        uploadedRecordSets.append(records)
    }
    override func deleteWorkoutData() async throws {
        if offline { throw URLError(.notConnectedToInternet) }
        workoutWipeCalls += 1
        remoteSessions = []
        remoteRoutines = []
        uploadedRecordSets.append([])
        if loseWorkoutWipeResponses > 0 {
            loseWorkoutWipeResponses -= 1
            throw URLError(.networkConnectionLost)
        }
    }
}

@MainActor
final class ReleaseReadinessTests: XCTestCase {
    func testCancelledAppleDeletionPreservesAccountWorkoutsAndGuest() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cloud = OfflineCloud()
        cloud.profile = UserProfile(id: "apple-account", email: "apple@example.com", fullName: "Apple")
        cloud.accountDeletionError = CancellationError()
        let session = WorkoutSession(createdAt: Date(), split: "Strength", exercises: [LoggedExercise(name: "Push Ups", bodyweight: true, timed: false, sets: [LoggedSet(reps: 10)])], syncState: .synced)
        cloud.remoteSessions = [session]
        let store = LocalStore(directory: folder)
        try await store.save(AppSnapshot(sessions: [session]), ownerID: "apple-account")
        let app = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await app.boot()
        let deleted = await app.deleteAccount()
        XCTAssertFalse(deleted)
        XCTAssertEqual(app.user?.id, "apple-account")
        XCTAssertEqual(app.sessions.map(\.id), [session.id])
        XCTAssertEqual(cloud.guestDeletionCalls, 0)
        XCTAssertFalse(app.needsAppleRevocationFallback)
    }

    func testManualRevocationReminderSurvivesDeletionAndRelaunch() async throws {
        let key = "setzo-apple-manual-revocation"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cloud = OfflineCloud()
        cloud.profile = UserProfile(id: "apple-account", email: "apple@example.com", fullName: "Apple")
        cloud.accountDeletionError = SupabaseError.appleRevocationUnconfigured
        let store = LocalStore(directory: folder)
        let app = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await app.boot()
        let blocked = await app.deleteAccount()
        XCTAssertFalse(blocked)
        XCTAssertTrue(app.needsAppleRevocationFallback)
        cloud.accountDeletionError = nil
        cloud.manualRevocationRequired = true
        let deleted = await app.deleteAccount(allowManualAppleRevocation: true)
        XCTAssertTrue(deleted)
        XCTAssertTrue(app.showAppleRevocationInstructions)
        XCTAssertEqual(cloud.guestDeletionCalls, 1)
        let relaunched = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        XCTAssertTrue(relaunched.showAppleRevocationInstructions)
        relaunched.showAppleRevocationInstructions = false
        XCTAssertFalse(AppState(localStore: store, supabase: cloud, allowDebugSeeds: false).showAppleRevocationInstructions)
    }

    func testUnfinishedWorkoutRestoresAsDraftUntilExplicitSave() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let app = AppState(localStore: store, supabase: OfflineCloud(), allowDebugSeeds: false)
        await app.boot()
        app.startFreeWorkout()
        app.addExercise(name: "Push Ups")
        let exerciseID = app.todayExercises[0].id
        let setID = app.todayExercises[0].sets[0].id
        app.updateSet(exerciseID: exerciseID, setID: setID, reps: "12")
        app.toggleDone(exerciseID: exerciseID, setID: setID)
        app.updateWorkoutNote("Not saved yet")
        // Account transitions drain the queued disk writes and reload the draft.
        await app.signOut()
        let draftSnapshot = try await store.load()
        XCTAssertTrue(draftSnapshot.sessions.isEmpty)
        XCTAssertEqual(draftSnapshot.draft?.exercises.first?.sets.first?.done, true)

        let relaunched = AppState(localStore: store, supabase: OfflineCloud(), allowDebugSeeds: false)
        await relaunched.boot()
        XCTAssertTrue(relaunched.sessions.isEmpty)
        XCTAssertEqual(relaunched.stats.sets, 0)
        XCTAssertEqual(relaunched.stats.streak, 0)
        XCTAssertTrue(relaunched.personalRecords.isEmpty)
        XCTAssertEqual(relaunched.validCompletedSetCount, 1)

        await relaunched.finishWorkout(note: relaunched.workoutNote)
        await relaunched.finishWorkout(note: "Duplicate tap")
        let saved = try await store.load()
        XCTAssertEqual(saved.sessions.count, 1)
        XCTAssertNil(saved.draft)
        XCTAssertEqual(saved.sessions.first?.exercises.first?.sets.first?.reps, 12)
    }

    func testColdLaunchPreservesNewerLockScreenSetEdits() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let app = AppState(localStore: store, supabase: OfflineCloud(), allowDebugSeeds: false)
        await app.boot()
        app.startFreeWorkout()
        app.addExercise(name: "Push Ups")
        await app.signOut()
        // The disk draft is incomplete; the lock-screen intent completes it.
        await LiveWorkoutEngine.shared.mutate { state in
            var edited = state
            edited.exercises[0].sets[0].reps = "15"
            edited.exercises[0].sets[0].done = true
            return edited
        }
        let relaunched = AppState(localStore: store, supabase: OfflineCloud(), allowDebugSeeds: false)
        await relaunched.boot()
        XCTAssertEqual(relaunched.todayExercises.first?.sets.first?.reps, "15")
        XCTAssertEqual(relaunched.validCompletedSetCount, 1)
        await relaunched.finishWorkout(note: "From the lock screen")
        let saved = try await store.load()
        XCTAssertEqual(saved.sessions.first?.exercises.first?.sets.first?.reps, 15)
        LiveWorkoutEngine.shared.end()
        await LiveWorkoutEngine.shared.waitForPendingOperations()
    }

    func testDiscardingStartedWorkoutNeverCreatesHistory() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let app = AppState(localStore: store, supabase: OfflineCloud(), allowDebugSeeds: false)
        await app.boot()
        app.startFreeWorkout()
        app.addExercise(name: "Push Ups")
        app.discardWorkout()
        await app.signOut()
        let saved = try await store.load()
        XCTAssertTrue(saved.sessions.isEmpty)
        XCTAssertNil(saved.draft)
    }

    func testEmptyLocalAndCloudSessionsStayOutOfHistoryAndCanRecoverOnRetry() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let cloud = OfflineCloud()
        cloud.profile = UserProfile(id: "account-a", email: "a@example.com", fullName: "A")
        let id = UUID()
        let empty = WorkoutSession(id: id, cloudID: id.uuidString.lowercased(),
            createdAt: Date(), split: "PPL", exercises: [], syncState: .synced)
        var invalid = empty
        invalid.id = UUID()
        invalid.cloudID = invalid.id.uuidString.lowercased()
        invalid.exercises = [LoggedExercise(name: "Push Ups", bodyweight: true, timed: false,
            sets: [LoggedSet(weight: nil, reps: 0)])]
        let runID = UUID()
        let run = WorkoutSession(id: runID, cloudID: runID.uuidString.lowercased(),
            createdAt: Date().addingTimeInterval(-86_400), split: "Walk", exercises: [], syncState: .synced,
            activity: CardioActivity(kind: .walk, duration: 600, distance: 0, route: []))
        cloud.remoteSessions = [empty, invalid, run]
        try await store.save(AppSnapshot(sessions: [empty, invalid, run]), ownerID: "account-a")
        let app = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await app.boot()
        XCTAssertEqual(app.sessions.map(\.id), [runID])
        XCTAssertEqual(app.stats.streak, 0)
        XCTAssertTrue(cloud.deletedSessionIDs.isEmpty, "Incomplete uploads must remain recoverable")

        var completed = empty
        completed.exercises = [LoggedExercise(name: "Push Ups", bodyweight: true, timed: false,
            sets: [LoggedSet(weight: nil, reps: 12)])]
        cloud.remoteSessions = [completed, run]
        await app.syncNow()
        await app.syncNow()
        XCTAssertEqual(Set(app.sessions.map(\.id)), Set([id, runID]))
        XCTAssertEqual(app.sessions.count, 2)
        XCTAssertEqual(app.stats.sets, 1)
    }

    func testEmptyRunCannotBeSaved() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = AppState(localStore: LocalStore(directory: folder), supabase: OfflineCloud(), allowDebugSeeds: false)
        await app.boot()
        let saved = await app.saveRun(CardioActivity(kind: .run, duration: 0, distance: 0, route: []))
        XCTAssertFalse(saved)
        XCTAssertTrue(app.sessions.isEmpty)
    }

    private func directory() throws -> URL {
        // Screenshot capture can leave this launch preference behind on a
        // reused simulator; it would replace the test's loaded account state.
        UserDefaults.standard.removeObject(forKey: "seedDemo")
        UserDefaults.standard.removeObject(forKey: "seedActive")
        let result = FileManager.default.temporaryDirectory
            .appendingPathComponent("SetzoReleaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    func testRetryBackoffRemainsAvailableAfterFourthFailure() {
        XCTAssertEqual((0..<8).map { AppState.syncRetryDelay(attempt: $0) }, [5, 15, 45, 120, 120, 120, 120, 120])
        XCTAssertEqual(AppState.syncRetryDelay(attempt: Int.max), 120)
    }

    func testForegroundRetriesOfflineDeletionWithoutRelaunch() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let cloud = OfflineCloud()
        cloud.profile = UserProfile(id: "account-a", email: "a@example.com", fullName: "A")
        let id = UUID()
        let session = WorkoutSession(id: id, cloudID: id.uuidString.lowercased(), createdAt: Date(), split: "Strength", exercises: [LoggedExercise(name: "Push Ups", bodyweight: true, timed: false, sets: [LoggedSet(reps: 10)])], syncState: .synced)
        cloud.remoteSessions = [session]
        try await store.save(AppSnapshot(sessions: [session]), ownerID: "account-a")
        let app = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await app.boot()
        cloud.offline = true
        await app.deleteSession(id)
        cloud.offline = false
        await app.resumeForegroundSync()
        XCTAssertTrue(cloud.remoteSessions.isEmpty)
        XCTAssertTrue(cloud.deletedSessionIDs.contains(id.uuidString.lowercased()))
    }

    func testTransientSaveCanBeRetriedWithoutLosingPendingChanges() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let app = AppState(localStore: store, supabase: OfflineCloud(), allowDebugSeeds: false)
        await app.boot()
        // Replace the directory with a file to reproduce a temporary I/O failure.
        try FileManager.default.removeItem(at: folder)
        try Data().write(to: folder)
        app.setWater(index: 2)
        for _ in 0..<100 {
            if app.storageError != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(app.storageError)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await app.retryStorage()
        XCTAssertNil(app.storageError)
        let snapshot = try await store.load()
        XCTAssertEqual(snapshot.waterByDay[Date().dayKey], 3)
    }

    func testRetryCannotOverwriteFutureSnapshot() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = Data(#"{"schemaVersion":999}"#.utf8)
        let file = folder.appendingPathComponent("store.json")
        try data.write(to: file)
        let app = AppState(localStore: LocalStore(directory: folder), supabase: OfflineCloud(), allowDebugSeeds: false)
        await app.boot()
        await app.retryStorage()
        XCTAssertNotNil(app.storageError)
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testRejectedSessionEditReturnsFailure() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = WorkoutSession(createdAt: Date(), split: "Strength", note: "Keep me", exercises: [LoggedExercise(name: "Push Ups", bodyweight: true, timed: false, sets: [LoggedSet(reps: 10)])], syncState: .localOnly)
        let store = LocalStore(directory: folder)
        try await store.save(AppSnapshot(sessions: [session]))
        let app = AppState(localStore: store, supabase: OfflineCloud(), allowDebugSeeds: false)
        await app.boot()
        let accepted = await app.updateSession(id: session.id, exercises: [], note: "")
        XCTAssertFalse(accepted)
        XCTAssertEqual(app.sessions.first?.note, "Keep me")
    }

    func testBulkWorkoutDeletionStaysPendingAcrossOfflineRelaunchAndLostResponse() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let cloud = OfflineCloud()
        cloud.profile = UserProfile(id: "account-a", email: "a@example.com", fullName: "A")
        let session = WorkoutSession(createdAt: Date(), split: "Strength", exercises: [LoggedExercise(name: "Push Ups", bodyweight: true, timed: false, sets: [LoggedSet(reps: 10)])], syncState: .synced)
        let routine = SavedRoutine(name: "Leg Day", exercises: [])
        cloud.remoteSessions = [session]
        cloud.remoteRoutines = [routine]
        try await store.save(AppSnapshot(sessions: [session], routines: [routine]), ownerID: "account-a")
        cloud.offline = true
        let app = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await app.boot()
        let deleted = await app.deleteWorkoutData()
        XCTAssertTrue(deleted)
        XCTAssertTrue(app.sessions.isEmpty)
        XCTAssertTrue(app.routines.isEmpty)
        let pending = try await store.load(ownerID: "account-a")
        XCTAssertTrue(pending.pendingWorkoutWipe)

        cloud.offline = false
        cloud.loseWorkoutWipeResponses = 1
        let relaunched = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await relaunched.boot()
        XCTAssertTrue(relaunched.sessions.isEmpty)
        XCTAssertTrue(relaunched.routines.isEmpty)
        let stillPending = try await store.load(ownerID: "account-a")
        XCTAssertTrue(stillPending.pendingWorkoutWipe)
        await relaunched.syncNow()
        XCTAssertEqual(cloud.workoutWipeCalls, 2)
        XCTAssertTrue(cloud.remoteSessions.isEmpty)
        XCTAssertTrue(cloud.remoteRoutines.isEmpty)
        let settled = try await store.load(ownerID: "account-a")
        XCTAssertFalse(settled.pendingWorkoutWipe)
    }

    func testOfflineSessionDeletionSurvivesRelaunchAndPull() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let cloud = OfflineCloud()
        cloud.profile = UserProfile(id: "account-a", email: "a@example.com", fullName: "A")
        let id = UUID()
        let saved = WorkoutSession(id: id, cloudID: id.uuidString.lowercased(), userID: "account-a",
            createdAt: Date(), split: "Strength", exercises: [LoggedExercise(name: "Push Ups", bodyweight: true, timed: false, sets: [LoggedSet(reps: 10)])], syncState: .synced)
        cloud.remoteSessions = [saved]
        try await store.save(AppSnapshot(sessions: [saved]), ownerID: "account-a")
        cloud.offline = true
        let first = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await first.boot()
        XCTAssertEqual(first.sessions.map(\.id), [id], "boot: \(first.sessions), user: \(String(describing: first.user)), storage: \(String(describing: first.storageError))")
        await first.deleteSession(id)
        XCTAssertTrue(first.sessions.isEmpty)
        let pending = try await store.load(ownerID: "account-a")
        XCTAssertTrue(pending.pendingCloudSessionDeletions.contains(id.uuidString.lowercased()))
        XCTAssertTrue(pending.deletedCloudSessionIDs.contains(id.uuidString.lowercased()))

        // Recovery must never bring back the pre-delete backup.
        let primary = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("store-") && $0.pathExtension == "json" }!
        try Data("{broken".utf8).write(to: primary)

        cloud.offline = false
        let relaunched = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await relaunched.boot()
        XCTAssertTrue(relaunched.sessions.isEmpty)
        XCTAssertTrue(cloud.remoteSessions.isEmpty)
        XCTAssertTrue(cloud.deletedSessionIDs.contains(id.uuidString.lowercased()))
        XCTAssertEqual(cloud.uploadedRecordSets.last?.count, 0)
        let settled = try await store.load(ownerID: "account-a")
        XCTAssertTrue(settled.pendingCloudSessionDeletions.isEmpty)
        XCTAssertTrue(settled.deletedCloudSessionIDs.contains(id.uuidString.lowercased()))
        await relaunched.syncNow()
        XCTAssertTrue(relaunched.sessions.isEmpty)
    }

    func testBackupFailureShowsFriendlyStatusAndRetryClearsIt() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let cloud = OfflineCloud()
        cloud.profile = UserProfile(id: "account-a", email: "a@example.com", fullName: "A")
        cloud.uploadError = SupabaseError.requestFailed("All object keys must match")
        let pending = WorkoutSession(createdAt: Date(), split: "Strength",
            exercises: [LoggedExercise(name: "Push Ups", bodyweight: true, timed: false,
                sets: [LoggedSet(reps: 10)])], syncState: .pending)
        try await store.save(AppSnapshot(sessions: [pending]), ownerID: "account-a")
        let app = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await app.boot()
        XCTAssertEqual(app.sessions.first?.syncState, .failed)
        XCTAssertEqual(app.syncMessage, "Saved on this device. Cloud backup pending. We'll retry automatically.")
        let saved = try await store.load(ownerID: "account-a")
        XCTAssertEqual(saved.sessions.first?.id, pending.id)
        cloud.uploadError = nil
        await app.syncPending()
        XCTAssertEqual(app.sessions.first?.syncState, .synced)
        XCTAssertEqual(app.syncMessage, "Synced with Supabase")
        XCTAssertEqual(cloud.remoteSessions.count, 1)
    }

    func testLostUploadResponseAndRepeatedDeleteDoNotDuplicateOrResurrect() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let cloud = OfflineCloud()
        cloud.profile = UserProfile(id: "account-a", email: "a@example.com", fullName: "A")
        let id = UUID()
        let pending = WorkoutSession(id: id, userID: "account-a", createdAt: Date(),
            split: "Run", exercises: [], syncState: .pending,
            activity: CardioActivity(kind: .run, duration: 600, distance: 2000, route: []))
        try await store.save(AppSnapshot(sessions: [pending]), ownerID: "account-a")
        cloud.loseNextUploadResponse = true
        let app = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await app.boot()
        XCTAssertEqual(cloud.remoteSessions.count, 1)
        await app.syncNow()
        XCTAssertEqual(cloud.remoteSessions.count, 1)
        XCTAssertEqual(app.sessions.count, 1)
        cloud.loseDeleteResponses = 2
        await app.deleteSession(id)
        XCTAssertTrue(app.sessions.isEmpty)
        let afterLostResponse = try await store.load(ownerID: "account-a")
        XCTAssertTrue(afterLostResponse.pendingCloudSessionDeletions.contains(id.uuidString.lowercased()))
        await app.syncNow()
        XCTAssertTrue(cloud.remoteSessions.isEmpty)
        XCTAssertTrue(app.sessions.isEmpty)
        let settled = try await store.load(ownerID: "account-a")
        XCTAssertTrue(settled.pendingCloudSessionDeletions.isEmpty)
    }

    func testRoutineTombstoneIsAccountScopedAndRetried() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let routine = SavedRoutine(name: "Leg Day", exercises: [ExerciseTemplate(name: "Squat", sets: 3, reps: "5", tip: "")])
        let other = SavedRoutine(name: "Pull Day", exercises: [ExerciseTemplate(name: "Row", sets: 3, reps: "8", tip: "")])
        try await store.save(AppSnapshot(routines: [routine]), ownerID: "account-a")
        try await store.save(AppSnapshot(routines: [other]), ownerID: "account-b")
        let cloud = OfflineCloud()
        cloud.profile = UserProfile(id: "account-a", email: "a@example.com", fullName: "A")
        cloud.remoteRoutines = [routine]
        cloud.offline = true
        let first = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await first.boot()
        await first.deleteRoutine(routine.id)
        await first.signOut() // waits for the queued account-scoped save
        let pending = try await store.load(ownerID: "account-a")
        XCTAssertTrue(pending.deletedRoutineIDs.contains(routine.id))

        cloud.profile = UserProfile(id: "account-b", email: "b@example.com", fullName: "B")
        cloud.offline = false
        cloud.remoteRoutines = [other]
        let switched = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await switched.boot()
        XCTAssertEqual(switched.routines.map(\.name), ["Pull Day"])
        XCTAssertFalse(cloud.deletedRoutineIDs.contains(routine.id))

        cloud.profile = UserProfile(id: "account-a", email: "a@example.com", fullName: "A")
        cloud.remoteRoutines = [routine]
        let returned = AppState(localStore: store, supabase: cloud, allowDebugSeeds: false)
        await returned.boot()
        XCTAssertTrue(returned.routines.isEmpty)
        XCTAssertTrue(cloud.deletedRoutineIDs.contains(routine.id))
    }

    func testCorruptSnapshotRecoversPreviousSaveAndPreservesDamagedFile() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let previous = AppSnapshot(sessions: [WorkoutSession(createdAt: Date(), split: "Previous", exercises: [])])
        try await store.save(previous)
        try await store.save(AppSnapshot(sessions: [WorkoutSession(createdAt: Date(), split: "Latest", exercises: [])]))
        try Data("{broken".utf8).write(to: folder.appendingPathComponent("store.json"))
        let recovered = try await store.load()
        XCTAssertEqual(recovered.sessions.first?.split, "Previous")
        let didRecover = await store.didRecoverFromBackup
        XCTAssertTrue(didRecover)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.contains("damaged-") })
    }

    func testFutureVersionBlocksLoadAndOverwrite() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        let url = folder.appendingPathComponent("store.json")
        let future = Data(#"{"schemaVersion":999,"sessions":[]}"#.utf8)
        try future.write(to: url)
        do { _ = try await store.load(); XCTFail("Future snapshot must be rejected") }
        catch LocalStore.StoreError.futureVersion {}
        do { try await store.save(AppSnapshot()); XCTFail("Future snapshot must not be replaced") }
        catch LocalStore.StoreError.futureVersion {}
        XCTAssertEqual(try Data(contentsOf: url), future)
    }

    func testMissingFieldsAndUnknownFieldsDecodeWithoutLosingSessions() throws {
        let json = Data(#"{"sessions":[],"newerOptionalField":"ignored"}"#.utf8)
        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: json)
        XCTAssertTrue(snapshot.sessions.isEmpty)
        XCTAssertTrue(snapshot.pendingCloudSessionDeletions.isEmpty)
        XCTAssertEqual(snapshot.schemaVersion, AppSnapshot.currentSchemaVersion)

        let historical = Data(#"{"sessions":[{"createdAt":"2026-01-01T00:00:00Z","split":"PPL","exercises":[{"name":"Squat","sets":[{"reps":5}]}]}]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(AppSnapshot.self, from: historical)
        XCTAssertEqual(migrated.sessions.first?.split, "PPL")
        XCTAssertEqual(migrated.sessions.first?.exercises.first?.sets.first?.reps, 5)
        XCTAssertEqual(migrated.sessions.first?.syncState, .pending)
    }

    func testInterruptedAtomicReplacementCanRecoverFromBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(directory: folder)
        try await store.save(AppSnapshot(sessions: [WorkoutSession(createdAt: Date(), split: "Before", exercises: [])]))
        try await store.save(AppSnapshot(sessions: [WorkoutSession(createdAt: Date(), split: "After", exercises: [])]))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("store.json"))
        let recovered = try await store.load()
        XCTAssertEqual(recovered.sessions.first?.split, "Before")
    }

    func testExtremeAndMalformedNumericEntriesNeverConvertToInt() {
        currentWeightUnit = .kg
        currentBodyWeight = 70
        for value in ["999999999999999999999999", "1e309", "-12", "2,3,4", "abc", "1441"] {
            XCTAssertNil(manualCardio(kind: .run, minutes: value, distance: "5"), value)
        }
        XCTAssertNil(manualCardio(kind: .run, minutes: "30", distance: "1e309"))
        XCTAssertNil(manualCardio(kind: .run, minutes: "30", distance: "999999999999999999"))
        XCTAssertNil(manualCardio(kind: .run, minutes: "30", distance: "5", elevation: "999999999999999999"))
        XCTAssertNil(estimateCalories(kind: .run, durationSeconds: Int.max, distanceMetres: .infinity, elevationGainMetres: Int.max, bodyWeightKg: .infinity))
        XCTAssertNil(boundedInteger(Double.greatestFiniteMagnitude, in: 1...50_000))
        XCTAssertEqual(manualCardio(kind: .run, minutes: "30,5", distance: "5,5")?.duration, 1830)
        XCTAssertEqual(manualCardio(kind: .run, minutes: "30,5", distance: "5,5")?.distance, 5500)
        XCTAssertEqual(manualCardio(kind: .run, minutes: ",5", distance: ".5")?.duration, 30)
        XCTAssertEqual(displayDurationToSeconds(Int.max, minutes: true), 0)
        XCTAssertNil(decimalEntry("NaN"))
        XCTAssertNil(decimalEntry("Infinity"))
        XCTAssertEqual(decimalEntry(".5"), 0.5)
        currentBodyWeight = 0
    }

    func testTimedSetAndBodyWeightBounds() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = AppState(localStore: LocalStore(directory: folder), supabase: OfflineCloud(), allowDebugSeeds: false)
        app.startFreeWorkout()
        app.addExercise(template: ExerciseTemplate(name: "Bike", sets: 1, reps: "", tip: "", timed: true, minutes: true))
        let exercise = app.todayExercises[0]
        let set = exercise.sets[0]
        app.updateSet(exerciseID: exercise.id, setID: set.id, reps: "999999999999999999")
        app.toggleDone(exerciseID: exercise.id, setID: set.id)
        XCTAssertFalse(app.todayExercises[0].sets[0].done)
        app.updateSet(exerciseID: exercise.id, setID: set.id, reps: "1,5")
        app.toggleDone(exerciseID: exercise.id, setID: set.id)
        XCTAssertTrue(app.todayExercises[0].sets[0].done)
        await app.finishWorkout(note: "")
        XCTAssertEqual(app.sessions.first?.exercises.first?.sets.first?.reps, 90)

        app.setBodyWeight(70)
        app.setBodyWeight(Double.greatestFiniteMagnitude)
        XCTAssertEqual(app.bodyWeight, 70)
        app.setBodyWeight(nil)
        XCTAssertNil(app.bodyWeight)
    }
}

final class HistoryCalendarTests: XCTestCase {
    private func calendar(firstWeekday: Int = 1, timeZone: String = "UTC") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.firstWeekday = firstWeekday
        result.timeZone = TimeZone(identifier: timeZone)!
        return result
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testLeapMonthAndFirstWeekdayAlignment() {
        let sunday = calendar()
        let february = HistoryCalendarMonth(containing: date(2024, 2, 15, calendar: sunday), calendar: sunday)
        XCTAssertEqual(february.days.count, 42)
        XCTAssertEqual(february.days.compactMap { $0 }.count, 29)
        XCTAssertNil(february.days[3])
        XCTAssertEqual(february.days[4], date(2024, 2, 1, calendar: sunday))
        let monday = calendar(firstWeekday: 2)
        let mondayMonth = HistoryCalendarMonth(containing: date(2024, 2, 15, calendar: monday), calendar: monday)
        XCTAssertEqual(mondayMonth.days[3], date(2024, 2, 1, calendar: monday))
    }

    func testSixWeekMonthKeepsLastDay() {
        let cal = calendar()
        let month = HistoryCalendarMonth(containing: date(2026, 8, 31, calendar: cal), calendar: cal)
        XCTAssertEqual(month.days[36], date(2026, 8, 31, calendar: cal))
        XCTAssertEqual(month.days.compactMap { $0 }.count, 31)
    }

    func testWorkoutFilteringUsesLocalDaysAcrossDaylightSavingAndIncludesAllSessions() {
        let cal = calendar(timeZone: "America/Los_Angeles")
        let start = date(2026, 3, 8, calendar: cal)
        let nextDay = date(2026, 3, 9, calendar: cal)
        XCTAssertEqual(nextDay.timeIntervalSince(start), 23 * 3600)
        let sessions = [start.addingTimeInterval(-1), start, nextDay.addingTimeInterval(-1), nextDay].map {
            WorkoutSession(createdAt: $0, exercises: [], syncState: .localOnly)
        }
        XCTAssertEqual(HistoryCalendarMonth.sessions(sessions, on: start, calendar: cal).map(\.id),
            [sessions[1].id, sessions[2].id])
        XCTAssertEqual(HistoryCalendarMonth.sessions(sessions, on: nil, calendar: cal).count, 4)
        let days = HistoryCalendarMonth(containing: start, calendar: cal).days.compactMap { $0 }
        XCTAssertEqual(Set(days).count, 31)
        XCTAssertTrue(days.allSatisfy { cal.component(.hour, from: $0) == 0 })
    }
}
