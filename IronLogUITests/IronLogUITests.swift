import XCTest

final class IronLogUITests: XCTestCase {
    private var app: XCUIApplication!

    private func waitUntilStable(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var previousFrame: CGRect?
        var stableSamples = 0

        while Date() < deadline {
            if element.exists, element.isHittable {
                let frame = element.frame
                if frame == previousFrame {
                    stableSamples += 1
                    if stableSamples >= 2 { return true }
                } else {
                    stableSamples = 0
                    previousFrame = frame
                }
            } else {
                stableSamples = 0
                previousFrame = nil
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UITest_ResetStore"]
        app.launch()
    }

    func testFreeWorkoutCanAddExerciseCompleteSetAndSave() {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()

        let exerciseField = app.textFields["new-exercise-name-field"]
        XCTAssertTrue(exerciseField.waitForExistence(timeout: 3))
        exerciseField.tap()
        exerciseField.typeText("Push Ups")
        app.buttons["confirm-add-exercise-button"].tap()

        let repsField = app.textFields["set-reps-input"].firstMatch
        XCTAssertTrue(repsField.waitForExistence(timeout: 3))
        repsField.tap()
        repsField.typeText("12")

        app.buttons["set-done-button"].firstMatch.tap()
        app.buttons["finish-workout-button"].tap()

        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 4))
        // Collapsed card shows date + split only; expanding reveals exercises.
        XCTAssertTrue(app.staticTexts["1 set · Free Workout · local"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Push Ups"].exists)
        app.buttons["history-card-toggle"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Push Ups"].waitForExistence(timeout: 3))
    }

    func testExerciseAndSetDeletionUseTheRequestedConfirmationRules() {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()
        let exerciseField = app.textFields["new-exercise-name-field"]
        XCTAssertTrue(exerciseField.waitForExistence(timeout: 3))
        exerciseField.tap()
        exerciseField.typeText("Push Ups")
        app.buttons["confirm-add-exercise-button"].tap()

        // Exercise removal always asks, even before any set is filled in.
        let removeExercise = app.buttons["remove-exercise-button"].firstMatch
        XCTAssertTrue(waitUntilStable(removeExercise))
        removeExercise.tap()
        XCTAssertTrue(app.staticTexts["Remove exercise?"].waitForExistence(timeout: 2))
        app.buttons["Keep It"].tap()

        // A newly added empty set disappears directly.
        let addSet = app.buttons["Add Set"]
        XCTAssertTrue(waitUntilStable(addSet))
        addSet.tap()
        let repsFields = app.textFields.matching(identifier: "set-reps-input")
        XCTAssertTrue(repsFields.element(boundBy: 1).waitForExistence(timeout: 2))
        let removeSet = app.buttons.matching(identifier: "remove-set-button").element(boundBy: 1)
        XCTAssertTrue(waitUntilStable(removeSet))
        removeSet.tap()
        XCTAssertFalse(repsFields.element(boundBy: 1).waitForExistence(timeout: 1))
        XCTAssertFalse(app.staticTexts["Remove set?"].exists)

        // Once the set has content, the same action requires confirmation.
        addSet.tap()
        let secondReps = app.textFields.matching(identifier: "set-reps-input").element(boundBy: 1)
        secondReps.tap()
        secondReps.typeText("8")
        XCTAssertTrue(waitUntilStable(removeSet))
        removeSet.tap()
        XCTAssertTrue(app.staticTexts["Remove set?"].waitForExistence(timeout: 2))
    }

    func testCustomRemarkCanBeTypedForASet() {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()
        let exerciseField = app.textFields["new-exercise-name-field"]
        XCTAssertTrue(exerciseField.waitForExistence(timeout: 3))
        exerciseField.tap()
        exerciseField.typeText("Push Ups")
        app.buttons["confirm-add-exercise-button"].tap()

        app.buttons["set-type-button"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Add Custom Remark"].waitForExistence(timeout: 2))
        app.buttons["Add Custom Remark"].tap()
        let remarkField = app.textFields["e.g. Slow eccentric"]
        XCTAssertTrue(remarkField.waitForExistence(timeout: 2))
        remarkField.tap()
        remarkField.typeText("Pause at the bottom")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Pause at the bottom"].waitForExistence(timeout: 2))
    }

    func testRoutineDeletionIsVisibleAndRequiresConfirmation() {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()
        let exerciseField = app.textFields["new-exercise-name-field"]
        XCTAssertTrue(exerciseField.waitForExistence(timeout: 3))
        exerciseField.tap()
        exerciseField.typeText("Push Ups")
        app.buttons["confirm-add-exercise-button"].tap()

        let saveRoutine = app.buttons["save-routine-button"]
        XCTAssertTrue(saveRoutine.waitForExistence(timeout: 3))
        saveRoutine.tap()
        let routineName = app.textFields["e.g. Chris's Leg Day"]
        XCTAssertTrue(routineName.waitForExistence(timeout: 2))
        routineName.tap()
        routineName.typeText("Quick Push")
        app.buttons["Save"].tap()

        app.buttons["Discard workout"].tap()
        XCTAssertTrue(app.buttons["Discard Workout"].waitForExistence(timeout: 2))
        app.buttons["Discard Workout"].tap()

        let deleteRoutine = app.buttons["delete-routine-button"]
        XCTAssertTrue(deleteRoutine.waitForExistence(timeout: 3))
        deleteRoutine.tap()
        XCTAssertTrue(app.staticTexts["Delete routine?"].waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Quick Push"].exists)

        deleteRoutine.tap()
        app.buttons["Delete Routine"].tap()
        XCTAssertFalse(app.staticTexts["Quick Push"].waitForExistence(timeout: 1))
    }

    func testSettingsOpensFromGearAndShowsAccountControls() {
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 6))
        app.buttons["settings-button"].tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Local — saved on this iPhone"].exists)
        XCTAssertTrue(app.buttons["delete-workout-data-button"].exists)
        XCTAssertTrue(app.buttons["Pounds (lb)"].exists)

        // Unit toggle flips the log screen's weight field label.
        app.buttons["Pounds (lb)"].tap()
        app.buttons["Close settings"].tap()
        app.buttons["Today"].tap()
        app.buttons["start-free-workout-button"].tap()
        let exerciseField = app.textFields["new-exercise-name-field"]
        XCTAssertTrue(exerciseField.waitForExistence(timeout: 3))
        app.swipeUp()
        app.buttons["Weight + Reps"].tap()
        exerciseField.tap()
        exerciseField.typeText("Bench Press")
        app.buttons["confirm-add-exercise-button"].tap()
        XCTAssertTrue(app.staticTexts["LB"].waitForExistence(timeout: 3))
    }

    func testHistoryCardOpensEditSheetAndSavesChanges() {
        // Log a quick workout first.
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()
        let exerciseField = app.textFields["new-exercise-name-field"]
        XCTAssertTrue(exerciseField.waitForExistence(timeout: 3))
        exerciseField.tap()
        exerciseField.typeText("Push Ups")
        app.buttons["confirm-add-exercise-button"].tap()
        let repsField = app.textFields["set-reps-input"].firstMatch
        XCTAssertTrue(repsField.waitForExistence(timeout: 3))
        repsField.tap()
        repsField.typeText("12")
        app.buttons["set-done-button"].firstMatch.tap()
        app.buttons["finish-workout-button"].tap()

        // Expand the card → exercises drop down → pencil opens the edit sheet →
        // change reps → save → expanded card updates.
        let cardToggle = app.buttons["history-card-toggle"].firstMatch
        XCTAssertTrue(cardToggle.waitForExistence(timeout: 4))
        cardToggle.tap()
        XCTAssertTrue(app.staticTexts["Push Ups"].waitForExistence(timeout: 3))
        app.buttons["edit-session-button"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Edit Session"].waitForExistence(timeout: 3))
        let editReps = app.textFields["edit-reps-input"].firstMatch
        editReps.doubleTap() // select-all, so typing replaces "12"
        editReps.typeText("15")
        app.buttons["save-session-edits-button"].tap()

        XCTAssertTrue(app.staticTexts["BW x 15"].waitForExistence(timeout: 4))
    }

    // MARK: Run tab

    /// The Run tab is a manual logger: pick the kind, type time (required) and
    /// optionally distance/elevation, save into History.
    private func openRunTab() {
        XCTAssertTrue(app.buttons["Run"].waitForExistence(timeout: 6))
        app.buttons["Run"].tap()
        XCTAssertTrue(app.buttons["run-kind-run"].waitForExistence(timeout: 4))
    }

    private func typeInto(_ identifier: String, _ text: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(text)
    }

    func testRunTabSelectsRunOrWalkAndSavesManually() {
        openRunTab()

        // Both kinds are offered, and the save button follows the selection.
        XCTAssertTrue(app.buttons["run-kind-walk"].exists)
        XCTAssertEqual(app.buttons["save-manual-cardio-button"].label, "Save Run")
        app.buttons["run-kind-walk"].tap()
        XCTAssertEqual(app.buttons["save-manual-cardio-button"].label, "Save Walk")
        app.buttons["run-kind-run"].tap()

        typeInto("run-minutes-field", "30")
        typeInto("run-distance-field", "3")
        app.buttons["Done"].tap()

        app.buttons["save-manual-cardio-button"].tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 4))
        let subtitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3.00 km")).firstMatch
        XCTAssertTrue(subtitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["history-card-toggle"].firstMatch.label.contains("Run"))
    }

    func testTerrainChipsSelectAndClear() {
        openRunTab()

        let trail = app.buttons["run-terrain-trail"]
        XCTAssertTrue(trail.waitForExistence(timeout: 3))
        trail.tap()
        XCTAssertTrue(trail.isSelected)
        // Tapping the active chip clears it again — terrain is optional context.
        trail.tap()
        XCTAssertFalse(trail.isSelected)
    }

    /// The calorie estimate needs a body weight first; once set in Settings,
    /// the preview shows the ACSM figure for what is typed (5 km in 30 min at
    /// 70 kg ≈ 387 kcal).
    func testBodyWeightSettingDrivesTheCaloriePreview() {
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 6))
        app.buttons["settings-button"].tap()
        let weightField = app.textFields["body-weight-field"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 4))
        weightField.tap()
        weightField.typeText("70")
        app.buttons["Close settings"].tap()

        openRunTab()
        typeInto("run-minutes-field", "30")
        typeInto("run-distance-field", "5")
        app.buttons["Done"].tap()

        let estimate = app.staticTexts["run-calorie-estimate"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 3))
        XCTAssertTrue(estimate.label.contains("387"), "expected the ACSM estimate in '\(estimate.label)'")
    }

    func testSuggestedWorkoutWizardStartsWorkoutAndPreventsOverwrite() {
        XCTAssertTrue(app.staticTexts["Split Type"].waitForExistence(timeout: 6))
        app.buttons["PPL"].tap()
        app.buttons["Push"].tap()

        XCTAssertTrue(app.buttons["start-suggested-workout-button"].waitForExistence(timeout: 3))
        app.buttons["start-suggested-workout-button"].tap()

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Barbell Bench Press"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Seated DB Shoulder Press"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Overhead Tricep Extension"].waitForExistence(timeout: 3))

        app.buttons["Workouts"].tap()
        XCTAssertTrue(app.staticTexts["Workout in progress"].waitForExistence(timeout: 3))
        app.buttons["start-suggested-workout-button"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Barbell Bench Press"].waitForExistence(timeout: 3))
    }
}
