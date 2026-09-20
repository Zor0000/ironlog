import Foundation

/// A named signal that contributed to an exercise's relevance score. The UI
/// turns these into short, honest copy; the copy therefore never claims a
/// factor the engine did not actually weigh.
enum ExerciseRecommendationFactor: Equatable, Hashable {
    /// Never appears in the user's logged history.
    case neverLogged
    /// Last logged at least this many days ago (14+).
    case restedFor(days: Int)
    /// Logged within the last few days; pushed down the ranking.
    case trainedRecently(days: Int)
    /// Logged this many times in the last 30 days (2+); pushed down slightly.
    case frequentlyUsed(count: Int)
    /// A compound movement while the current workout has none yet.
    case addsCompound
    /// An isolation movement to complement a compound already in the workout.
    case complementsCompound
    /// A familiar movement the user has logged before (small boost).
    case familiar

    var label: String {
        switch self {
        case .neverLogged: return "New to your log"
        case .restedFor(let days): return "Rested \(days) days"
        case .trainedRecently(let days): return days == 0 ? "Trained today" : "Trained \(days)d ago"
        case .frequentlyUsed(let count): return "Used \(count)× this month"
        case .addsCompound: return "Adds a compound lift"
        case .complementsCompound: return "Complements your compound"
        case .familiar: return "Familiar movement"
        }
    }

    var systemImage: String {
        switch self {
        case .neverLogged: return "sparkle"
        case .restedFor: return "arrow.triangle.2.circlepath"
        case .trainedRecently: return "clock"
        case .frequentlyUsed: return "repeat"
        case .addsCompound: return "square.stack.3d.up"
        case .complementsCompound: return "circle.grid.cross"
        case .familiar: return "checkmark.seal"
        }
    }

    /// Whether the factor argued *for* the exercise. Negative factors are still
    /// surfaced so "why this?" copy stays truthful when a pool is small.
    var isPositive: Bool {
        switch self {
        case .neverLogged, .restedFor, .addsCompound, .complementsCompound, .familiar: return true
        case .trainedRecently, .frequentlyUsed: return false
        }
    }
}

struct ExerciseRecommendation: Identifiable, Equatable, Hashable {
    let template: ExerciseTemplate
    let muscle: Muscle
    /// Bounded relevance in 0...1. Higher is a better fit for this workout.
    let score: Double
    let movementStyle: String
    let factors: [ExerciseRecommendationFactor]

    var id: String { "\(muscle.id)/\(template.id)" }

    /// One line of user-facing copy derived from the strongest positive factor.
    var reason: String {
        if let factor = factors.first(where: \.isPositive) {
            switch factor {
            case .neverLogged: return "A fresh pick you haven't logged yet."
            case .restedFor(let days): return "Back in rotation after \(days) days."
            case .addsCompound: return "Brings a compound lift into this workout."
            case .complementsCompound: return "An isolation move to round out your compound work."
            case .familiar: return "A movement you already know well."
            case .trainedRecently, .frequentlyUsed: break
            }
        }
        return "A solid \(muscle.label.lowercased()) option from your library."
    }
}

/// The outcome of one finder search: what was chosen, what else qualified, and
/// enough context for the UI to explain the pick without guessing.
struct ExerciseFinderResult: Equatable {
    let selected: ExerciseRecommendation
    /// Other qualified candidates, best first, excluding `selected`.
    let alternates: [ExerciseRecommendation]
    /// Size of the full viable pool for the muscle group.
    let poolSize: Int
    /// True when every viable candidate had already been shown and the
    /// rotation started over.
    let cycleRestarted: Bool
}

/// Scores every viable exercise for a muscle group with named, bounded
/// factors. Selection and presentation live elsewhere so this stays a pure
/// function of catalog + history + current workout.
struct ExerciseRecommendationEngine {
    let library: ExerciseLibrary
    let sessions: [WorkoutSession]
    let currentExerciseNames: Set<String>
    var now = Date()

    /// Every viable candidate for the muscle group, best score first. Ties break
    /// alphabetically so the order is stable for identical inputs.
    func candidates(for muscleID: String) -> [ExerciseRecommendation] {
        guard let muscle = library.muscle(muscleID),
              let templates = library.library[muscleID] else { return [] }

        let currentNames = Set(currentExerciseNames.map { $0.lowercased() })
        let usage = usageByExercise()
        let currentHasCompound = library.library.values
            .joined()
            .contains { template in
                currentNames.contains(template.name.lowercased()) && Self.movementStyle(for: template) == "Compound"
            }

        var seen: Set<String> = []
        let scored = templates.compactMap { template -> ExerciseRecommendation? in
            let key = template.name.lowercased()
            guard !key.isEmpty, !currentNames.contains(key), seen.insert(key).inserted else { return nil }

            let style = Self.movementStyle(for: template)
            var factors: [ExerciseRecommendationFactor] = []
            var score = 0.5

            if let lastUsed = usage[key]?.latest {
                let days = daysSince(lastUsed)
                switch days {
                case 0...2:
                    score -= 0.30
                    factors.append(.trainedRecently(days: days))
                case 3...6:
                    score -= 0.12
                    factors.append(.trainedRecently(days: days))
                case 7...13:
                    score += 0.08
                    factors.append(.familiar)
                default:
                    score += 0.22
                    factors.append(.restedFor(days: days))
                }
                let recentCount = usage[key]?.countLast30Days ?? 0
                if recentCount >= 2 {
                    score -= min(0.15, Double(recentCount - 1) * 0.05)
                    factors.append(.frequentlyUsed(count: recentCount))
                }
            } else {
                score += 0.28
                factors.append(.neverLogged)
            }

            if !currentHasCompound && style == "Compound" {
                score += 0.18
                factors.append(.addsCompound)
            } else if currentHasCompound && style == "Isolation" {
                score += 0.10
                factors.append(.complementsCompound)
            }

            return ExerciseRecommendation(
                template: template,
                muscle: muscle,
                score: min(max(score, 0), 1),
                movementStyle: style,
                factors: factors
            )
        }

        return scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.template.name.localizedStandardCompare($1.template.name) == .orderedAscending
        }
    }

    static func movementStyle(for template: ExerciseTemplate) -> String {
        if template.timed { return "Timed" }

        let name = template.name.lowercased()
        let compoundMarkers = [
            "press", "squat", "deadlift", "row", "pull-up", "chin-up",
            "lunge", "dip", "push-up", "step-up", "hip thrust"
        ]
        if compoundMarkers.contains(where: name.contains) { return "Compound" }
        if template.bodyweight { return "Bodyweight" }
        return "Isolation"
    }

    private struct Usage {
        var latest: Date
        var countLast30Days: Int
    }

    private func usageByExercise() -> [String: Usage] {
        let monthAgo = now.addingTimeInterval(-30 * 86_400)
        var usage: [String: Usage] = [:]
        for session in sessions {
            for exercise in session.exercises {
                let key = exercise.name.lowercased()
                let recent = session.createdAt >= monthAgo ? 1 : 0
                if var existing = usage[key] {
                    existing.latest = max(existing.latest, session.createdAt)
                    existing.countLast30Days += recent
                    usage[key] = existing
                } else {
                    usage[key] = Usage(latest: session.createdAt, countLast30Days: recent)
                }
            }
        }
        return usage
    }

    private func daysSince(_ date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(date, now))
        let end = calendar.startOfDay(for: now)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }
}

/// Picks one recommendation from a scored pool with relevance-weighted
/// randomness and a shuffle-bag memory, so repeated searches vary without
/// drifting into irrelevant picks. The random source is injected: tests seed
/// it, the app uses the system generator.
struct ExerciseFinderSelector<Generator: RandomNumberGenerator> {
    /// The qualified pool is the top `poolLimit` candidates whose score sits
    /// within `scoreMargin` of the best one.
    var poolLimit = 5
    var scoreMargin = 0.35
    private(set) var generator: Generator
    /// IDs shown this cycle, oldest first. Cleared when the pool is exhausted.
    private(set) var shownIDs: [String] = []
    private(set) var lastSelectedID: String?

    init(generator: Generator) {
        self.generator = generator
    }

    /// Forget everything shown so far — used when the muscle group changes.
    mutating func reset() {
        shownIDs = []
        lastSelectedID = nil
    }

    /// Choose from `candidates` (best first, as produced by the engine).
    /// Returns nil only for an empty pool.
    mutating func select(from candidates: [ExerciseRecommendation]) -> ExerciseFinderResult? {
        let pool = Self.qualifiedPool(from: candidates, limit: poolLimit, margin: scoreMargin)
        guard !pool.isEmpty else { return nil }

        // Anything shown this cycle is out until the bag empties.
        let poolIDs = Set(pool.map(\.id))
        shownIDs.removeAll { !poolIDs.contains($0) }
        var remaining = pool.filter { !shownIDs.contains($0.id) }
        var restarted = false
        if remaining.isEmpty {
            restarted = true
            shownIDs = []
            // Avoid an immediate repeat unless there's nothing else to show.
            remaining = pool.filter { $0.id != lastSelectedID }
            if remaining.isEmpty { remaining = pool }
        }

        let selected = Self.weightedPick(from: remaining, using: &generator)
        shownIDs.append(selected.id)
        lastSelectedID = selected.id

        return ExerciseFinderResult(
            selected: selected,
            alternates: pool.filter { $0.id != selected.id },
            poolSize: pool.count,
            cycleRestarted: restarted
        )
    }

    /// Promote a specific alternate to the selection (the user tapped it).
    mutating func choose(_ recommendation: ExerciseRecommendation, from candidates: [ExerciseRecommendation]) -> ExerciseFinderResult? {
        let pool = Self.qualifiedPool(from: candidates, limit: poolLimit, margin: scoreMargin)
        guard pool.contains(recommendation) else { return nil }
        if !shownIDs.contains(recommendation.id) { shownIDs.append(recommendation.id) }
        lastSelectedID = recommendation.id
        return ExerciseFinderResult(
            selected: recommendation,
            alternates: pool.filter { $0.id != recommendation.id },
            poolSize: pool.count,
            cycleRestarted: false
        )
    }

    static func qualifiedPool(from candidates: [ExerciseRecommendation], limit: Int, margin: Double) -> [ExerciseRecommendation] {
        guard let best = candidates.first?.score, limit > 0 else { return [] }
        let floor = best - margin
        // Always keep at least three when available so small score gaps don't
        // collapse the finder into a single repeated answer.
        let top = candidates.prefix(limit)
        let withinMargin = top.filter { $0.score >= floor }
        return withinMargin.count >= 3 ? withinMargin : Array(top.prefix(3))
    }

    /// Weighted by score so relevance still tilts the odds. A one-item pool is
    /// returned directly, so the fallback is deterministic.
    private static func weightedPick(from pool: [ExerciseRecommendation], using generator: inout Generator) -> ExerciseRecommendation {
        guard pool.count > 1 else { return pool[0] }
        // Floor at 0.05 so a low-scoring but qualified pick is never impossible.
        let weights = pool.map { max($0.score, 0.05) }
        let total = weights.reduce(0, +)
        var roll = Double.random(in: 0..<total, using: &generator)
        for (index, weight) in weights.enumerated() {
            roll -= weight
            if roll < 0 { return pool[index] }
        }
        return pool[pool.count - 1]
    }
}

/// Small, fast, reproducible generator for tests and previews (SplitMix64).
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
