import XCTest

final class IronLogUITests: XCTestCase {
    private var app: XCUIApplication!

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
        XCTAssertTrue(app.staticTexts["Push Ups"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1 sets · Free Workout · local"].exists)
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

        // Tap the card → edit sheet → change reps → save → card updates.
        XCTAssertTrue(app.staticTexts["Push Ups"].waitForExistence(timeout: 4))
        app.staticTexts["Push Ups"].tap()
        XCTAssertTrue(app.staticTexts["Edit Session"].waitForExistence(timeout: 3))
        let editReps = app.textFields["edit-reps-input"].firstMatch
        editReps.doubleTap() // select-all, so typing replaces "12"
        editReps.typeText("15")
        app.buttons["save-session-edits-button"].tap()

        XCTAssertTrue(app.staticTexts["BW x 15"].waitForExistence(timeout: 4))
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
