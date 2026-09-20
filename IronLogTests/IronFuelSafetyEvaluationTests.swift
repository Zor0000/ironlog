import XCTest
@testable import IronLog

/// Evaluation suite for the LLM-assisted Fuel Buddy path. It replays fixture
/// requests and fixture model outputs through the real client boundary —
/// `FuelBuddyGate` with a spy provider — and asserts the safety contract
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
        struct Override: Decodable { let maxFoods: Int?; let maxResponseBytes: Int? }
        struct Case: Decodable {
            let id: String
            let expect: String
            let body: String?
            let provider: String?
            let rulesReject: [String]?
            let requestOverride: Override?
        }
        let candidates: [FuelBuddyCandidate]
        let cases: [Case]
    }

    private func load<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "missing fixture \(name).json")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private let requestID = UUID(uuidString: "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10")!

    private func request(text: String = "indian vegetarian dinner", candidates: [FuelBuddyCandidate], override: ModelOutputFixture.Override? = nil) -> FuelBuddyPresentationRequest {
        FuelBuddyPresentationRequest(
            policyVersion: FuelBuddySafetyPolicy.version,
            requestID: requestID,
            userText: FuelBuddyRequestRedactor.redact(text),
            mealContext: FuelBuddyMealContext(mealType: .dinner, cuisines: ["indian"]),
            profileContext: FuelBuddyProfileContext(ruleTags: ["vegetarian", "no-peanut"]),
            candidates: candidates,
            limits: FuelBuddyRequestLimits(
                timeoutMilliseconds: 50,
                maxResponseBytes: override?.maxResponseBytes ?? 8192,
                maxFoods: override?.maxFoods ?? 3
            )
        )
    }

    /// Replays a fixture body or simulates a transport failure, and counts
    /// how often it was reached.
    private final class FixtureProvider: FuelBuddyLLMProvider, @unchecked Sendable {
        let mode: String?
        let body: Data
        private(set) var calls = 0

        init(mode: String?, body: Data) {
            self.mode = mode
            self.body = body
        }

        func send(_ request: FuelBuddyPresentationRequest) async throws -> Data { try await respond() }
        func send(_ request: FuelBuddyIntentRequest) async throws -> Data { try await respond() }

        private func respond() async throws -> Data {
            calls += 1
            switch mode {
            case "timeout":
                try await Task.sleep(for: .seconds(5))
                return body
            case "hang":
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                return body
            case "rateLimited": throw FuelBuddyProviderError.rateLimited
            case "unavailable": throw FuelBuddyProviderError.unavailable
            default: return body
            }
        }
    }

    private var validBody: Data {
        Data("""
        {"schemaVersion":1,"requestID":"\(requestID.uuidString)","status":"ok","foods":[{"foodID":"chana-masala","rationaleFacts":[]}],"explanation":"","tradeOffs":[],"declineReason":null}
        """.utf8)
    }

    // MARK: Request-side policy

    func testFixturePolicyVersionMatchesTheShippedPolicy() throws {
        let fixture: RequestFixture = try load("fuel-buddy-requests")
        XCTAssertEqual(fixture.policyVersion, FuelBuddySafetyPolicy.version, "bump the fixture when the policy changes so evaluations stay comparable")
    }

    func testEveryRequestFixtureScreensAsDocumented() throws {
        let fixture: RequestFixture = try load("fuel-buddy-requests")
        XCTAssertGreaterThanOrEqual(fixture.cases.count, 40)

        for testCase in fixture.cases {
            let verdict = FuelBuddySafetyPolicy.screen(request: testCase.text)
            XCTAssertEqual(describe(verdict), testCase.expect, "case \(testCase.id): \"\(testCase.text)\"")
        }
    }

    func testRequestFixturesCoverEveryBlockAndRoutingReason() throws {
        let fixture: RequestFixture = try load("fuel-buddy-requests")
        let expectations = Set(fixture.cases.map(\.expect))
        for block in FuelBuddySafetyPolicy.BlockReason.allCases {
            XCTAssertTrue(expectations.contains("blocked:\(block.rawValue)"), "no fixture for \(block)")
        }
        for route in FuelBuddySafetyPolicy.RoutingReason.allCases {
            XCTAssertTrue(expectations.contains("routed:\(route.rawValue)"), "no fixture for \(route)")
        }
        XCTAssertGreaterThanOrEqual(fixture.cases.filter { $0.expect == "allowed" }.count, 5, "benign cases keep the policy from being 'reject everything'")
    }

    /// The real boundary: every fixture goes through `FuelBuddyGate` with a
    /// provider that would happily answer. Unsafe ones must never reach it;
    /// allowed ones must.
    func testUnsafeRequestsNeverReachTheProviderThroughTheGate() async throws {
        let fixture: RequestFixture = try load("fuel-buddy-requests")
        let candidates: [FuelBuddyCandidate] = [FuelBuddyCandidate(foodID: "chana-masala", displayName: "Chana Masala", facts: ["cuisine:indian"])]

        for testCase in fixture.cases {
            let spy = FixtureProvider(mode: nil, body: validBody)
            let gate = FuelBuddyGate(provider: spy)
            let answer = await gate.presentation(request: request(text: testCase.text, candidates: candidates), local: "local", passesCurrentRules: { _ in true })

            switch testCase.expect {
            case "allowed":
                XCTAssertEqual(spy.calls, 1, "\(testCase.id): allowed requests should reach the provider")
                if case .local(let diagnostic) = answer.source { XCTFail("\(testCase.id): expected model answer, got \(String(describing: diagnostic))") }
            case let expectation where expectation.hasPrefix("blocked:"):
                XCTAssertEqual(spy.calls, 0, "\(testCase.id) reached the provider")
                guard case .local(.blockedByPolicy(let reason)?) = answer.source else { return XCTFail("\(testCase.id): expected blocked, got \(answer.source)") }
                XCTAssertEqual("blocked:\(reason.rawValue)", expectation, testCase.id)
            case let expectation where expectation.hasPrefix("routed:"):
                XCTAssertEqual(spy.calls, 0, "\(testCase.id) reached the provider")
                guard case .local(.routedByPolicy(let reason)?) = answer.source else { return XCTFail("\(testCase.id): expected routed, got \(answer.source)") }
                XCTAssertEqual("routed:\(reason.rawValue)", expectation, testCase.id)
            default:
                XCTFail("\(testCase.id): unknown expectation \(testCase.expect)")
            }
            XCTAssertEqual(answer.local, "local", testCase.id)
        }
    }

    func testSensitiveDetailsAreRedactedBeforeTheProviderSeesThem() async {
        final class Capture: FuelBuddyLLMProvider, @unchecked Sendable {
            var seen: String?
            let body: Data
            init(body: Data) { self.body = body }
            func send(_ request: FuelBuddyPresentationRequest) async throws -> Data { seen = request.userText.value; return body }
            func send(_ request: FuelBuddyIntentRequest) async throws -> Data { seen = request.userText.value; return body }
        }
        let capture = Capture(body: validBody)
        let candidates: [FuelBuddyCandidate] = [FuelBuddyCandidate(foodID: "chana-masala", displayName: "Chana Masala", facts: [])]
        let text = "I'm jane@example.com, 90 kg, on +44 7911 123456 — quick lunch?"

        _ = await FuelBuddyGate(provider: capture).presentation(request: request(text: text, candidates: candidates), local: "local", passesCurrentRules: { _ in true })

        let seen = capture.seen ?? ""
        XCTAssertFalse(seen.contains("jane@example.com"))
        XCTAssertFalse(seen.contains("90 kg"))
        XCTAssertFalse(seen.contains("7911"))
        XCTAssertTrue(seen.contains("quick lunch"))
    }

    // MARK: Model-output guardrails

    func testEveryModelOutputFixtureResolvesAsDocumented() async throws {
        let fixture: ModelOutputFixture = try load("fuel-buddy-model-outputs")
        XCTAssertGreaterThanOrEqual(fixture.cases.count, 35)

        for testCase in fixture.cases {
            let body = Data((testCase.body ?? "").replacingOccurrences(of: "REQ", with: requestID.uuidString).utf8)
            let provider = FixtureProvider(mode: testCase.provider, body: body)
            let gate = FuelBuddyGate(provider: provider)
            let rejected = Set(testCase.rulesReject ?? [])
            let answer = await gate.presentation(
                request: request(candidates: fixture.candidates, override: testCase.requestOverride),
                local: "local-answer",
                passesCurrentRules: { !rejected.contains($0) }
            )

            XCTAssertEqual(describe(answer), testCase.expect, "case \(testCase.id)")
            XCTAssertEqual(answer.local, "local-answer", "case \(testCase.id): the local answer is always available")
        }
    }

    func testHallucinatedFoodsAndFactsNeverReachTheUser() async throws {
        let fixture: ModelOutputFixture = try load("fuel-buddy-model-outputs")
        let approvedFacts = Dictionary(uniqueKeysWithValues: fixture.candidates.map { ($0.foodID, Set($0.facts)) })
        let order = fixture.candidates.map(\.foodID)

        for testCase in fixture.cases where testCase.body != nil {
            let body = Data(testCase.body!.replacingOccurrences(of: "REQ", with: requestID.uuidString).utf8)
            let gate = FuelBuddyGate(provider: FixtureProvider(mode: nil, body: body))
            let rejected = Set(testCase.rulesReject ?? [])
            let answer = await gate.presentation(
                request: request(candidates: fixture.candidates, override: testCase.requestOverride),
                local: "local",
                passesCurrentRules: { !rejected.contains($0) }
            )

            guard case .model(let validated) = answer.source else { continue }
            // Order is the deterministic order; nothing skipped or added.
            XCTAssertEqual(validated.foods.map(\.foodID), Array(order.prefix(validated.foods.count)), testCase.id)
            for food in validated.foods {
                XCTAssertFalse(rejected.contains(food.foodID), "\(testCase.id): \(food.foodID) fails current rules")
                XCTAssertTrue(Set(food.rationaleFacts).isSubset(of: approvedFacts[food.foodID] ?? []), "\(testCase.id): rationale cites an unapproved fact")
                XCTAssertTrue(Set(food.tradeOffFacts).isSubset(of: approvedFacts[food.foodID] ?? []), "\(testCase.id): trade-off cites an unapproved fact")
                XCTAssertEqual(food.displayName, fixture.candidates.first { $0.foodID == food.foodID }?.displayName, "\(testCase.id): names come from the catalog")
            }
            XCTAssertFalse(FuelBuddySafetyPolicy.containsForbiddenLanguage(validated.explanation), testCase.id)
        }
    }

    func testModelOutputFixturesCoverEveryFailureCategory() throws {
        let fixture: ModelOutputFixture = try load("fuel-buddy-model-outputs")
        let codes = Set(fixture.cases.map(\.expect))
        let required: [FuelBuddyDiagnostic] = [
            .modelDeclined, .inconsistentStatus, .unknownFoodID, .duplicateFoodID, .orderMismatch, .tooManyFoods(count: 0),
            .foodFailsCurrentRules, .unapprovedFact, .forbiddenLanguage, .textTooLong, .schemaVersionMismatch(received: 0),
            .requestIDMismatch, .malformedJSON, .responseTooLarge(bytes: 0), .providerTimeout, .providerRateLimited, .providerUnavailable
        ]
        for diagnostic in required {
            XCTAssertTrue(codes.contains("local:\(diagnostic.code)"), "no fixture resolves to \(diagnostic.code)")
        }
        XCTAssertTrue(codes.contains("model"), "at least one fixture must be accepted, or the guardrails are just 'reject everything'")
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

    func testNoProviderMeansNoNetworkAndAStillUsableAnswer() async {
        // With no provider configured nothing can leave the device and the
        // local answer is returned; with a provider, only the gate calls it.
        let candidates: [FuelBuddyCandidate] = [FuelBuddyCandidate(foodID: "chana-masala", displayName: "Chana Masala", facts: [])]
        let answer = await FuelBuddyGate(provider: nil).presentation(request: request(candidates: candidates), local: "local", passesCurrentRules: { _ in true })
        XCTAssertEqual(answer.source, .local(.providerUnavailable))
        XCTAssertEqual(answer.local, "local")
    }

    // MARK: Helpers

    private func describe(_ verdict: FuelBuddySafetyPolicy.Verdict) -> String {
        switch verdict {
        case .allowed: return "allowed"
        case .blocked(let reason): return "blocked:\(reason.rawValue)"
        case .routed(let reason): return "routed:\(reason.rawValue)"
        }
    }

    private func describe(_ answer: FuelBuddyAnswer<FuelBuddyValidatedPresentation, String>) -> String {
        switch answer.source {
        case .model: return "model"
        case .local(let diagnostic): return "local:\(diagnostic?.code ?? "none")"
        }
    }
}
