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
