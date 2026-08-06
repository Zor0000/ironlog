import AppIntents

/// Interactive intents fired by the Live Activity buttons. They conform to
/// `LiveActivityIntent`, so iOS runs `perform()` in the app's process straight
/// from the Lock Screen — no Face ID, no app launch into the foreground.
///
/// Each intent funnels through `LiveWorkoutEngine.mutate` with a pure
/// `LiveWorkoutReducer` transform, keeping lock-screen behaviour identical to
/// the in-app flow.

struct LogSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log set"
    static var description = IntentDescription("Mark the current set done and start the rest timer.")

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveWorkoutEngine.shared.mutate { LiveWorkoutReducer.logCurrentSet($0) }
        return .result()
    }
}

struct UndoSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Undo set"

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveWorkoutEngine.shared.mutate { LiveWorkoutReducer.unlogCurrentSet($0) }
        return .result()
    }
}

struct NextExerciseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next exercise"

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveWorkoutEngine.shared.mutate { LiveWorkoutReducer.nextExercise($0) }
        return .result()
    }
}

struct PreviousExerciseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous exercise"

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveWorkoutEngine.shared.mutate { LiveWorkoutReducer.previousExercise($0) }
        return .result()
    }
}

struct IncreaseWeightIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add weight"

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveWorkoutEngine.shared.mutate { LiveWorkoutReducer.adjustWeight($0, by: 1) }
        return .result()
    }
}

struct DecreaseWeightIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Remove weight"

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveWorkoutEngine.shared.mutate { LiveWorkoutReducer.adjustWeight($0, by: -1) }
        return .result()
    }
}

struct IncreaseRepsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add rep"

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveWorkoutEngine.shared.mutate { LiveWorkoutReducer.adjustReps($0, by: 1) }
        return .result()
    }
}

struct DecreaseRepsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Remove rep"

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveWorkoutEngine.shared.mutate { LiveWorkoutReducer.adjustReps($0, by: -1) }
        return .result()
    }
}

// MARK: - Run controls

/// Lets the run intents reach `RunTracker` without this file — which the widget
/// extension also compiles — ever naming it. `RunTracker` is app-only and drags
/// in CoreLocation; instantiating a `CLLocationManager` inside a widget process
/// is not something to do for the sake of a type reference.
///
/// `AppState` installs these at launch. In the widget's own process they stay
/// nil, which is harmless: `LiveActivityIntent.perform()` always runs in the
/// app's process.
///
/// ponytail: a tap arriving while the app is not running is a no-op. In practice
/// the background-location mode keeps the app alive for the whole of a tracked
/// activity, so this only bites if iOS has already killed it — at which point
/// nothing is being measured anyway. Persist a pending command if that changes.
@MainActor
enum LiveRunControls {
    static var pause: (() -> Void)?
    static var resume: (() -> Void)?
    static var finish: (() -> Void)?
}

struct PauseRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause"
    static var description = IntentDescription("Pause the activity without unlocking.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveRunControls.pause?()
        return .result()
    }
}

struct ResumeRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveRunControls.resume?()
        return .result()
    }
}

struct FinishRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Finish"
    static var description = IntentDescription("Finish and save the activity.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveRunControls.finish?()
        return .result()
    }
}
