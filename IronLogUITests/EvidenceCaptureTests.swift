import XCTest

/// Deterministic screenshot capture for PR evidence.
///
/// Every test here is one *scenario*: it drives the app through a fixed set of
/// states from a clean store and attaches a screenshot per state. The class is
/// skipped unless `EVIDENCE_CAPTURE=1` is in the test environment, so the
/// normal `xcodebuild test` run never pays for it; `scripts/capture_evidence.sh`
/// sets the variable, runs the scenarios across the device/Dynamic Type matrix
/// and exports the attachments as `<device>-<size>-<scenario>-<step>.png`.
///
/// Determinism comes from: `UITest_ResetStore` (clean state), the script's
/// status-bar override (9:41, full battery), fixed content-size categories,
/// `UITest_Seed` for any randomised feature, and screenshots only being taken
/// after `waitForExistence` on the element that marks the state.
///
/// Adding a scenario: write `func testScenario<Name>()`, call `snap("step")`
/// at each state worth showing, keep the step names stable — the script and PR
/// templates key off them.
final class EvidenceCaptureTests: XCTestCase {
    private var app: XCUIApplication!
    private var stepIndex = 0

    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            environment["EVIDENCE_CAPTURE"] == "1",
            "Evidence capture only runs via scripts/capture_evidence.sh"
        )
        continueAfterFailure = false
        stepIndex = 0
        app = XCUIApplication()
        var arguments = ["UITest_ResetStore", "UITest_Seed", environment["EVIDENCE_SEED"] ?? "7"]
        // Pin language, region and time zone so date headers and the keyboard
        // don't vary with the simulator's settings.
        arguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // Always pass a content size, so a simulator whose Dynamic Type was
        // changed by hand can't leak into a "default" capture.
        arguments += ["-UIPreferredContentSizeCategoryName", environment["EVIDENCE_CONTENT_SIZE"].flatMap { $0.isEmpty ? nil : $0 } ?? "UICTContentSizeCategoryL"]
        app.launchArguments = arguments
        app.launchEnvironment["TZ"] = "UTC"
        app.launch()
    }

    override func tearDown() {
        app?.terminate()
        super.tearDown()
    }

    /// Attach a screenshot named `<scenario>-<index>-<step>`; the zero-padded
    /// index keeps the exported files in capture order even past ten steps.
    private func snap(_ step: String, settle: TimeInterval = 0.6) {
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        dismissSystemAlerts()
        stepIndex += 1
        let scenario = name
            .replacingOccurrences(of: "-[EvidenceCaptureTests testScenario", with: "")
            .replacingOccurrences(of: "]", with: "")
            .lowercased()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = String(format: "%@-%02d-%@", scenario, stepIndex, step)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// System permission prompts (notifications for the rest timer, etc.)
    /// would otherwise land in a screenshot depending on simulator state.
    /// Decline them so captures don't depend on prior grants either.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var attempts = 0
        while springboard.alerts.firstMatch.exists, attempts < 3 {
            let alert = springboard.alerts.firstMatch
            for title in ["Don't Allow", "Not Now", "Cancel", "OK", "Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            attempts += 1
        }
    }

    private func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 6) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing \(element)")
    }

    // MARK: Scenarios

    /// Today tab → free workout → Add Exercise card in its initial state, with
    /// a muscle filter applied, and with the custom entry reached.
    func testScenarioAddExercise() {
        waitFor(app.buttons["Today"])
        app.buttons["Today"].tap()
        waitFor(app.buttons["start-free-workout-button"])
        app.buttons["start-free-workout-button"].tap()
        waitFor(app.textFields["exercise-template-search-field"])
        snap("initial")

        app.buttons["Chest exercises"].tap()
        waitFor(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'exercise-template-'")).firstMatch)
        snap("muscle-filter")

        // Bounded preview → dedicated browser for the rest of the catalog.
        if app.buttons["browse-all-exercises-button"].exists {
            app.buttons["browse-all-exercises-button"].tap()
            waitFor(app.buttons["close-exercise-browser-button"])
            snap("browse-all")
            app.buttons["close-exercise-browser-button"].tap()
            waitFor(app.buttons["add-exercise-mode-custom"])
        }

        let customField = app.textFields["new-exercise-name-field"]
        if app.buttons["add-exercise-mode-custom"].exists {
            app.buttons["add-exercise-mode-custom"].tap()
        } else {
            var swipes = 0
            while customField.exists, !customField.isHittable, swipes < 6 {
                app.swipeUp()
                swipes += 1
            }
        }
        waitFor(customField)
        snap("custom-entry")

        customField.tap()
        snap("custom-keyboard")
    }

    /// Exercise Finder: pick a muscle, run the search, land on a result, and
    /// try another.
    func testScenarioExerciseFinder() {
        waitFor(app.buttons["exercise-finder-entry-button"])
        app.buttons["exercise-finder-entry-button"].tap()
        waitFor(app.buttons["exercise-finder-muscle-shoulders"])
        app.buttons["exercise-finder-muscle-shoulders"].tap()
        snap("idle")

        app.buttons["find-best-exercise-button"].tap()
        snap("searching", settle: 0.35)

        waitFor(app.buttons["add-recommended-exercise-button"], 8)
        snap("result")

        if app.buttons["find-another-exercise-button"].exists {
            app.buttons["find-another-exercise-button"].tap()
            waitFor(app.buttons["add-recommended-exercise-button"], 8)
            snap("try-another", settle: 1.2)
        }

        app.swipeUp()
        snap("alternates")
    }

    /// The live log with a logged exercise and one completed set.
    func testScenarioWorkoutLog() {
        waitFor(app.buttons["Today"])
        app.buttons["Today"].tap()
        waitFor(app.buttons["start-free-workout-button"])
        app.buttons["start-free-workout-button"].tap()

        let customField = app.textFields["new-exercise-name-field"]
        if app.buttons["add-exercise-mode-custom"].exists {
            app.buttons["add-exercise-mode-custom"].tap()
        } else {
            var swipes = 0
            while customField.exists, !customField.isHittable, swipes < 6 {
                app.swipeUp()
                swipes += 1
            }
        }
        waitFor(customField)
        customField.tap()
        customField.typeText("Push Ups")
        app.buttons["confirm-add-exercise-button"].tap()

        let reps = app.textFields["set-reps-input"].firstMatch
        waitFor(reps)
        reps.tap()
        reps.typeText("12")
        app.buttons["set-done-button"].firstMatch.tap()
        snap("set-logged")
    }
}
