import CoreLocation
import CoreMotion
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
    /// How much of `distance` the pedometer contributed. Display only — it says
    /// which source is measuring, and never adds to the total a second time.
    @Published private(set) var stepMetres: Double = 0

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
    /// Step-counted distance for the indoor case — see `applyStepDistance`.
    /// Built on first use, not at launch: constructing it is enough to raise the
    /// Motion & Fitness prompt, and asking during onboarding — before the user
    /// has ever opened the Run tab — earns a "Don't Allow" it never recovers from.
    private var pedometer: CMPedometer?
    /// Pedometer metres already credited from the current segment. The API
    /// reports a running total from its start date, so only the increment is new.
    private var creditedStepMetres: Double = 0
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

    /// True before the very first trusted fix of a run, for the first few
    /// seconds only — see `measuringNothing` for what happens after that.
    var waitingForFix: Bool {
        phase == .running && lastFixAt == nil && elapsed < Int(Self.signalTimeout)
    }

    /// Distance is coming from step counting rather than GPS, so there will be
    /// no route to draw. The UI says so instead of implying a tracked line.
    ///
    /// Asks what the pedometer actually contributed rather than inferring it
    /// from "no fix yet, but distance": a run recovered from disk comes back in
    /// exactly that state with GPS-measured metres, and would otherwise claim to
    /// be counting steps when it never was.
    var stepCounting: Bool { stepMetres > 0 }

    /// GPS has had its chance and produced no distance: a treadmill, a basement
    /// gym, an indoor track. Not an error state — it is how most runs indoors
    /// look — so the UI switches to asking for the number instead of sitting on
    /// "Acquiring GPS…" for the whole session.
    var measuringNothing: Bool {
        phase != .idle && distance == 0 && elapsed >= Int(Self.signalTimeout)
    }

    /// The finished activity, or nil if nothing worth saving was recorded.
    ///
    /// Time is the only requirement. Distance may legitimately be zero — a
    /// treadmill, a basement gym, a covered track — and refusing to save those
    /// made the whole tab a dead end indoors: the clock ran, Finish did nothing,
    /// and Discard was the only way out.
    var activity: CardioActivity? {
        guard elapsed > 0 else { return nil }
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
    /// Finishing a run that recorded nothing is almost always a mis-tap, and
    /// resetting here would throw the session away with no way back.
    ///
    /// `manualMetres` is the treadmill path: GPS measured nothing, so the user
    /// reads the distance off the machine and types it in. It only ever fills a
    /// gap — a measured distance is never overwritten.
    @discardableResult
    func finish(manualMetres: Double? = nil) -> CardioActivity? {
        // Guard before banking: banking clears `segmentStart`, so an early return
        // afterwards would leave the run "running" with a stopped clock.
        guard phase != .idle, elapsed > 0 else { return nil }
        bankSegment()
        if distance == 0, let manualMetres, manualMetres > 0 {
            distance = manualMetres
        }
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
        stepMetres = 0
        creditedStepMetres = 0
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
        beginStepUpdates()
    }

    /// Stop *and* surrender the background-location capability. The Info.plist
    /// promises "nothing is tracked when you are not recording"; leaving the flag
    /// set keeps the blue status-bar indicator alive and makes that a lie.
    private func endUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        // Only if it was ever started — see the `pedometer` declaration.
        pedometer?.stopUpdates()
    }

    // MARK: Step counting
    //
    // The motion coprocessor counts steps and estimates distance with no GPS
    // and no meaningful battery cost, which is the only thing that measures a
    // treadmill at all. It is the second of three sources, in falling order of
    // trust: GPS, then steps, then a number the user types in.

    /// Start counting from *now*, so a segment resumed after a pause never
    /// inherits the steps taken while paused.
    private func beginStepUpdates() {
        guard CMPedometer.isDistanceAvailable() else { return }
        let pedometer = pedometer ?? CMPedometer()
        self.pedometer = pedometer
        // A re-grant of location permission mid-run calls `beginUpdates` again;
        // stop first so a second handler is never stacked on the first.
        pedometer.stopUpdates()
        creditedStepMetres = 0
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            // Delivered on an arbitrary queue; `distance` is @Published.
            guard let metres = data?.distance?.doubleValue else { return }
            DispatchQueue.main.async { self?.applyStepDistance(metres) }
        }
    }

    /// Internal rather than private so tests can drive it without a real
    /// pedometer — the simulator has no CoreMotion at all.
    func applyStepDistance(_ cumulative: Double) {
        // Readings are delivered asynchronously and can land after a pause, a
        // finish or a discard. Anything but an active run must be ignored, or a
        // saved run grows metres the user did not cover while stopped.
        guard phase == .running else { return }
        let credit = Self.stepCredit(
            cumulative: cumulative,
            alreadyCredited: creditedStepMetres,
            hasGPSFix: lastFixAt != nil
        )
        creditedStepMetres = cumulative
        distance += credit
        stepMetres += credit
    }

    /// How many metres a pedometer reading contributes.
    ///
    /// Steps only count while GPS has never produced a trusted fix this
    /// session, so exactly one source is live at a time and the two can never
    /// double-count each other. Outdoors the first fix hands ownership to GPS
    /// permanently; the metres counted before it arrived are kept, because they
    /// were covered — just not yet seen by satellite.
    ///
    /// The reading is a running total from the segment's start, so only the
    /// increment is new. It can go backwards when CoreMotion revises an
    /// estimate downwards, and distance must never shrink under the user.
    static func stepCredit(cumulative: Double, alreadyCredited: Double, hasGPSFix: Bool) -> Double {
        guard !hasGPSFix else { return 0 }
        return max(0, cumulative - alreadyCredited)
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
