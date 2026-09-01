
import Foundation

enum WorkoutTab: Hashable {
    case workouts, log, run, history, stats
}

enum AuthMode {
    case signIn, signUp
}

enum WorkoutStep: String, Codable, CaseIterable {
    case split, day, workout

    /// Position in the wizard, so a step change can tell forward from back.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

struct UserProfile: Codable, Equatable {
    var id: String
    var email: String
    var fullName: String?
    var isLocal: Bool = false

    var displayName: String {
        if isLocal { return "athlete" }
        if let first = fullName?.split(separator: " ").first, !first.isEmpty {
            return String(first)
        }
        return email.split(separator: "@").first.map(String.init) ?? "athlete"
    }
}

struct Muscle: Identifiable, Codable, Hashable {
    var id: String
    var label: String
    var systemImage: String
}

struct SplitDay: Identifiable, Codable, Hashable {
    var id: String { day }
    var day: String
    var muscles: [String]
}

struct ExerciseTemplate: Identifiable, Codable, Hashable {
    var id: String { name }
    var name: String
    var sets: Int
    var reps: String
    var tip: String
    var bodyweight: Bool
    var timed: Bool
    /// A `timed` move whose duration is entered in whole minutes rather than
    /// seconds — steady-state cardio machines, where "1200 seconds" is nobody's
    /// mental model. Storage stays canonical seconds either way.
    var minutes: Bool

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, tip, bodyweight, timed, minutes
    }

    init(name: String, sets: Int, reps: String, tip: String, bodyweight: Bool = false, timed: Bool = false, minutes: Bool = false) {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.tip = tip
        self.bodyweight = bodyweight
        self.timed = timed
        self.minutes = minutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        sets = try container.decode(Int.self, forKey: .sets)
        reps = try container.decode(String.self, forKey: .reps)
        tip = try container.decode(String.self, forKey: .tip)
        bodyweight = try container.decodeIfPresent(Bool.self, forKey: .bodyweight) ?? false
        timed = try container.decodeIfPresent(Bool.self, forKey: .timed) ?? false
        minutes = try container.decodeIfPresent(Bool.self, forKey: .minutes) ?? false
    }
}

/// How a set was performed, when it was something other than a straight
/// working set. Stored as an Optional everywhere: nil is an ordinary set, which
/// is also how every set logged before this existed decodes.
enum SetType: String, Codable, Hashable, CaseIterable {
    case warmup, drop, failure, restPause, repsInReserve

    var label: String {
        switch self {
        case .warmup: "Warm-up"
        case .drop: "Drop set"
        case .failure: "To failure"
        case .restPause: "Rest-pause"
        case .repsInReserve: "Reps in reserve"
        }
    }

    var icon: String {
        switch self {
        case .warmup: "sun.max"
        case .drop: "arrow.down.right.circle"
        case .failure: "flame"
        case .restPause: "pause.circle"
        case .repsInReserve: "hand.raised"
        }
    }

    /// Whether the set is real work. A warm-up is the one type that is not:
    /// counting an empty-bar set toward the day's tonnage inflates volume, and
    /// letting it reach `applyRecords` lets a warm-up claim a personal record.
    /// A drop set and a set to failure are both working sets — harder ones.
    var countsAsVolume: Bool { self != .warmup }
}

struct WorkoutSet: Identifiable, Codable, Hashable {
    var id = UUID()
    var weight: String = ""
    var reps: String = ""
    var done: Bool = false
    /// Optional — synthesized `Decodable` has no default-value fallback, so a
    /// plain value would fail to decode drafts written before set types existed.
    var type: SetType?
}

struct ActiveExercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var bodyweight: Bool
    var timed: Bool
    /// See `ExerciseTemplate.minutes` — duration typed in minutes, stored in
    /// seconds. Optional (not `Bool = false`): synthesized `Decodable` has no
    /// default-value fallback, so a plain Bool would fail to decode drafts
    /// written before cardio existed.
    var minutes: Bool?
    var custom: Bool = false
    var expanded: Bool = true
    var sets: [WorkoutSet]

    /// True once any set has been checked off or has a typed weight/reps — i.e. deleting would
    /// throw away logged work, so it's worth a confirmation.
    var hasLoggedData: Bool {
        sets.contains { $0.done || !$0.reps.isEmpty || !$0.weight.isEmpty }
    }

    /// Duration entered in whole minutes rather than seconds. Only ever true for
    /// a `timed` move, so it is safe to pass straight to the duration helpers.
    var usesMinutes: Bool { minutes == true }
}

struct WorkoutDraft: Codable, Equatable {
    var exercises: [ActiveExercise]
    var split: String?
    var day: String?
    var step: WorkoutStep?
    var showAddExerciseForm: Bool?
    var addExerciseWeighted: Bool?
    var note: String?
}

/// A workout the user saved to run again — "Anshul's leg day". The counterpart
/// to a bundled split, authored from whatever is in the log rather than shipped
/// in workouts.json.
///
/// It holds `ExerciseTemplate`s, the same currency the bundled splits deal in,
/// so starting one reuses the existing template → `todayExercises` mapping
/// instead of growing a second way to begin a workout.
struct SavedRoutine: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var createdAt: Date = Date()
    var exercises: [ExerciseTemplate]
}

struct LoggedSet: Identifiable, Codable, Hashable {
    var id = UUID()
    var weight: Double?
    /// Half-rep capable — see the REP HELPERS section. `Double` rather than
    /// `Int` decodes old snapshots unchanged (JSON `7` reads back as `7.0`),
    /// which matters because `LocalStore.load` turns a decode failure into an
    /// empty snapshot and would wipe every saved session.
    var reps: Double
    /// See `WorkoutSet.type` — Optional for the same decode reason, which here
    /// guards saved history rather than a draft.
    var type: SetType?

    /// Volume and personal records both skip anything that is not real work.
    var isWorkingSet: Bool { type?.countsAsVolume ?? true }
}

struct LoggedExercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var bodyweight: Bool
    var timed: Bool
    /// Display-only: `sets[].reps` is always seconds for a timed move. Optional
    /// because a missing key must decode, not throw — `LocalStore.load` turns any
    /// decode failure into an empty snapshot, which would wipe saved history.
    var minutes: Bool?
    var sets: [LoggedSet]

    /// See `ActiveExercise.usesMinutes`.
    var usesMinutes: Bool { minutes == true }
}

struct WorkoutSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var cloudID: String?
    var userID: String?
    var createdAt: Date
    var muscle: String?
    var split: String?
    var note: String?
    var exercises: [LoggedExercise]
    var syncState: SyncState = .pending
    /// Set for a tracked run/walk, which has no exercises. Optional so sessions
    /// saved before the Run tab existed still decode — see `LocalStore.load`.
    var activity: CardioActivity?

    var isCardio: Bool { activity != nil }
}

// ─────────────────────────────────────────────────────────────
//  CARDIO  (Run tab)
// ─────────────────────────────────────────────────────────────

enum CardioKind: String, Codable, Hashable, CaseIterable {
    case run, walk

    /// Anything unrecognised decodes as a walk rather than throwing.
    ///
    /// `LocalStore.load` discards the *entire* snapshot on any decode error, so
    /// a single session saved under a kind we no longer ship — "cycle", which
    /// this app used to offer — would silently wipe every workout, routine and
    /// setting on upgrade. A ride mislabelled as a walk keeps its distance,
    /// time and route; that is the far smaller loss.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardioKind(rawValue: raw) ?? .walk
    }

    var label: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        }
    }

    var icon: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        }
    }

    var blurb: String {
        switch self {
        case .run: "Outside or on a treadmill"
        case .walk: "Easy miles still count"
        }
    }
}

/// Where a cardio session happened. Purely context for the history card — the
/// one behavioural difference is that a treadmill session carries no route.
enum CardioTerrain: String, Codable, CaseIterable, Hashable {
    case road, trail, treadmill, track

    /// Unknown raw values decode as a road rather than throwing.
    ///
    /// Same rationale as `CardioKind`: `LocalStore.load` discards the entire
    /// snapshot on any decode error, so a session saved under a terrain we
    /// someday retire must not be able to wipe every workout on upgrade.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardioTerrain(rawValue: raw) ?? .road
    }

    var label: String {
        switch self {
        case .road: "Road"
        case .trail: "Trail"
        case .treadmill: "Treadmill"
        case .track: "Track"
        }
    }

    var icon: String {
        switch self {
        case .road: "road.lanes"
        case .trail: "figure.hiking"
        // No "treadmill" symbol ships in SF Symbols, so the closest activity
        // glyph stands in — the label carries the meaning anyway.
        case .treadmill: "figure.walk"
        case .track: "flag.checkered"
        }
    }
}

/// One GPS fix kept for the route line. Deliberately just two doubles: an hour
/// run is a few thousand points and the whole snapshot is re-encoded on save.
struct RoutePoint: Codable, Hashable {
    var lat: Double
    var lon: Double
}

struct CardioActivity: Codable, Hashable {
    var kind: CardioKind
    /// Moving time in seconds — time spent paused is not counted.
    var duration: Int
    /// Metres, accumulated from accuracy-filtered fixes.
    var distance: Double
    var route: [RoutePoint]
    /// Metres of ascent. Optional so sessions saved before it existed decode —
    /// see `LocalStore.load`, which wipes the snapshot on any decode error.
    var elevationGain: Int?
    /// Optional context for the history card.
    var terrain: CardioTerrain?
    /// Kilocalories, either estimated by `estimateCalories` at save time or
    /// typed over it. Optional: without a body weight there is no estimate.
    var calories: Int?
}

/// Kilocalories for a run or walk, from the ACSM metabolic equations.
///
/// With a distance the equations for the metabolic cost of level + graded
/// walking and running apply — speed in m/min and grade as rise over run:
///   run  VO₂ = 0.2·v + 0.9·v·grade + 3.5
///   walk VO₂ = 0.1·v + 1.8·v·grade + 3.5
/// VO₂ in mL/kg/min converts to kcal by multiplying through the body weight
/// and the duration (→ litres of O₂) and then by ~5 kcal per litre.
///
/// Without a distance there is nothing to put a speed on, so published MET
/// values stand in: 9.8 for running, 3.8 for walking.
///
/// Returns nil without a body weight or a duration — an estimate with either
/// missing would be a made-up number presented as one.
func estimateCalories(kind: CardioKind, durationSeconds: Int, distanceMetres: Double, elevationGainMetres: Int, bodyWeightKg: Double) -> Int? {
    guard bodyWeightKg > 0, durationSeconds > 0 else { return nil }
    let minutes = Double(durationSeconds) / 60
    guard distanceMetres > 0 else {
        let met: Double = kind == .run ? 9.8 : 3.8
        return Int((met * bodyWeightKg * minutes / 60).rounded())
    }
    let speed = distanceMetres / minutes
    let grade = elevationGainMetres > 0 ? Double(elevationGainMetres) / distanceMetres : 0
    let (linear, vertical): (Double, Double) = kind == .run ? (0.2, 0.9) : (0.1, 1.8)
    let vo2 = linear * speed + vertical * speed * grade + 3.5
    let kcal = vo2 * bodyWeightKg * minutes / 1000 * 5
    return Int(kcal.rounded())
}

/// Build an activity from what the user typed into the manual logger.
///
/// Returns nil unless there is a real duration: time is the only hard
/// requirement for a tracked session, so it cannot be optional here either.
/// Distance and elevation are taken in the display unit and may be left
/// blank — a treadmill that only shows a clock is still a session worth
/// keeping. Calories are estimated from the current body weight when there
/// is one; the logger may override the figure afterwards.
func manualCardio(kind: CardioKind, minutes: String, distance: String, elevation: String = "", terrain: CardioTerrain? = nil) -> CardioActivity? {
    guard let mins = decimalEntry(minutes), mins > 0 else { return nil }
    var activity = CardioActivity(
        kind: kind,
        duration: Int((mins * 60).rounded()),
        distance: max(decimalEntry(distance).map { $0 * currentDistanceUnit.metres } ?? 0, 0),
        route: [],
        elevationGain: decimalEntry(elevation).map { Int(max($0, 0).rounded()) },
        terrain: terrain
    )
    activity.calories = estimateCalories(
        kind: activity.kind,
        durationSeconds: activity.duration,
        distanceMetres: activity.distance,
        elevationGainMetres: activity.elevationGain ?? 0,
        bodyWeightKg: currentBodyWeight
    )
    return activity
}

/// A typed number, accepting the comma decimal separator most of the world uses.
func decimalEntry(_ text: String) -> Double? {
    Double(text.replacingOccurrences(of: ",", with: "."))
}

// ─────────────────────────────────────────────────────────────
//  DISTANCE / PACE HELPERS
//  Distance is stored canonically in METRES, like weight in kg and duration in
//  seconds. The display unit follows the weight preference rather than adding a
//  second setting — nobody logs pounds and kilometres.
// ─────────────────────────────────────────────────────────────

enum DistanceUnit {
    case km, mi

    var label: String { self == .km ? "km" : "mi" }
    var metres: Double { self == .km ? 1000 : 1609.344 }
}

var currentDistanceUnit: DistanceUnit { currentWeightUnit == .kg ? .km : .mi }

/// Number-only distance in the display unit, e.g. "5.42".
func formatDistance(_ metres: Double) -> String {
    String(format: "%.2f", metres / currentDistanceUnit.metres)
}

/// Pace as "m:ss" per km/mi — the number runners actually read. Returns
/// "--:--" until there is enough distance for the figure to mean anything.
func formatPace(seconds: Int, metres: Double) -> String {
    guard seconds > 0, metres > 20 else { return "--:--" }
    let perUnit = Double(seconds) / (metres / currentDistanceUnit.metres)
    guard perUnit.isFinite, perUnit < 3600 else { return "--:--" }
    let total = Int(perUnit.rounded())
    return "\(total / 60):\(String(format: "%02d", total % 60))"
}

/// Speed as "10.0 km/h" / "6.2 mph" — the treadmill's favourite number and the
/// complement of pace. "--" until there is enough distance to mean anything.
func formatSpeed(seconds: Int, metres: Double) -> String {
    guard seconds > 0, metres > 20 else { return "--" }
    let kmh = metres / 1000 / (Double(seconds) / 3600)
    guard kmh.isFinite else { return "--" }
    let value = currentDistanceUnit == .km ? kmh : kmh * 0.621371
    return String(format: "%.1f", value)
}

/// Unit label that pairs with `formatSpeed`.
var speedUnitLabel: String { currentDistanceUnit == .km ? "km/h" : "mph" }

/// Elapsed clock for a run — "24:10", or "1:04:22" once past the hour.
/// (`formatDuration` is the rest-timer's m:ss and never needs hours.)
func formatElapsed(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60
    return hours > 0
        ? "\(hours):\(String(format: "%02d:%02d", minutes, secs))"
        : "\(minutes):\(String(format: "%02d", secs))"
}

enum SyncState: String, Codable, Hashable {
    case localOnly, pending, synced, failed
}

struct PersonalRecord: Identifiable, Codable, Hashable {
    var id: String { exerciseName }
    var exerciseName: String
    var weight: Double
    var reps: Double
    var achievedAt: Date
}

struct AppSnapshot: Codable {
    var sessions: [WorkoutSession] = []
    var personalRecords: [PersonalRecord] = []
    var waterByDay: [String: Int] = [:]
    var draft: WorkoutDraft?
    // Optional so snapshots written before these fields existed still decode
    // (a failed decode falls back to an empty snapshot and wipes history).
    var unitPreference: WeightUnit?
    var hasOnboarded: Bool?
    var timerPreset: Int?
    var routines: [SavedRoutine]?
    /// Canonical KG; nil until the user sets it, and what calorie estimates need.
    var bodyWeight: Double?
}

// ─────────────────────────────────────────────────────────────
//  WEIGHT / PERFORMANCE HELPERS  (shared logic — see CLAUDE design rules)
//  Weight is stored canonically in KG everywhere — in sessions, PRs and
//  Supabase. The user's unit is a display/input concern only:
//  `formatWeight`/`displayWeight` convert kg → the chosen unit for display,
//  and `displayWeightToKg` converts typed input back to kg for storage.
// ─────────────────────────────────────────────────────────────

enum WeightUnit: String, Codable {
    case kg, lb

    var label: String { self == .kg ? "kg" : "lb" }
    /// Uppercase form for input-field labels ("KG"/"LB") and the Live Activity.
    var fieldLabel: String { label.uppercased() }
}

/// The active display unit. Mirrored from `AppState.unitPreference` (the
/// persisted source of truth) so `formatWeight` stays a zero-context chokepoint
/// callable from any view helper.
var currentWeightUnit: WeightUnit = .kg

/// The user's body weight in canonical KG, mirrored from `AppState.bodyWeight`
/// exactly like `currentWeightUnit`. Zero means "not set" — calorie estimates
/// then return nil rather than inventing a person.
var currentBodyWeight: Double = 0

private let kgPerLb = 0.45359237

/// A KG value converted to the display unit. Pounds round to the nearest
/// 0.5 lb — finer than any plate, coarse enough to hide float noise.
func displayWeight(_ kg: Double, in unit: WeightUnit = currentWeightUnit) -> Double {
    unit == .kg ? kg : (kg / kgPerLb * 2).rounded() / 2
}

/// Typed input in the display unit, converted back to canonical KG.
func displayWeightToKg(_ value: Double, in unit: WeightUnit = currentWeightUnit) -> Double {
    unit == .kg ? value : value * kgPerLb
}

/// Number-only display string for a KG weight (for placeholders/inputs).
func formatWeightValue(_ kg: Double) -> String {
    clean(displayWeight(kg))
}

/// Display string for a KG weight, e.g. "60 kg" / "137.5 lb".
/// Reuses `clean(_:)` so the number matches everywhere it is shown.
func formatWeight(_ kg: Double) -> String {
    "\(formatWeightValue(kg)) \(currentWeightUnit.label)"
}

// ─────────────────────────────────────────────────────────────
//  REP HELPERS
//  Reps are stored as a Double so a set can be "7.5" — the rep you failed
//  partway up, or a deliberate partial-ROM rep pushed past failure.
//
//  A half is as fine as the grid goes. Training literature names quarter, half
//  and three-quarter partials, but that is a description of range of motion,
//  not a counting unit: no one logs a rep tally to the quarter, and a finer
//  grid only buys typing. Timed moves stay whole — `reps` is seconds there.
// ─────────────────────────────────────────────────────────────

/// The half-rep grid. Mirrors how `displayWeight` rounds pounds, for the same
/// reason: finer than anything real, coarse enough to hide float noise.
func snapToHalf(_ value: Double) -> Double { (value * 2).rounded() / 2 }

/// Typed reps snapped to the nearest half *on the keystroke*, so the field can
/// only ever hold a loggable value — "7.2" collapses to "7" and "7.4" to "7.5"
/// as they type, rather than being silently rejected later at save time.
///
/// A lone trailing "." survives untouched: snapping it away would make the
/// decimal point impossible to type in the first place.
func snapReps(_ input: String) -> String {
    var whole = ""
    var fraction: Character?
    var seenSeparator = false
    for character in input {
        if character.isNumber {
            // One decimal digit is all the grid can hold; further keys are dead.
            if seenSeparator {
                if fraction == nil { fraction = character }
            } else {
                whole.append(character)
            }
        } else if character == "." || character == ",", !seenSeparator {
            seenSeparator = true
        }
    }
    guard seenSeparator else { return whole }
    guard let fraction else { return whole + "." }
    let value = (Double(whole) ?? 0) + (Double(String(fraction)) ?? 0) / 10
    return clean(snapToHalf(value))
}

// ─────────────────────────────────────────────────────────────
//  DURATION HELPERS  (timed exercises)
//  Duration is stored canonically in SECONDS everywhere — in sets, drafts and
//  Supabase — exactly like weight is stored in kg. `minutes` is a display/input
//  concern only: cardio machines are logged in whole minutes, holds and
//  intervals in seconds. These four are the only places that conversion lives.
// ─────────────────────────────────────────────────────────────

// `durationFieldLabel` lives in `LiveWorkoutModels.swift` instead — the widget
// target needs it too, and this file is not compiled into the extension.

/// Canonical seconds converted to the value shown in the input field.
func displayDuration(_ seconds: Int, minutes: Bool) -> Int {
    minutes ? seconds / 60 : seconds
}

/// Typed input in the display unit, converted back to canonical seconds.
func displayDurationToSeconds(_ value: Int, minutes: Bool) -> Int {
    minutes ? value * 60 : value
}

/// Display string for a stored duration, e.g. "20 min" / "45s".
func formatLoggedDuration(_ seconds: Int, minutes: Bool) -> String {
    minutes ? "\(seconds / 60) min" : "\(seconds)s"
}

/// Rest-timer default durations (seconds) offered in the Log and Settings tabs.
let restTimerPresets = [60, 90, 120, 180]

/// "m:ss" for a seconds count, e.g. 90 → "1:30".
func formatDuration(_ seconds: Int) -> String {
    "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
}

extension Date {
    var dayKey: String {
        Self.dayFormatter.string(from: self)
    }

    var displayDay: String {
        Self.displayFormatter.string(from: self)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
