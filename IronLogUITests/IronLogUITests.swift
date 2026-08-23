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

    /// The system permission alert can surface in either the app or SpringBoard
    /// depending on iOS version. Prefer a durable grant over "Allow Once".
    private func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard let app else { return }
        for host in [app, springboard] {
            let alert = host.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { continue }
            let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Allow While Using")).firstMatch
            if allow.exists { allow.tap(); return }
            let once = alert.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Allow Once")).firstMatch
            if once.exists { once.tap(); return }
        }
    }

    private func openRunTab() {
        XCTAssertTrue(app.buttons["Run"].waitForExistence(timeout: 6))
        app.buttons["Run"].tap()
        XCTAssertTrue(app.buttons["run-start-button"].waitForExistence(timeout: 4))
    }

    func testRunTabSelectsRunOrWalkAndDiscardsCleanly() {
        openRunTab()

        // Both kinds are offered, and the start button follows the selection.
        XCTAssertTrue(app.buttons["run-kind-run"].exists)
        XCTAssertTrue(app.buttons["run-kind-walk"].exists)
        XCTAssertEqual(app.buttons["run-start-button"].label, "Start Run")
        app.buttons["run-kind-walk"].tap()
        XCTAssertEqual(app.buttons["run-start-button"].label, "Start Walk")
        app.buttons["run-kind-run"].tap()

        app.buttons["run-start-button"].tap()
        allowLocationIfAsked()

        // The clock runs and advances on its own.
        let elapsed = app.staticTexts["run-elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 6))
        let first = elapsed.label
        sleep(4)
        XCTAssertNotEqual(elapsed.label, first)
        XCTAssertFalse(app.staticTexts["run-status"].label.isEmpty)

        // Pause freezes the session; resume brings it back.
        app.buttons["run-pause-button"].tap()
        XCTAssertEqual(app.staticTexts["run-status"].label, "Paused")
        app.buttons["run-pause-button"].tap()
        XCTAssertNotEqual(app.staticTexts["run-status"].label, "Paused")

        // Discard asks first, and "Keep Going" genuinely keeps going.
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.staticTexts["Discard run?"].waitForExistence(timeout: 3))
        app.buttons["Keep Going"].tap()
        XCTAssertTrue(app.staticTexts["run-elapsed"].waitForExistence(timeout: 3))

        app.buttons["Discard"].tap()
        app.buttons["Discard Run"].tap()
        XCTAssertTrue(app.buttons["run-start-button"].waitForExistence(timeout: 4))
    }

    func testIndoorRunSavesTypedDistanceIntoHistory() {
        openRunTab()
        app.buttons["run-start-button"].tap()
        allowLocationIfAsked()
        XCTAssertTrue(app.staticTexts["run-elapsed"].waitForExistence(timeout: 6))

        // With no GPS distance arriving (a treadmill, a basement), the tracker
        // eventually offers the typed-distance field instead of a dead 0.00.
        let manualField = app.textFields["run-manual-distance"]
        XCTAssertTrue(manualField.waitForExistence(timeout: 35))
        manualField.tap()
        manualField.typeText("5")
        app.buttons["Done"].tap()

        app.buttons["run-finish-button"].tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 4))
        // The collapsed card leads with "5.00 km" and is labelled "Run" in its
        // accessibility description (the kind is not visible text otherwise).
        let subtitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "5.00 km")).firstMatch
        XCTAssertTrue(subtitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["history-card-toggle"].firstMatch.label.contains("Run"))
    }

    func testManualLogSheetSavesAWalk() {
        openRunTab()

        // Pick Walk before opening the sheet — the logger's segmented picker
        // would be ambiguous to tap ("Walk" also matches the tile behind it).
        app.buttons["run-kind-walk"].tap()

        app.buttons["run-manual-log-button"].tap()
        XCTAssertTrue(app.staticTexts["Log It Manually"].waitForExistence(timeout: 4))

        let minutes = app.textFields.firstMatch
        minutes.tap()
        minutes.typeText("30")
        let distance = app.textFields.element(boundBy: 1)
        distance.tap()
        distance.typeText("3")

        // The button names the kind it will save — proof the picker agreed.
        XCTAssertEqual(app.buttons["save-manual-cardio-button"].label, "Save Walk")
        app.buttons["save-manual-cardio-button"].tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 4))
        let subtitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3.00 km")).firstMatch
        XCTAssertTrue(subtitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["history-card-toggle"].firstMatch.label.contains("Walk"))
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
