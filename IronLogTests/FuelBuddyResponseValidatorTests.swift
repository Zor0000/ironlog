import XCTest
@testable import IronLog

final class FuelBuddyResponseValidatorTests: XCTestCase {
    private let requestID = UUID(uuidString: "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10")!

    private func request(candidates: [String] = ["chana-masala", "vegetable-pulao", "palak-paneer"], maxFoods: Int = 3, maxBytes: Int = 8192) -> FuelBuddyLLMRequest {
        FuelBuddyLLMRequest(
            policyVersion: FuelBuddySafetyPolicy.version,
            requestID: requestID,
            stage: .presentation,
            userText: "indian vegetarian dinner",
            mealContext: FuelBuddyMealContext(mealType: .dinner, cuisines: ["indian"]),
            profileContext: FuelBuddyProfileContext(ruleTags: ["vegetarian"]),
            candidateFoodIDs: candidates,
            limits: FuelBuddyRequestLimits(timeoutMilliseconds: 50, maxResponseBytes: maxBytes, maxFoods: maxFoods)
        )
    }

    private func context(_ request: FuelBuddyLLMRequest, rules: @escaping (String) -> Bool = { _ in true }) -> FuelBuddyValidationContext {
        FuelBuddyValidationContext(request: request, passesCurrentRules: rules)
    }

    private func json(_ body: String) -> Data {
        Data(body.replacingOccurrences(of: "REQ", with: requestID.uuidString).utf8)
    }

    private let validBody = """
    { "schemaVersion": 1, "requestID": "REQ", "status": "ok",
      "foods": [{ "foodID": "chana-masala", "rationale": "quick and different from the dal" },
                { "foodID": "vegetable-pulao", "rationale": "fresh cuisine this week" }],
      "explanation": "Two quick vegetarian dinners.", "tradeOffs": ["Pulao needs the full 20 minutes."],
      "refusalReason": null }
    """

    // MARK: Accepts

    func testValidResponseIsAccepted() throws {
        let result = FuelBuddyResponseValidator.validate(data: json(validBody), context: context(request()))
        let validated = try result.get()
        guard case .foods(let foods, let explanation, let tradeOffs) = validated.outcome else { return XCTFail("expected foods") }
        XCTAssertEqual(foods.map(\.foodID), ["chana-masala", "vegetable-pulao"])
        XCTAssertEqual(explanation, "Two quick vegetarian dinners.")
        XCTAssertEqual(tradeOffs.count, 1)
    }

    func testRefusalAndEmptyAreAcceptedAsSafeStates() throws {
        let refused = json("""
        { "schemaVersion": 1, "requestID": "REQ", "status": "refused", "foods": [], "explanation": "", "tradeOffs": [], "refusalReason": "unsafeRequest" }
        """)
        let empty = json("""
        { "schemaVersion": 1, "requestID": "REQ", "status": "empty", "foods": [], "explanation": "", "tradeOffs": [], "refusalReason": "noCandidates" }
        """)
        XCTAssertEqual(try FuelBuddyResponseValidator.validate(data: refused, context: context(request())).get().outcome, .refused(.unsafeRequest))
        XCTAssertEqual(try FuelBuddyResponseValidator.validate(data: empty, context: context(request())).get().outcome, .empty)
    }

    // MARK: Rejects

    private func failure(_ body: String, request: FuelBuddyLLMRequest? = nil, rules: @escaping (String) -> Bool = { _ in true }) -> FuelBuddyDiagnostic? {
        if case .failure(let diagnostic) = FuelBuddyResponseValidator.validate(data: json(body), context: context(request ?? self.request(), rules: rules)) {
            return diagnostic
        }
        return nil
    }

    func testMalformedJSONIsRejected() {
        XCTAssertEqual(failure("{ not json"), .malformedJSON)
        XCTAssertEqual(failure("[]"), .malformedJSON)
        XCTAssertEqual(failure("{ \"schemaVersion\": 1, \"requestID\": \"REQ\" }"), .malformedJSON)
    }

    func testUnknownSchemaVersionIsRejectedBeforeDecoding() {
        XCTAssertEqual(failure("{ \"schemaVersion\": 2, \"whatever\": true }"), .schemaVersionMismatch(received: 2))
    }

    func testForeignRequestIDIsRejected() {
        let body = validBody.replacingOccurrences(of: "REQ", with: UUID().uuidString)
        XCTAssertEqual(failure(body), .requestIDMismatch)
    }

    func testUnknownFoodIDIsRejected() {
        let body = validBody.replacingOccurrences(of: "vegetable-pulao", with: "butter-chicken")
        XCTAssertEqual(failure(body), .unknownFoodID("butter-chicken"))
    }

    func testDuplicateFoodIDIsRejected() {
        let body = validBody.replacingOccurrences(of: "vegetable-pulao", with: "chana-masala")
        XCTAssertEqual(failure(body), .duplicateFoodID("chana-masala"))
    }

    func testTooManyFoodsIsRejected() {
        XCTAssertEqual(failure(validBody, request: request(maxFoods: 1)), .tooManyFoods(count: 2))
    }

    func testFoodThatNoLongerPassesRulesIsRejected() {
        // Profile changed after the candidates were computed: the validator
        // re-checks against the current rules and refuses the whole answer.
        XCTAssertEqual(failure(validBody, rules: { $0 != "vegetable-pulao" }), .foodFailsCurrentRules("vegetable-pulao"))
    }

    func testInventedNutrientValuesAreRejected() {
        let body = validBody.replacingOccurrences(of: "quick and different from the dal", with: "about 320 kcal with 18 g protein")
        XCTAssertEqual(failure(body), .forbiddenLanguage(field: "foods.rationale"))
    }

    func testCaloriePrescriptionInExplanationIsRejected() {
        let body = validBody.replacingOccurrences(of: "Two quick vegetarian dinners.", with: "Aim for 1200 calories a day.")
        XCTAssertEqual(failure(body), .forbiddenLanguage(field: "explanation"))
    }

    func testMedicalOrSupplementLanguageIsRejected() {
        let medical = validBody.replacingOccurrences(of: "Two quick vegetarian dinners.", with: "This will treat my condition.")
        let supplement = validBody.replacingOccurrences(of: "Pulao needs the full 20 minutes.", with: "Add a whey supplement.")
        XCTAssertEqual(failure(medical), .forbiddenLanguage(field: "explanation"))
        XCTAssertEqual(failure(supplement), .forbiddenLanguage(field: "tradeOffs"))
    }

    func testOverlongTextIsRejected() {
        let body = validBody.replacingOccurrences(of: "Two quick vegetarian dinners.", with: String(repeating: "x", count: 401))
        XCTAssertEqual(failure(body), .textTooLong(field: "explanation"))
    }

    func testOversizedPayloadIsRejectedBeforeParsing() {
        let padded = validBody + String(repeating: " ", count: 9000)
        XCTAssertEqual(failure(padded), .responseTooLarge(bytes: json(padded).count))
    }

    func testInconsistentStatusIsRejected() {
        let refusedWithFoods = validBody.replacingOccurrences(of: "\"status\": \"ok\"", with: "\"status\": \"refused\"")
        let okWithReason = validBody.replacingOccurrences(of: "\"refusalReason\": null", with: "\"refusalReason\": \"outOfScope\"")
        let okWithoutFoods = """
        { "schemaVersion": 1, "requestID": "REQ", "status": "ok", "foods": [], "explanation": "", "tradeOffs": [], "refusalReason": null }
        """
        let refusedWithoutReason = """
        { "schemaVersion": 1, "requestID": "REQ", "status": "refused", "foods": [], "explanation": "", "tradeOffs": [], "refusalReason": null }
        """
        XCTAssertEqual(failure(refusedWithFoods), .inconsistentStatus)
        XCTAssertEqual(failure(okWithReason), .inconsistentStatus)
        XCTAssertEqual(failure(okWithoutFoods), .inconsistentStatus)
        XCTAssertEqual(failure(refusedWithoutReason), .missingRefusalReason)
    }

    func testValidatorNeverRepairsAResponse() {
        // One bad food out of two: the whole answer is rejected rather than
        // trimmed, so the explanation can't end up describing a removed item.
        let body = validBody.replacingOccurrences(of: "vegetable-pulao", with: "not-in-catalog")
        if case .success = FuelBuddyResponseValidator.validate(data: json(body), context: context(request())) {
            XCTFail("must not partially accept")
        }
    }

    // MARK: Gate + fallback

    private struct StubProvider: FuelBuddyLLMProvider {
        let handler: @Sendable (FuelBuddyLLMRequest) async throws -> Data
        func send(_ request: FuelBuddyLLMRequest) async throws -> Data { try await handler(request) }
    }

    func testGateReturnsModelAnswerWhenValid() async {
        let body = json(validBody)
        let gate = FuelBuddyGate<String>(provider: StubProvider { _ in body })
        let answer = await gate.answer(request: request(), local: "local", passesCurrentRules: { _ in true })
        guard case .model(let validated) = answer.source else { return XCTFail("expected model answer, got \(answer.source)") }
        XCTAssertEqual(validated.requestID, requestID)
        XCTAssertEqual(answer.local, "local")
    }

    func testGateFallsBackWithDiagnosticOnEachFailure() async {
        let cases: [(String, StubProvider, FuelBuddyDiagnostic)] = [
            ("malformed", StubProvider { _ in Data("nope".utf8) }, .malformedJSON),
            ("unknown id", StubProvider { [validBody] _ in Data(validBody.replacingOccurrences(of: "REQ", with: "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10").replacingOccurrences(of: "chana-masala", with: "pizza").utf8) }, .unknownFoodID("pizza")),
            ("unavailable", StubProvider { _ in throw FuelBuddyProviderError.unavailable }, .providerUnavailable),
            ("rate limited", StubProvider { _ in throw FuelBuddyProviderError.rateLimited }, .providerRateLimited),
            ("timeout", StubProvider { _ in
                try await Task.sleep(for: .seconds(5))
                return Data()
            }, .providerTimeout)
        ]

        for (name, provider, expected) in cases {
            let gate = FuelBuddyGate<String>(provider: provider)
            let answer = await gate.answer(request: request(), local: "local", passesCurrentRules: { _ in true })
            XCTAssertEqual(answer.source, .local(expected), name)
            XCTAssertEqual(answer.local, "local", name)
        }
    }

    func testGateWithoutProviderIsPureLocal() async {
        let gate = FuelBuddyGate<String>(provider: nil)
        let answer = await gate.answer(request: request(), local: "local", passesCurrentRules: { _ in true })
        XCTAssertEqual(answer.source, .local(.providerUnavailable))
    }

    func testGateRejectsSafetyRuleBypassFromModel() async {
        // Candidates are vegetarian; the model returns one of them, but the
        // profile now excludes it. The current-rules check wins.
        let body = json(validBody)
        let gate = FuelBuddyGate<String>(provider: StubProvider { _ in body })
        let answer = await gate.answer(request: request(), local: "local", passesCurrentRules: { $0 != "chana-masala" })
        XCTAssertEqual(answer.source, .local(.foodFailsCurrentRules("chana-masala")))
    }

    func testDiagnosticCodesAreStableAndNonSensitive() {
        let diagnostics: [FuelBuddyDiagnostic] = [
            .providerUnavailable, .providerTimeout, .providerRateLimited, .responseTooLarge(bytes: 1),
            .malformedJSON, .schemaVersionMismatch(received: 9), .requestIDMismatch, .unknownFoodID("x"),
            .duplicateFoodID("x"), .tooManyFoods(count: 9), .foodFailsCurrentRules("x"),
            .forbiddenLanguage(field: "f"), .textTooLong(field: "f"), .inconsistentStatus, .missingRefusalReason
        ]
        XCTAssertEqual(Set(diagnostics.map(\.code)).count, diagnostics.count)
        XCTAssertTrue(diagnostics.allSatisfy { $0.code.range(of: #"^[a-z_]+$"#, options: .regularExpression) != nil })
    }
}
