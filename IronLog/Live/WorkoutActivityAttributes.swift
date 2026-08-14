import Foundation
import ActivityKit

/// Drives the IronLog rest/log Live Activity on the Lock Screen and Dynamic
/// Island. The dynamic `ContentState` simply carries the shared
/// `LiveWorkoutState`, so the widget renders entirely from data the app (or a
/// lock-screen intent) pushes via `Activity.update`.
struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var workout: LiveWorkoutState
    }

    /// Weight unit label shown next to the stepper, fixed for the session.
    var weightUnit: String = "KG"
}

/// Drives the tracked run or walk Live Activity.
///
/// Unlike the lifting activity — which ships the whole `LiveWorkoutState` so the
/// Lock Screen can *edit* it — a run is measured by GPS in the app process and
/// the Lock Screen only ever renders it and issues commands. So the payload is
/// pre-formatted display strings: the widget target does not compile
/// `Models.swift`, and a render payload has no business owning `CardioKind` or
/// the unit helpers.
struct RunActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// The instant the elapsed clock reads zero from, i.e. `now - elapsed`.
        /// Lets the widget run a live counter via `Text(timerInterval:)` rather
        /// than the app pushing an update every second — ActivityKit throttles
        /// frequent updates, and a per-second push would spend that budget on
        /// the one number iOS can animate for free.
        var clockStart: Date
        /// Frozen elapsed text, shown while paused (no live counter then).
        var elapsedText: String
        var distanceText: String
        var paceText: String
        var isPaused: Bool
        var signalLost: Bool
    }

    /// Fixed for the activity's lifetime.
    var kindLabel: String
    var kindIcon: String
    var distanceUnit: String
}
