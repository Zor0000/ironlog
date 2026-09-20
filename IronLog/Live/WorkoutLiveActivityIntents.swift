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
