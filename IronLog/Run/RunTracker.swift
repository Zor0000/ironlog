import CoreLocation
import Foundation

/// GPS tracking for the Run tab.
///
/// A singleton like `LiveWorkoutEngine.shared` so a run survives the view
/// disappearing — switching tabs mid-run must not stop the clock.
///
/// Elapsed time is derived from wall-clock anchors rather than counted ticks:
/// iOS suspends timers freely in the background, and a run that loses minutes
/// while the phone is in a pocket is worse than useless. The 1 Hz timer only
/// drives redraws.
final class RunTracker: NSObject, ObservableObject {
    static let shared = RunTracker()

    enum Phase: Equatable {
        case idle
        /// Asked for location and waiting on the user. The clock is deliberately
        /// **not** running: a run whose first 30 seconds are a permission dialog
        /// has no GPS for those seconds, and baking them in corrupts the pace.
        case awaitingPermission
        case running
        case paused
    }

    /// Why a run is paused, when it wasn't the user's choice. Surfaced in the UI
    /// so a run that silently stopped measuring is never mistaken for one that
    /// is still recording.
    enum Interruption: Equatable {
        /// A one-time ("Allow Once") grant expired, or access was turned off.
        case permissionLost
        /// Restored from disk after the app was killed mid-run.
        case restored
    }

    @Published private(set) var phase: Phase = .idle
    @Published var kind: CardioKind = .run
    /// Metres, accumulated from accuracy-filtered fixes only.
    @Published private(set) var distance: Double = 0
    /// Moving seconds — time spent paused is excluded.
    @Published private(set) var elapsed: Int = 0
    @Published private(set) var route: [RoutePoint] = []
    @Published private(set) var interruption: Interruption?
    @Published private(set) var permissionDenied = false
    /// When the last trusted fix arrived. Drives the signal indicator.
    @Published private(set) var lastFixAt: Date?

    /// Called at most every `checkpointInterval` seconds while a run is active,
    /// and once when it ends (with nil). `AppState` persists this so the run
    /// survives a crash.
    var onCheckpoint: ((RunDraft?) -> Void)?

    // MARK: GPS trust thresholds
    //
    // Raw CoreLocation output wanders several metres while you stand still. Left
    // unfiltered that drift is indistinguishable from movement and silently
    // inflates a long ride's distance. These are calibration knobs — the right
    // values depend on the phone and the environment (dense city, tree cover)
    // and will want tuning against real activities.

    /// Reject fixes less accurate than this (metres).
    private static let maxHorizontalAccuracy: CLLocationDistance = 20
    /// Reject fixes older than this — CoreLocation replays stale ones on start.
    private static let maxFixAge: TimeInterval = 5
    /// Steps below this are treated as noise, not movement (metres).
    /// Note a slow walker covers less than this per second; the anchor is kept
    /// on a noise verdict precisely so those steps still add up.
    private static let minStep: CLLocationDistance = 3
    /// No trusted fix for this long means the signal is gone (tunnel, buildings)
    /// and the distance has quietly stopped growing. The UI must say so.
    static let signalTimeout: TimeInterval = 20
    /// How often an in-progress run is written to disk.
    private static let checkpointInterval: TimeInterval = 15
    /// How often distance/pace are pushed to the Live Activity. The elapsed
    /// clock is not pushed at all — the widget animates that itself — so this
    /// only needs to keep the two measured numbers fresh. ActivityKit throttles
    /// aggressive updaters, so spending the budget once every ten seconds keeps
    /// headroom for the pause/resume pushes that must land instantly.
    private static let liveActivityInterval: TimeInterval = 10

    private let manager = CLLocationManager()
    private var lastFix: CLLocation?
    private var ticker: Timer?
    /// Start of the current un-banked moving segment; nil while paused.
    private var segmentStart: Date?
    /// Moving seconds from segments already closed by a pause.
    private var bankedSeconds = 0
    private var startedAt = Date()
    private var lastCheckpointAt = Date.distantPast
    private var lastActivityPushAt = Date.distantPast
    private var wasSignalLost = false

    private override init() {
        super.init()
        manager.delegate = self
        // `Best`, not `BestForNavigation`: the latter is tuned for turn-by-turn
        // with the screen on and is markedly heavier on the battery — the wrong
        // trade for a two-hour ride with the phone locked in a jersey pocket.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        // We manage pausing ourselves; letting iOS pause updates silently ends
        // background delivery and the run stops accumulating.
        manager.pausesLocationUpdatesAutomatically = false
    }

    var hasActiveRun: Bool { phase != .idle }

    /// True when a run is recording but no trusted fix has arrived recently.
    var signalLost: Bool {
        guard phase == .running else { return false }
        guard let lastFixAt else { return false }
        return Date().timeIntervalSince(lastFixAt) > Self.signalTimeout
    }

    /// True before the very first trusted fix of a run.
    var waitingForFix: Bool { phase == .running && lastFixAt == nil }

    /// The finished activity, or nil if nothing worth saving was recorded.
    var activity: CardioActivity? {
        guard elapsed > 0, distance > 0 else { return nil }
        return CardioActivity(kind: kind, duration: elapsed, distance: distance, route: route)
    }

    // MARK: Control

    func start(kind: CardioKind) {
        guard phase == .idle else { return }
        self.kind = kind
        clearMeasurements()
        startedAt = Date()
        permissionDenied = false
        interruption = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            // Hold everything until the user answers. `didChangeAuthorization`
            // promotes this to `.running`, or drops back to `.idle` on a refusal.
            phase = .awaitingPermission
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            permissionDenied = true
        default:
            beginRunning()
        }
    }

    func pause() {
        guard phase == .running else { return }
        bankSegment()
        phase = .paused
        interruption = nil
        endUpdates()
        // Drop the anchor so the ground covered while paused is never counted as
        // one enormous step on resume.
        lastFix = nil
        checkpoint(force: true)
        pushLiveActivity(force: true)
    }

    func resume() {
        guard phase == .paused else { return }
        // Permission can have been revoked while paused — re-check rather than
        // resuming into a run that cannot measure anything.
        switch manager.authorizationStatus {
        case .denied, .restricted:
            permissionDenied = true
            interruption = .permissionLost
            return
        case .notDetermined:
            phase = .awaitingPermission
            manager.requestWhenInUseAuthorization()
            return
        default:
            break
        }
        interruption = nil
        beginRunning()
    }

    /// Stop tracking and return the recorded activity, or nil if there is
    /// nothing worth saving — in which case the run is deliberately left alive.
    /// Finishing a run that recorded nothing is almost always a mis-tap or an
    /// early tap before the first fix, and resetting here would throw the
    /// session away with no way back.
    @discardableResult
    func finish() -> CardioActivity? {
        guard phase != .idle, distance > 0, elapsed > 0 else { return nil }
        bankSegment()
        let result = activity
        reset()
        return result
    }

    func discard() {
        reset()
    }

    /// Restore a run checkpointed before the app died. Always comes back paused
    /// — see `RunDraft.elapsed`.
    func restore(from draft: RunDraft) {
        guard phase == .idle else { return }
        kind = draft.kind
        distance = draft.distance
        route = draft.route
        startedAt = draft.startedAt
        bankedSeconds = draft.elapsed
        segmentStart = nil
        elapsed = draft.elapsed
        lastFix = nil
        lastFixAt = nil
        phase = .paused
        interruption = .restored
        pushLiveActivity(force: true)
    }

    // MARK: Internals

    private func beginRunning() {
        phase = .running
        segmentStart = Date()
        beginUpdates()
        startTicker()
        pushLiveActivity(force: true)
    }

    private func clearMeasurements() {
        distance = 0
        route = []
        lastFix = nil
        lastFixAt = nil
        bankedSeconds = 0
        elapsed = 0
        segmentStart = nil
    }

    private func reset() {
        endUpdates()
        stopTicker()
        endLiveActivity()
        phase = .idle
        clearMeasurements()
        interruption = nil
        onCheckpoint?(nil)
        lastCheckpointAt = .distantPast
        wasSignalLost = false
    }

    private func beginUpdates() {
        // Only legal once authorised AND the target declares the `location`
        // background mode — otherwise this throws at runtime.
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startUpdatingLocation()
    }

    /// Stop *and* surrender the background-location capability. The Info.plist
    /// promises "nothing is tracked when you are not recording"; leaving the flag
    /// set keeps the blue status-bar indicator alive and makes that a lie.
    private func endUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func bankSegment() {
        if let segmentStart {
            bankedSeconds += Int(Date().timeIntervalSince(segmentStart).rounded())
        }
        segmentStart = nil
        refreshElapsed()
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common so the clock keeps ticking while a scroll view is dragging.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        refreshElapsed()
        // Republish so `signalLost` is re-evaluated even when no fix arrives —
        // losing signal is exactly the case where nothing else changes.
        objectWillChange.send()
        checkpoint(force: false)
        // Losing (or regaining) signal changes what the Lock Screen is claiming,
        // so it jumps the throttle queue.
        let lost = signalLost
        defer { wasSignalLost = lost }
        pushLiveActivity(force: lost != wasSignalLost)
    }

    private func refreshElapsed() {
        let live = segmentStart.map { Int(Date().timeIntervalSince($0).rounded()) } ?? 0
        elapsed = bankedSeconds + live
    }

    private func checkpoint(force: Bool) {
        guard phase == .running || phase == .paused else { return }
        guard force || Date().timeIntervalSince(lastCheckpointAt) >= Self.checkpointInterval else { return }
        lastCheckpointAt = Date()
        onCheckpoint?(RunDraft(
            kind: kind,
            distance: distance,
            elapsed: elapsed,
            route: route,
            startedAt: startedAt
        ))
    }

    // MARK: Live Activity

    /// Nothing is shown on the Lock Screen until the run is actually recording —
    /// an activity that appears while a permission dialog is still open would be
    /// claiming to measure something it cannot.
    private var showsLiveActivity: Bool { phase == .running || phase == .paused }

    private var liveAttributes: RunActivityAttributes {
        RunActivityAttributes(
            kindLabel: kind.label,
            kindIcon: kind.icon,
            distanceUnit: currentDistanceUnit.label
        )
    }

    private var liveState: RunActivityAttributes.ContentState {
        RunActivityAttributes.ContentState(
            // now − elapsed, so the widget's own timer lands on the same number.
            // While running this is a fixed instant, so repeated pushes agree.
            clockStart: Date().addingTimeInterval(-Double(elapsed)),
            elapsedText: formatElapsed(elapsed),
            distanceText: formatDistance(distance),
            paceText: formatPace(seconds: elapsed, metres: distance),
            isPaused: phase != .running,
            signalLost: signalLost
        )
    }

    /// `force` for anything the user just did — pause, resume, a lost signal —
    /// which must appear on the Lock Screen immediately rather than at the next
    /// throttled tick.
    private func pushLiveActivity(force: Bool) {
        guard showsLiveActivity else { return }
        guard force || Date().timeIntervalSince(lastActivityPushAt) >= Self.liveActivityInterval else { return }
        lastActivityPushAt = Date()
        let (state, attributes) = (liveState, liveAttributes)
        Task { @MainActor in
            LiveRunEngine.shared.sync(state, attributes: attributes)
        }
    }

    private func endLiveActivity() {
        lastActivityPushAt = .distantPast
        Task { @MainActor in
            LiveRunEngine.shared.end()
        }
    }
}

extension RunTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .running else { return }
        for location in locations {
            guard Self.isTrustworthy(location) else { continue }
            lastFixAt = Date()

            guard let previous = lastFix else {
                lastFix = location
                route.append(RoutePoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude))
                continue
            }

            switch Self.verdict(from: previous, to: location, kind: kind) {
            case .noise:
                // Keep the old anchor rather than advancing it: real but slow
                // movement then accumulates until it crosses the threshold,
                // instead of being thrown away one sub-3m step at a time.
                continue
            case .jump:
                // Implausible — re-anchor, but credit no distance.
                lastFix = location
            case .counted(let metres):
                distance += metres
                route.append(RoutePoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude))
                lastFix = location
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            permissionDenied = false
            if phase == .awaitingPermission {
                beginRunning()
            } else if phase == .running {
                beginUpdates()
            }

        case .denied, .restricted:
            permissionDenied = true
            handleLostPermission()

        case .notDetermined:
            // An "Allow Once" grant reverts to `.notDetermined` when the app
            // leaves the foreground. Without this branch the clock would keep
            // running against a GPS that has silently stopped reporting.
            handleLostPermission()

        @unknown default:
            break
        }
    }

    /// Never discard the run: pause it and say why. The distance already covered
    /// is the user's, and a permission change is not a reason to bin it.
    private func handleLostPermission() {
        guard phase == .running || phase == .awaitingPermission else { return }
        if phase == .awaitingPermission {
            // Nothing recorded yet — go back to the start screen.
            reset()
            return
        }
        bankSegment()
        phase = .paused
        endUpdates()
        stopTicker()
        lastFix = nil
        interruption = .permissionLost
        checkpoint(force: true)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure (no fix yet indoors) is normal and self-heals. A
        // hard denial arrives through the authorization callback instead.
    }

    /// A fix worth trusting: real accuracy, good enough, and not a stale replay.
    static func isTrustworthy(_ location: CLLocation, now: Date = Date()) -> Bool {
        location.horizontalAccuracy > 0
            && location.horizontalAccuracy <= maxHorizontalAccuracy
            && abs(location.timestamp.timeIntervalSince(now)) <= maxFixAge
    }

    /// What a pair of consecutive fixes contributes. The delegate's only source
    /// of truth for the filter, and pure enough to test without a GPS.
    enum StepVerdict: Equatable {
        /// Real movement worth this many metres.
        case counted(CLLocationDistance)
        /// Under the noise floor — standing still.
        case noise
        /// Faster than this activity can go: a GPS jump, not distance covered.
        case jump
    }

    static func verdict(from previous: CLLocation, to next: CLLocation, kind: CardioKind) -> StepVerdict {
        let step = next.distance(from: previous)
        let interval = next.timestamp.timeIntervalSince(previous.timestamp)
        guard step >= minStep else { return .noise }
        guard interval > 0, step / interval <= kind.maxSpeed else { return .jump }
        return .counted(step)
    }
}
