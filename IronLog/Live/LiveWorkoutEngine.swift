import Foundation
import ActivityKit
import UserNotifications

/// Schedules the "rest over" local notification — the background safety net
/// for the in-app countdown (the Live Activity counts down visually but never
/// alerts). One fixed identifier, so rescheduling replaces instead of stacking
/// and the app + lock-screen paths can never double-fire.
/// A class so tests can subclass a spy; stateless otherwise.
class RestTimerNotifier {
    static let id = "ironlog.restTimer"

    func schedule(at endsAt: Date) {
        let center = UNUserNotificationCenter.current()
        // Lazy permission: the first schedule triggers the system prompt;
        // once decided, this resolves immediately on every later call.
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let remaining = endsAt.timeIntervalSinceNow
            guard remaining > 1 else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest over"
            content.body = "Time for your next set."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.id, content: content, trigger: trigger))
        }
    }

    func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.id])
    }
}

/// Owns the IronLog Live Activity and the shared snapshot that backs it.
///
/// Every operation is isolated to the main actor and processed through a FIFO
/// task chain, so concurrent app updates and lock-screen intents can never:
/// - create a duplicate activity (two `sync`s racing before `request` returns), or
/// - resurrect one after `end()` (a stale `sync` landing after a finish).
///
/// State is persisted to `UserDefaults` so a lock-screen intent can run even
/// after the app process was relaunched in the background to service the tap.
@MainActor
final class LiveWorkoutEngine {
    static let shared = LiveWorkoutEngine()

    private let defaults = UserDefaults.standard
    private let stateKey = "ironlog.liveWorkout.state"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Tail of the serial operation chain; each new op awaits the previous one.
    private var tail: Task<Void, Never> = Task {}
    /// Last state handed to ActivityKit, used to skip redundant updates.
    private var lastPushed: LiveWorkoutState?

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

    // MARK: Serial queue

    @discardableResult
    private func enqueue(_ operation: @escaping () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous.value
            await operation()
        }
        tail = task
        return task
    }

    // MARK: App-facing API

    /// Whether the user has Live Activities enabled in Settings.
    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private var activity: Activity<WorkoutActivityAttributes>? {
        Activity<WorkoutActivityAttributes>.activities.first
    }

    /// Push the latest in-app state to the activity, starting one if the user
    /// enabled Live Activities mid-workout. Fire-and-forget; ordered via the queue.
    func sync(_ state: LiveWorkoutState, weightUnit: String = "KG") {
        enqueue { await self.performSync(state, weightUnit: weightUnit) }
    }

    /// Tear the activity down and forget the shared snapshot.
    func end() {
        enqueue { await self.performEnd() }
    }

    /// Apply a reducer transform from a lock-screen intent and await the update,
    /// so the Live Activity reflects the tap before `perform()` returns.
    func mutate(_ transform: @escaping @Sendable (LiveWorkoutState) -> LiveWorkoutState) async {
        await enqueue { await self.performMutate(transform) }.value
    }

    // MARK: Operations (run one at a time, in enqueue order)

    private func performStart(_ state: LiveWorkoutState, weightUnit: String) async {
        for existing in Activity<WorkoutActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        do {
            _ = try Activity.request(
                attributes: WorkoutActivityAttributes(weightUnit: weightUnit),
                content: content(for: state),
                pushType: nil
            )
            lastPushed = state
        } catch {
            lastPushed = nil
        }
    }

    private func performSync(_ state: LiveWorkoutState, weightUnit: String) async {
        persist(state)
        guard let activity else {
            if isAvailable, !state.exercises.isEmpty {
                await performStart(state, weightUnit: weightUnit)
            }
            return
        }
        guard state != lastPushed else { return }
        await activity.update(content(for: state))
        lastPushed = state
    }

    private func performMutate(_ transform: @Sendable (LiveWorkoutState) -> LiveWorkoutState) async {
        guard let state = currentState else { return }
        let next = transform(state)
        persist(next)
        // Lock-screen taps restart or clear the rest period while the app is
        // suspended; keep the "rest over" notification in step. (In-app set
        // logging schedules through AppState — same identifier, so no stacking.)
        if next.restEndsAt != state.restEndsAt {
            if let endsAt = next.restEndsAt, endsAt > Date() {
                RestTimerNotifier().schedule(at: endsAt)
            } else {
                RestTimerNotifier().cancel()
            }
        }
        guard let activity else { return }
        await activity.update(content(for: next))
        lastPushed = next
    }

    private func performEnd() async {
        for existing in Activity<WorkoutActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        persist(nil)
        lastPushed = nil
    }

    private func content(for state: LiveWorkoutState) -> ActivityContent<WorkoutActivityAttributes.ContentState> {
        // Keep the activity fresh until a little after the current rest ends.
        let stale = state.restEndsAt.map { $0.addingTimeInterval(60) }
        return ActivityContent(state: .init(workout: state), staleDate: stale)
    }

    #if DEBUG
    /// Test hook: await all queued operations so assertions see a settled state.
    func waitForPendingOperations() async {
        await tail.value
    }
    #endif
}

/// Owns the tracked-run Live Activity.
///
/// Deliberately thinner than `LiveWorkoutEngine`: a run's truth lives in
/// `RunTracker` inside the app process, which the background-location mode keeps
/// alive for the activity's whole duration. There is nothing to persist here and
/// no reducer — the Lock Screen renders and commands, it never edits.
///
/// The same serial task chain is used, for the same reason: two `sync` calls
/// racing before `request` returns would otherwise create duplicate activities,
/// and a late `sync` could resurrect one after `end()`.
@MainActor
final class LiveRunEngine {
    static let shared = LiveRunEngine()

    private var tail: Task<Void, Never> = Task {}
    private var lastPushed: RunActivityAttributes.ContentState?

    private init() {}

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private var activity: Activity<RunActivityAttributes>? {
        Activity<RunActivityAttributes>.activities.first
    }

    @discardableResult
    private func enqueue(_ operation: @escaping () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous.value
            await operation()
        }
        tail = task
        return task
    }

    func sync(_ state: RunActivityAttributes.ContentState, attributes: RunActivityAttributes) {
        enqueue { await self.performSync(state, attributes: attributes) }
    }

    func end() {
        enqueue { await self.performEnd() }
    }

    private func performSync(_ state: RunActivityAttributes.ContentState, attributes: RunActivityAttributes) async {
        guard let activity else {
            guard isAvailable else { return }
            for existing in Activity<RunActivityAttributes>.activities {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
            _ = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastPushed = state
            return
        }
        guard state != lastPushed else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
        lastPushed = state
    }

    private func performEnd() async {
        for existing in Activity<RunActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        lastPushed = nil
    }

    #if DEBUG
    func waitForPendingOperations() async {
        await tail.value
    }
    #endif
}
