import XCTest
@testable import IronLog

/// Evaluation suite for the LLM-assisted Fuel Buddy path. It replays fixture
/// requests through `FuelBuddySafetyPolicy` and fixture model outputs through
/// `FuelBuddyGate` (validator + fallback) and asserts the safety contract
/// holds regardless of what a model might say. No provider, no credentials.
///
/// Fixtures: `IronLogTests/Fixtures/IronFuel/*.json` — see
/// `docs/ironfuel/safety-evaluation.md` for how to add cases and how to
/// evaluate a new model/provider against them.
final class IronFuelSafetyEvaluationTests: XCTestCase {
    // MARK: Fixtures

    private struct RequestFixture: Decodable {
        struct Case: Decodable { let id: String; let text: String; let expect: String }
        let policyVersion: String
        let cases: [Case]
    }

    private struct ModelOutputFixture: Decodable {
        struct Case: Decodable {
            let id: String
            let expect: String
            let body: String?
            let provider: String?
            let rulesReject: [String]?
        }
        let candidateFoodIDs: [String]
        let cases: [Case]
    }

    private func load<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "missing fixture \(name).json")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private let requestID = UUID(uuidString: "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10")!

    private func request(candidates: [String]) -> FuelBuddyLLMRequest {
        FuelBuddyLLMRequest(
            policyVersion: FuelBuddySafetyPolicy.version,
            requestID: requestID,
            stage: .presentation,
            userText: "indian vegetarian dinner",
            mealContext: FuelBuddyMealContext(mealType: .dinner, cuisines: ["indian"]),
            profileContext: FuelBuddyProfileContext(ruleTags: ["vegetarian", "no-peanut"]),
            candidateFoodIDs: candidates,
            limits: FuelBuddyRequestLimits(timeoutMilliseconds: 50, maxResponseBytes: 8192, maxFoods: 3)
        )
    }

    private struct FixtureProvider: FuelBuddyLLMProvider {
        let mode: String?
        let body: Data
        func send(_ request: FuelBuddyLLMRequest) async throws -> Data {
            switch mode {
            case "timeout":
                try await Task.sleep(for: .seconds(5))
                return body
            case "rateLimited": throw FuelBuddyProviderError.rateLimited
            case "unavailable": throw FuelBuddyProviderError.unavailable
            default: return body
            }
        }
    }

    // MARK: Request-side policy

    func testFixturePolicyVersionMatchesTheShippedPolicy() throws {
        let fixture: RequestFixture = try load("fuel-buddy-requests")
        XCTAssertEqual(fixture.policyVersion, FuelBuddySafetyPolicy.version, "bump the fixture when the policy changes so evaluations stay comparable")
    }

    func testEveryRequestFixtureScreensAsDocumented() throws {
        let fixture: RequestFixture = try load("fuel-buddy-requests")
        XCTAssertGreaterThanOrEqual(fixture.cases.count, 25)

        for testCase in fixture.cases {
            let verdict = FuelBuddySafetyPolicy.screen(request: testCase.text)
            XCTAssertEqual(describe(verdict), testCase.expect, "case \(testCase.id): \"\(testCase.text)\"")
        }
    }

    func testRequestFixturesCoverEveryBlockAndRoutingReason() throws {
        let fixture: RequestFixture = try load("fuel-buddy-requests")
        let expectations = Set(fixture.cases.map(\.expect))
        let blocks: [FuelBuddySafetyPolicy.BlockReason] = [.supplementsOrSteroids, .diagnosisOrTreatment, .crashDietOrCompensation, .allergyBypass, .dietaryRuleBypass]
        let routes: [FuelBuddySafetyPolicy.RoutingReason] = [.under18, .pregnancyOrBreastfeeding, .disorderedEating, .clinicianManagedDiet]
        for block in blocks { XCTAssertTrue(expectations.contains("blocked:\(block.rawValue)"), "no fixture for \(block)") }
        for route in routes { XCTAssertTrue(expectations.contains("routed:\(route.rawValue)"), "no fixture for \(route)") }
        XCTAssertTrue(expectations.contains("allowed"))
    }

    func testUnsafeRequestsNeverReachTheModel() throws {
        // The gate is only ever called with a request that passed the
        // policy; here we prove the policy alone stops every unsafe fixture,
        // without any provider being involved.
        let fixture: RequestFixture = try load("fuel-buddy-requests")
        for testCase in fixture.cases where testCase.expect != "allowed" {
            if case .allowed = FuelBuddySafetyPolicy.screen(request: testCase.text) {
                XCTFail("\(testCase.id) reached the model path")
            }
        }
    }

    // MARK: Model-output guardrails

    func testEveryModelOutputFixtureResolvesAsDocumented() async throws {
        let fixture: ModelOutputFixture = try load("fuel-buddy-model-outputs")
        XCTAssertGreaterThanOrEqual(fixture.cases.count, 20)
        let request = request(candidates: fixture.candidateFoodIDs)

        for testCase in fixture.cases {
            let body = Data((testCase.body ?? "").replacingOccurrences(of: "REQ", with: requestID.uuidString).utf8)
            let gate = FuelBuddyGate<String>(provider: FixtureProvider(mode: testCase.provider, body: body))
            let rejected = Set(testCase.rulesReject ?? [])
            let answer = await gate.answer(request: request, local: "local-answer", passesCurrentRules: { !rejected.contains($0) })

            XCTAssertEqual(describe(answer), testCase.expect, "case \(testCase.id)")
            XCTAssertEqual(answer.local, "local-answer", "case \(testCase.id): the local answer is always available")
        }
    }

    func testHallucinatedFoodsAndFactsNeverReachTheUser() async throws {
        let fixture: ModelOutputFixture = try load("fuel-buddy-model-outputs")
        let approved = Set(fixture.candidateFoodIDs)
        let request = request(candidates: fixture.candidateFoodIDs)

        for testCase in fixture.cases where testCase.body != nil {
            let body = Data(testCase.body!.replacingOccurrences(of: "REQ", with: requestID.uuidString).utf8)
            let gate = FuelBuddyGate<String>(provider: FixtureProvider(mode: nil, body: body))
            let rejected = Set(testCase.rulesReject ?? [])
            let answer = await gate.answer(request: request, local: "local", passesCurrentRules: { !rejected.contains($0) })

            guard case .model(let validated) = answer.source, case .foods(let foods, let explanation, let tradeOffs) = validated.outcome else { continue }
            for food in foods {
                XCTAssertTrue(approved.contains(food.foodID), "\(testCase.id): \(food.foodID) is not approved")
                XCTAssertFalse(rejected.contains(food.foodID), "\(testCase.id): \(food.foodID) fails current rules")
                XCTAssertFalse(FuelBuddySafetyPolicy.containsForbiddenLanguage(food.rationale), testCase.id)
            }
            XCTAssertFalse(FuelBuddySafetyPolicy.containsForbiddenLanguage(explanation), testCase.id)
            XCTAssertTrue(tradeOffs.allSatisfy { !FuelBuddySafetyPolicy.containsForbiddenLanguage($0) }, testCase.id)
        }
    }

    func testModelOutputFixturesCoverEveryFailureCategory() throws {
        let fixture: ModelOutputFixture = try load("fuel-buddy-model-outputs")
        let codes = Set(fixture.cases.map(\.expect))
        for required in [
            "model",
            "local:unknown_food_id", "local:forbidden_language", "local:food_fails_current_rules",
            "local:schema_version_mismatch", "local:malformed_json", "local:inconsistent_status", "local:too_many_foods",
            "local:provider_timeout", "local:provider_rate_limited", "local:provider_unavailable"
        ] {
            XCTAssertTrue(codes.contains(required), "no fixture resolves to \(required)")
        }
    }

    // MARK: Deterministic layers stay provider-independent

    func testVarietyRotationCannotReintroduceAFilteredFood() {
        // History mentions a food the rule engine has excluded from the pool;
        // the rotation must not resurrect it.
        let pool = [ApprovedFood(id: "chana-masala"), ApprovedFood(id: "vegetable-pulao")]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let history = [
            MealHistoryEntry(foodID: "peanut-satay", servedAt: now.addingTimeInterval(-86_400)),
            MealHistoryEntry(foodID: "chana-masala", servedAt: now.addingTimeInterval(-2 * 86_400))
        ]
        let rotated = MealVarietyRotation.rotate(pool: pool, history: history, context: MealVarietyContext(now: now))
        XCTAssertEqual(Set(rotated.map(\.food.id)), ["chana-masala", "vegetable-pulao"])
    }

    func testPolicyAndValidatorNeedNoNetworkOrCredentials() {
        // Sanity: both are pure functions of their inputs.
        XCTAssertEqual(FuelBuddySafetyPolicy.screen(request: "quick lunch"), .allowed)
        XCTAssertFalse(FuelBuddySafetyPolicy.containsForbiddenLanguage("a light, quick option"))
        XCTAssertTrue(FuelBuddySafetyPolicy.containsForbiddenLanguage("about 300 kcal"))
        XCTAssertNil(ProcessInfo.processInfo.environment["FUEL_BUDDY_PROVIDER_KEY"], "evaluation must not depend on a provider secret")
    }

    // MARK: Helpers

    private func describe(_ verdict: FuelBuddySafetyPolicy.Verdict) -> String {
        switch verdict {
        case .allowed: return "allowed"
        case .blocked(let reason): return "blocked:\(reason.rawValue)"
        case .routed(let reason): return "routed:\(reason.rawValue)"
        }
    }

    private func describe(_ answer: FuelBuddyAnswer<String>) -> String {
        switch answer.source {
        case .model: return "model"
        case .local(let diagnostic): return "local:\(diagnostic?.code ?? "none")"
        }
    }
}
