import Foundation

/// A food that has already passed every hard filter (`FoodRuleEngine`,
/// `EnergyFirewall`). The rotation only ever *reorders* what it is given; it
/// cannot admit anything new, so an excluded food can never re-enter here.
struct ApprovedFood: Equatable, Hashable {
    let id: String
    /// Lowercase cuisine tags from the curated catalog ("indian", "mexican").
    var cuisines: Set<String> = []
    /// Lowercase meal tags ("breakfast", "quick", "high-protein").
    var mealTags: Set<String> = []
    var prepMinutes: Int?
    /// 0 = cheapest tier. Nil when the catalog doesn't say.
    var budgetTier: Int?
}

/// What the user has been served recently, oldest first. Carries the food's
/// tags as they were when served, so a recent meal that isn't in today's
/// pool (yesterday's breakfast while picking dinner) still counts toward
/// "seen this cuisine lately".
struct MealHistoryEntry: Equatable {
    let foodID: String
    let servedAt: Date
    var cuisines: Set<String> = []
    var mealTags: Set<String> = []

    init(foodID: String, servedAt: Date, cuisines: Set<String> = [], mealTags: Set<String> = []) {
        self.foodID = foodID
        self.servedAt = servedAt
        self.cuisines = cuisines
        self.mealTags = mealTags
    }

    init(_ food: ApprovedFood, servedAt: Date) {
        self.init(foodID: food.id, servedAt: servedAt, cuisines: food.cuisines, mealTags: food.mealTags)
    }
}

/// Preferences that must be preserved while rotating. Everything here is a
/// *soft* preference; hard rules were applied before we got the pool.
struct MealVarietyContext: Equatable {
    var preferredCuisines: Set<String> = []
    var requiredMealTags: Set<String> = []
    var maxPrepMinutes: Int?
    var maxBudgetTier: Int?
    var now: Date
    /// Foods served within this window are penalised most.
    var recencyWindowDays = 7
    /// Frequency is counted over this window.
    var frequencyWindowDays = 30
}

/// Deterministic variety over an approved pool: recency and frequency
/// penalties, a bonus for cuisines/tags not seen lately, and a stable
/// tie-break, so the same inputs always produce the same order while
/// repeated identical requests (with history advancing) don't.
enum MealVarietyRotation {
    struct Scored: Equatable {
        let food: ApprovedFood
        let score: Double
        let factors: [Factor]
    }

    enum Factor: Equatable {
        case servedRecently(daysAgo: Int)
        case servedOften(count: Int)
        case freshCuisine
        case freshMealTag
        case preferredCuisine
        case withinPrepTime
        case withinBudget
        case overPrepTime
        case overBudget
        case neverServed
    }

    /// The approved pool ordered for variety, best first. Never adds, never
    /// removes: `result.map(\.food)` is a permutation of `pool`.
    static func rotate(
        pool: [ApprovedFood],
        history: [MealHistoryEntry],
        context: MealVarietyContext
    ) -> [Scored] {
        // Small pools have nothing to rotate; keep them stable.
        guard pool.count > 1 else {
            return pool.map { Scored(food: $0, score: 1, factors: factorsForTrivial($0, history: history)) }
        }

        let usage = usageByFood(history: history, context: context)
        let recentCuisines = recentTags(history: history, pool: pool, context: context, keyPath: \.cuisines)
        let recentMealTags = recentTags(history: history, pool: pool, context: context, keyPath: \.mealTags)

        // Dedupe by id so a duplicated entry can't double its odds.
        var seen: Set<String> = []
        let scored = pool.compactMap { food -> Scored? in
            guard seen.insert(food.id).inserted else { return nil }
            var score = 1.0
            var factors: [Factor] = []

            if let use = usage[food.id] {
                let days = use.daysSinceLast
                if days <= context.recencyWindowDays {
                    // Yesterday hurts more than a week ago.
                    score -= 0.6 * (1 - Double(days) / Double(context.recencyWindowDays + 1))
                    factors.append(.servedRecently(daysAgo: days))
                }
                if use.count >= 2 {
                    score -= min(0.3, Double(use.count - 1) * 0.1)
                    factors.append(.servedOften(count: use.count))
                }
            } else {
                score += 0.2
                factors.append(.neverServed)
            }

            if !food.cuisines.isEmpty, food.cuisines.isDisjoint(with: recentCuisines) {
                score += 0.15
                factors.append(.freshCuisine)
            }
            if !food.mealTags.isEmpty, food.mealTags.isDisjoint(with: recentMealTags) {
                score += 0.1
                factors.append(.freshMealTag)
            }
            if !context.preferredCuisines.isEmpty, !food.cuisines.isDisjoint(with: context.preferredCuisines) {
                score += 0.25
                factors.append(.preferredCuisine)
            }
            if let limit = context.maxPrepMinutes, let prep = food.prepMinutes {
                if prep <= limit {
                    score += 0.1
                    factors.append(.withinPrepTime)
                } else {
                    score -= 0.4
                    factors.append(.overPrepTime)
                }
            }
            if let limit = context.maxBudgetTier, let tier = food.budgetTier {
                if tier <= limit {
                    score += 0.05
                    factors.append(.withinBudget)
                } else {
                    score -= 0.3
                    factors.append(.overBudget)
                }
            }
            if !context.requiredMealTags.isEmpty, !context.requiredMealTags.isSubset(of: food.mealTags) {
                score -= 0.5
            }

            return Scored(food: food, score: (score * 1000).rounded() / 1000, factors: factors)
        }

        return scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            // Stable, deterministic tie-break: the food served longest ago wins,
            // then the id. Never the input order, so catalog position can't
            // silently pin a favourite.
            let a = usage[$0.food.id]?.daysSinceLast ?? Int.max
            let b = usage[$1.food.id]?.daysSinceLast ?? Int.max
            if a != b { return a > b }
            return $0.food.id < $1.food.id
        }
    }

    // MARK: - Helpers

    private struct Usage {
        var daysSinceLast: Int
        var count: Int
    }

    private static func usageByFood(history: [MealHistoryEntry], context: MealVarietyContext) -> [String: Usage] {
        let windowStart = context.now.addingTimeInterval(-Double(context.frequencyWindowDays) * 86_400)
        var usage: [String: Usage] = [:]
        for entry in history where entry.servedAt <= context.now {
            let days = daysBetween(entry.servedAt, context.now)
            let counts = entry.servedAt >= windowStart ? 1 : 0
            if var existing = usage[entry.foodID] {
                existing.daysSinceLast = min(existing.daysSinceLast, days)
                existing.count += counts
                usage[entry.foodID] = existing
            } else {
                usage[entry.foodID] = Usage(daysSinceLast: days, count: counts)
            }
        }
        return usage
    }

    /// Tags of anything served inside the recency window: the entry's own
    /// snapshot, plus the pool's tags for the same id in case the entry was
    /// recorded without them.
    private static func recentTags(
        history: [MealHistoryEntry],
        pool: [ApprovedFood],
        context: MealVarietyContext,
        keyPath: KeyPath<ApprovedFood, Set<String>>
    ) -> Set<String> {
        let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let cutoff = context.now.addingTimeInterval(-Double(context.recencyWindowDays) * 86_400)
        var tags: Set<String> = []
        for entry in history where entry.servedAt >= cutoff && entry.servedAt <= context.now {
            tags.formUnion(keyPath == \.cuisines ? entry.cuisines : entry.mealTags)
            if let food = byID[entry.foodID] { tags.formUnion(food[keyPath: keyPath]) }
        }
        return tags
    }

    private static func factorsForTrivial(_ food: ApprovedFood, history: [MealHistoryEntry]) -> [Factor] {
        history.contains { $0.foodID == food.id } ? [] : [.neverServed]
    }

    private static func daysBetween(_ from: Date, _ to: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }
}
