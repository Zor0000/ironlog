import XCTest

final class IronLogUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UITest_ResetStore"]
        app.launch()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 15))
    }

    private func dismissKeyboard() {
        if app.keyboards.count > 0 {
            for button in app.buttons.matching(identifier: "Done").allElementsBoundByIndex where button.isHittable {
                button.tap()
                return
            }
        }
    }

    private func tapVisible(_ element: XCUIElement) {
        dismissKeyboard()
        for _ in 0..<10 {
            if element.exists && element.isHittable { element.tap(); return }
            app.swipeUp()
        }
        XCTFail("Could not reach \(element)")
    }

    private func addCustomExercise() {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        app.buttons["Today"].tap()
        app.buttons["start-free-workout-button"].tap()
        let field = app.textFields["new-exercise-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Push Ups")
        tapVisible(app.buttons["confirm-add-exercise-button"])
    }

    func testExerciseRemovalAlwaysConfirmsAndCancelKeepsIt() {
        addCustomExercise()
        app.buttons["remove-exercise-button"].firstMatch.tap()
        XCTAssertTrue(app.alerts["Remove exercise?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Keep It"].tap()
        XCTAssertTrue(app.staticTexts["Push Ups"].exists)
        app.buttons["remove-exercise-button"].firstMatch.tap()
        app.alerts.buttons["Remove Exercise"].tap()
        XCTAssertTrue(app.textFields["new-exercise-name-field"].waitForExistence(timeout: 3))
    }

    func testSetRemovalIsVisibleAndIdentifiesTheSet() {
        addCustomExercise()
        XCTAssertFalse(app.buttons["remove-set-button"].firstMatch.isEnabled)
        tapVisible(app.buttons["Add Set"])
        XCTAssertEqual(app.buttons.matching(identifier: "remove-set-button").count, 2)
        tapVisible(app.buttons.matching(identifier: "remove-set-button").element(boundBy: 1))
        XCTAssertTrue(app.alerts["Remove set?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Set 2 of Push Ups")).firstMatch.exists)
        app.alerts.buttons["Keep It"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "remove-set-button").count, 2)
        tapVisible(app.buttons.matching(identifier: "remove-set-button").element(boundBy: 1))
        app.alerts.buttons["Remove Set"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "remove-set-button").count, 1)
    }

    func testFinishWarnsBeforeDroppingUnfinishedSets() {
        addCustomExercise()
        let reps = app.textFields["set-reps-input"].firstMatch
        reps.tap(); reps.typeText("12")
        dismissKeyboard()
        app.buttons["set-done-button"].firstMatch.tap()
        tapVisible(app.buttons["Add Set"])
        tapVisible(app.buttons["finish-workout-button"])
        XCTAssertTrue(app.alerts["Finish with unfinished sets?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Keep Logging"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "remove-set-button").count, 2)
        tapVisible(app.buttons["finish-workout-button"])
        app.alerts.buttons["Save Completed Sets"].tap()
        XCTAssertTrue(app.buttons["history-card-toggle"].firstMatch.waitForExistence(timeout: 4))
    }

    func testEditorKeepsInvalidAndUnsavedChangesOpen() {
        addCustomExercise()
        let reps = app.textFields["set-reps-input"].firstMatch
        reps.tap(); reps.typeText("12")
        dismissKeyboard()
        app.buttons["set-done-button"].firstMatch.tap()
        tapVisible(app.buttons["finish-workout-button"])
        XCTAssertTrue(app.buttons["edit-session-button"].firstMatch.waitForExistence(timeout: 4))
        app.buttons["edit-session-button"].firstMatch.tap()
        let edited = app.textFields["edit-reps-input"].firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 3))
        edited.doubleTap(); edited.typeText(XCUIKeyboardKey.delete.rawValue)
        dismissKeyboard()
        XCTAssertFalse(app.buttons["save-session-edits-button"].isEnabled)
        app.buttons["Close editor"].tap()
        XCTAssertTrue(app.alerts["Discard unsaved changes?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Keep Editing"].tap()
        XCTAssertTrue(app.textFields["edit-reps-input"].firstMatch.exists)
        app.buttons["Close editor"].tap()
        app.alerts.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.buttons["history-card-toggle"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["history-card-toggle"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["BW x 12"].exists)
    }

    func testRoutineReplacementAndDeletionRequireConfirmation() {
        addCustomExercise()
        tapVisible(app.buttons["save-routine-button"])
        let name = app.textFields["routine-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("My Routine")
        tapVisible(app.buttons["Save Routine"])
        tapVisible(app.buttons["save-routine-button"])
        XCTAssertTrue(app.textFields["routine-name-field"].waitForExistence(timeout: 3))
        app.textFields["routine-name-field"].tap()
        app.textFields["routine-name-field"].typeText("My Routine")
        XCTAssertTrue(app.buttons["Replace Routine"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        app.buttons["Workouts"].tap()
        let actions = app.buttons["Actions for My Routine"]
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        tapVisible(actions)
        app.buttons["Delete Routine"].tap()
        XCTAssertTrue(app.alerts["Delete routine?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Keep Routine"].tap()
        XCTAssertTrue(actions.exists)
    }

    func testTabNavigationKeepsCardioDraftAndDoesNotSwipeAway() {
        openRunTab()
        typeInto("run-minutes-field", "30")
        dismissKeyboard()
        app.swipeLeft()
        XCTAssertTrue(app.buttons["run-kind-run"].exists)
        app.buttons["Today"].tap()
        app.buttons["Run"].tap()
        XCTAssertEqual(app.textFields["run-minutes-field"].value as? String, "30")
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
        tapVisible(app.buttons["confirm-add-exercise-button"])

        let repsField = app.textFields["set-reps-input"].firstMatch
        XCTAssertTrue(repsField.waitForExistence(timeout: 3))
        repsField.tap()
        repsField.typeText("12")

        app.buttons["set-done-button"].firstMatch.tap()
        tapVisible(app.buttons["finish-workout-button"])

        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 4))
        // Collapsed card shows date + split only; expanding reveals exercises.
        XCTAssertTrue(app.staticTexts["1 set · Free Workout · local"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Push Ups"].exists)
        app.buttons["history-card-toggle"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Push Ups"].waitForExistence(timeout: 3))
    }

    func testSettingsOpensFromGearAndShowsAccountControls() {
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 6))
        app.buttons["settings-button"].tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Local — saved on this iPhone"].exists)
        XCTAssertTrue(app.buttons["delete-account-button"].exists)
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
        tapVisible(app.buttons["confirm-add-exercise-button"])
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
        tapVisible(app.buttons["confirm-add-exercise-button"])
        let repsField = app.textFields["set-reps-input"].firstMatch
        XCTAssertTrue(repsField.waitForExistence(timeout: 3))
        repsField.tap()
        repsField.typeText("12")
        app.buttons["set-done-button"].firstMatch.tap()
        tapVisible(app.buttons["finish-workout-button"])

        // Expand the card → exercises drop down → pencil opens the edit sheet →
        // change reps → save → expanded card updates.
        let cardToggle = app.buttons["history-card-toggle"].firstMatch
        XCTAssertTrue(cardToggle.waitForExistence(timeout: 4))
        cardToggle.tap()
        XCTAssertTrue(app.staticTexts["Push Ups"].waitForExistence(timeout: 3))
        app.buttons["edit-session-button"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Edit Session"].waitForExistence(timeout: 3))
        let editReps = app.textFields["edit-reps-input"].firstMatch
        editReps.doubleTap()
        editReps.typeText("15")
        tapVisible(app.buttons["save-session-edits-button"])

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
        dismissKeyboard()

        tapVisible(app.buttons["save-manual-cardio-button"])
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
        dismissKeyboard()

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
