import XCTest
@testable import IronLog

final class MealVarietyRotationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func food(_ id: String, cuisines: Set<String> = [], tags: Set<String> = [], prep: Int? = nil, budget: Int? = nil) -> ApprovedFood {
        ApprovedFood(id: id, cuisines: cuisines, mealTags: tags, prepMinutes: prep, budgetTier: budget)
    }

    private func served(_ id: String, daysAgo: Int) -> MealHistoryEntry {
        MealHistoryEntry(foodID: id, servedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400))
    }

    private func context(_ configure: (inout MealVarietyContext) -> Void = { _ in }) -> MealVarietyContext {
        var context = MealVarietyContext(now: now)
        configure(&context)
        return context
    }

    func testEmptyPoolStaysEmpty() {
        XCTAssertEqual(MealVarietyRotation.rotate(pool: [], history: [served("x", daysAgo: 1)], context: context()), [])
    }

    func testSingleCandidateIsReturnedUnchangedEvenIfServedYesterday() {
        let only = food("dal-tadka")
        let result = MealVarietyRotation.rotate(pool: [only], history: [served("dal-tadka", daysAgo: 1)], context: context())
        XCTAssertEqual(result.map(\.food), [only])
        XCTAssertEqual(result.first?.score, 1)
    }

    func testRepeatedHistoryPushesTheFoodDown() {
        let pool = [food("dal-tadka"), food("chana-masala"), food("vegetable-pulao")]
        let history = [served("dal-tadka", daysAgo: 1), served("dal-tadka", daysAgo: 3), served("dal-tadka", daysAgo: 5)]

        let result = MealVarietyRotation.rotate(pool: pool, history: history, context: context())

        XCTAssertEqual(result.last?.food.id, "dal-tadka")
        XCTAssertTrue(result.last!.factors.contains(.servedRecently(daysAgo: 1)))
        XCTAssertTrue(result.last!.factors.contains(.servedOften(count: 3)))
        XCTAssertTrue(result.first!.factors.contains(.neverServed))
    }

    func testIdenticalRequestsRotateAsHistoryAdvances() {
        let pool = [food("a"), food("b"), food("c")]
        var history: [MealHistoryEntry] = []
        var served: [String] = []

        // Serve the top pick each day and record it; every food should get a
        // turn before anything repeats.
        for day in 0..<3 {
            let context = MealVarietyContext(now: now.addingTimeInterval(Double(day) * 86_400))
            let top = MealVarietyRotation.rotate(pool: pool, history: history, context: context).first!.food.id
            served.append(top)
            history.append(MealHistoryEntry(foodID: top, servedAt: context.now))
        }

        XCTAssertEqual(Set(served), Set(["a", "b", "c"]))
    }

    func testOutputIsAPermutationOfThePoolAndNothingElse() {
        let pool = [food("a"), food("b"), food("c"), food("d")]
        let history = [served("z-excluded", daysAgo: 1), served("a", daysAgo: 2)]

        let result = MealVarietyRotation.rotate(pool: pool, history: history, context: context())

        XCTAssertEqual(Set(result.map(\.food.id)), Set(pool.map(\.id)))
        XCTAssertEqual(result.count, pool.count)
        XCTAssertFalse(result.contains { $0.food.id == "z-excluded" }, "history cannot re-admit a filtered food")
    }

    func testDuplicatePoolEntriesAreCollapsed() {
        let result = MealVarietyRotation.rotate(pool: [food("a"), food("a"), food("b")], history: [], context: context())
        XCTAssertEqual(result.map(\.food.id).sorted(), ["a", "b"])
    }

    func testSameInputsAlwaysGiveTheSameOrder() {
        let pool = [food("a", cuisines: ["indian"]), food("b", cuisines: ["mexican"]), food("c", cuisines: ["thai"]), food("d")]
        let history = [served("b", daysAgo: 2), served("c", daysAgo: 9), served("a", daysAgo: 20)]
        let context = context { $0.preferredCuisines = ["thai"] }

        let first = MealVarietyRotation.rotate(pool: pool, history: history, context: context)
        for _ in 0..<5 {
            XCTAssertEqual(MealVarietyRotation.rotate(pool: pool.reversed(), history: history, context: context), first, "input order must not matter")
        }
    }

    func testFreshCuisineAndMealTagEarnABonus() {
        let pool = [food("curry", cuisines: ["indian"], tags: ["dinner"]), food("tacos", cuisines: ["mexican"], tags: ["dinner"]), food("pho", cuisines: ["vietnamese"], tags: ["soup"])]
        let history = [served("curry", daysAgo: 1)]

        let result = MealVarietyRotation.rotate(pool: pool, history: history, context: context())
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.food.id, $0) })

        XCTAssertTrue(byID["tacos"]!.factors.contains(.freshCuisine))
        XCTAssertFalse(byID["tacos"]!.factors.contains(.freshMealTag), "dinner was seen yesterday")
        XCTAssertTrue(byID["pho"]!.factors.contains(.freshMealTag))
        XCTAssertEqual(result.first?.food.id, "pho")
    }

    func testRecentFoodOutsideThePoolStillCountsAsSeenCuisine() {
        // Yesterday's breakfast was Indian; today's dinner pool doesn't contain
        // it, but Indian must not be treated as fresh.
        let pool = [food("curry", cuisines: ["indian"]), food("tacos", cuisines: ["mexican"])]
        let breakfast = ApprovedFood(id: "masala-oats", cuisines: ["indian"], mealTags: ["breakfast"])
        let history = [MealHistoryEntry(breakfast, servedAt: now.addingTimeInterval(-86_400))]

        let result = MealVarietyRotation.rotate(pool: pool, history: history, context: context())
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.food.id, $0) })

        XCTAssertFalse(byID["curry"]!.factors.contains(.freshCuisine))
        XCTAssertTrue(byID["tacos"]!.factors.contains(.freshCuisine))
        XCTAssertEqual(result.first?.food.id, "tacos")
    }

    func testHistoryWithoutTagsFallsBackToThePoolsTags() {
        let pool = [food("curry", cuisines: ["indian"]), food("tacos", cuisines: ["mexican"])]
        let history = [served("curry", daysAgo: 1)] // legacy entry, no snapshot
        let result = MealVarietyRotation.rotate(pool: pool, history: history, context: context())
        XCTAssertFalse(result.first(where: { $0.food.id == "curry" })!.factors.contains(.freshCuisine))
    }

    func testPreferencesPrepTimeAndBudgetArePreserved() {
        let pool = [
            food("slow-roast", cuisines: ["british"], prep: 90, budget: 2),
            food("quick-wrap", cuisines: ["mexican"], prep: 10, budget: 0),
            food("pad-thai", cuisines: ["thai"], prep: 20, budget: 1)
        ]
        let context = context {
            $0.preferredCuisines = ["thai"]
            $0.maxPrepMinutes = 25
            $0.maxBudgetTier = 1
        }

        let result = MealVarietyRotation.rotate(pool: pool, history: [], context: context)

        XCTAssertEqual(result.first?.food.id, "pad-thai")
        XCTAssertTrue(result.first!.factors.contains(.preferredCuisine))
        XCTAssertEqual(result.last?.food.id, "slow-roast")
        XCTAssertTrue(result.last!.factors.contains(.overPrepTime))
        XCTAssertTrue(result.last!.factors.contains(.overBudget))
    }

    func testTieBreakPrefersTheFoodServedLongestAgoThenID() {
        let pool = [food("b"), food("a"), food("c")]
        let history = [served("a", daysAgo: 10), served("b", daysAgo: 12), served("c", daysAgo: 12)]

        let result = MealVarietyRotation.rotate(pool: pool, history: history, context: context())

        XCTAssertEqual(result.map(\.food.id), ["b", "c", "a"])
    }

    func testFutureDatedHistoryIsIgnored() {
        let pool = [food("a"), food("b")]
        let history = [MealHistoryEntry(foodID: "a", servedAt: now.addingTimeInterval(86_400))]
        let result = MealVarietyRotation.rotate(pool: pool, history: history, context: context())
        XCTAssertTrue(result.allSatisfy { $0.factors.contains(.neverServed) })
    }
}
