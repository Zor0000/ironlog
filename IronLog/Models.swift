
import Foundation

enum WorkoutTab: Hashable {
    case workouts, log, history, stats
}

enum AuthMode {
    case signIn, signUp
}

enum WorkoutStep: String, Codable {
    case split, day, muscle, workout
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

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, tip, bodyweight, timed
    }

    init(name: String, sets: Int, reps: String, tip: String, bodyweight: Bool = false, timed: Bool = false) {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.tip = tip
        self.bodyweight = bodyweight
        self.timed = timed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        sets = try container.decode(Int.self, forKey: .sets)
        reps = try container.decode(String.self, forKey: .reps)
        tip = try container.decode(String.self, forKey: .tip)
        bodyweight = try container.decodeIfPresent(Bool.self, forKey: .bodyweight) ?? false
        timed = try container.decodeIfPresent(Bool.self, forKey: .timed) ?? false
    }
}

struct WorkoutSet: Identifiable, Codable, Hashable {
    var id = UUID()
    var weight: String = ""
    var reps: String = ""
    var done: Bool = false
}

struct ActiveExercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var bodyweight: Bool
    var timed: Bool
    var custom: Bool = false
    var expanded: Bool = true
    var sets: [WorkoutSet]
}

struct WorkoutDraft: Codable, Equatable {
    var exercises: [ActiveExercise]
    var muscle: String?
    var split: String?
    var day: String?
    var step: WorkoutStep?
    var showAddExerciseForm: Bool?
    var addExerciseWeighted: Bool?
    var note: String?
}

struct LoggedSet: Identifiable, Codable, Hashable {
    var id = UUID()
    var weight: Double?
    var reps: Int
}

struct LoggedExercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var bodyweight: Bool
    var timed: Bool
    var sets: [LoggedSet]
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
}

enum SyncState: String, Codable, Hashable {
    case localOnly, pending, synced, failed
}

struct PersonalRecord: Identifiable, Codable, Hashable {
    var id: String { exerciseName }
    var exerciseName: String
    var weight: Double
    var reps: Int
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
