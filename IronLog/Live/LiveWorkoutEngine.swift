import Foundation
import ActivityKit

/// Owns the IronLog Live Activity and the shared snapshot that backs it.
///
/// Both surfaces talk to the same singleton:
/// - The app (`AppState`) calls `start`, `sync`, and `end` as the workout changes.
/// - Lock-screen intents call `mutate` to apply a `LiveWorkoutReducer` transform
///   and push the result back to the Activity without unlocking the phone.
///
/// State is persisted to `UserDefaults` so an intent can run even after the app
/// process was relaunched in the background to service the tap.
final class LiveWorkoutEngine: @unchecked Sendable {
    static let shared = LiveWorkoutEngine()

    private let defaults = UserDefaults.standard
    private let stateKey = "ironlog.liveWorkout.state"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: Persistence

    var currentState: LiveWorkoutState? {
        guard let data = defaults.data(forKey: stateKey) else { return nil }
        return try? decoder.decode(LiveWorkoutState.self, from: data)
    }

    private func persist(_ state: LiveWorkoutState?) {
        guard let state, let data = try? encoder.encode(state) else {
            defaults.removeObject(forKey: stateKey)
            return
        }
        defaults.set(data, forKey: stateKey)
    }

    // MARK: App-facing API

    /// Whether the user has Live Activities enabled in Settings.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private var activity: Activity<WorkoutActivityAttributes>? {
        Activity<WorkoutActivityAttributes>.activities.first
    }

    /// Begin (or replace) the lock-screen activity for a fresh workout.
    @discardableResult
    func start(_ state: LiveWorkoutState, weightUnit: String = "KG") async -> Bool {
        persist(state)
        guard isAvailable else { return false }

        // Replace any stale activity from a previous session.
        for existing in Activity<WorkoutActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }

        do {
            _ = try Activity.request(
                attributes: WorkoutActivityAttributes(weightUnit: weightUnit),
                content: content(for: state),
                pushType: nil
            )
            return true
        } catch {
            return false
        }
    }

    /// Push the latest in-app state to the running activity, starting one if the
    /// user enabled Live Activities mid-workout.
    func sync(_ state: LiveWorkoutState, weightUnit: String = "KG") async {
        persist(state)
        guard let activity else {
            if isAvailable, !state.exercises.isEmpty {
                await start(state, weightUnit: weightUnit)
            }
            return
        }
        await activity.update(content(for: state))
    }

    /// Apply a reducer transform and push it to the activity. Used by the
    /// lock-screen intents, which run in the app's process.
    func mutate(_ transform: (LiveWorkoutState) -> LiveWorkoutState) async {
        guard let state = currentState else { return }
        let next = transform(state)
        persist(next)
        await activity?.update(content(for: next))
    }

    /// Tear the activity down and forget the shared snapshot.
    func end() async {
        for existing in Activity<WorkoutActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        persist(nil)
    }

    private func content(for state: LiveWorkoutState) -> ActivityContent<WorkoutActivityAttributes.ContentState> {
        // Keep the activity fresh until a little after the current rest ends.
        let stale = state.restEndsAt.map { $0.addingTimeInterval(60) }
        return ActivityContent(state: .init(workout: state), staleDate: stale)
    }
}
