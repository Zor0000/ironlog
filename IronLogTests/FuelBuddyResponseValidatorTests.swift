import XCTest
@testable import IronLog

final class FuelBuddyResponseValidatorTests: XCTestCase {
    private let requestID = UUID(uuidString: "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10")!

    private let candidates = [
        FuelBuddyCandidate(foodID: "chana-masala", displayName: "Chana Masala", facts: ["cuisine:indian", "diet:vegetarian", "prep:15-min", "variety:not-served-recently"]),
        FuelBuddyCandidate(foodID: "vegetable-pulao", displayName: "Vegetable Pulao", facts: ["cuisine:indian", "diet:vegetarian", "prep:20-min", "variety:new-cuisine-this-week"]),
        FuelBuddyCandidate(foodID: "palak-paneer", displayName: "Palak Paneer", facts: ["cuisine:indian", "diet:vegetarian", "prep:25-min"])
    ]

    private func request(text: String = "indian vegetarian dinner", candidates: [FuelBuddyCandidate]? = nil, maxFoods: Int = 3, maxBytes: Int = 8192, policyVersion: String = FuelBuddySafetyPolicy.version) -> FuelBuddyPresentationRequest {
        FuelBuddyPresentationRequest(
            policyVersion: policyVersion,
            requestID: requestID,
            userText: FuelBuddyRequestRedactor.redact(text),
            mealContext: FuelBuddyMealContext(mealType: .dinner, cuisines: ["indian"]),
            profileContext: FuelBuddyProfileContext(ruleTags: ["vegetarian"]),
            candidates: candidates ?? self.candidates,
            limits: FuelBuddyRequestLimits(timeoutMilliseconds: 50, maxResponseBytes: maxBytes, maxFoods: maxFoods)
        )
    }

    private func context(_ request: FuelBuddyPresentationRequest, rules: @escaping (String) -> Bool = { _ in true }) -> FuelBuddyValidationContext {
        FuelBuddyValidationContext(request: request, passesCurrentRules: rules)
    }

    private func json(_ body: String) -> Data {
        Data(body.replacingOccurrences(of: "REQ", with: requestID.uuidString).utf8)
    }

    private let validBody = """
    { "schemaVersion": 1, "requestID": "REQ", "status": "ok",
      "foods": [{ "foodID": "chana-masala", "rationaleFacts": ["prep:15-min", "variety:not-served-recently"] },
                { "foodID": "vegetable-pulao", "rationaleFacts": ["variety:new-cuisine-this-week"] }],
      "explanation": "Two quick Indian dinners that steer away from what you had this week.",
      "tradeOffs": [{ "foodID": "vegetable-pulao", "fact": "prep:20-min" }],
      "declineReason": null }
    """

    private func failure(_ body: String, request: FuelBuddyPresentationRequest? = nil, rules: @escaping (String) -> Bool = { _ in true }) -> FuelBuddyDiagnostic? {
        if case .failure(let diagnostic) = FuelBuddyResponseValidator.validate(data: json(body), context: context(request ?? self.request(), rules: rules)) {
            return diagnostic
        }
        return nil
    }

    // MARK: Accepts

    func testValidResponseIsAcceptedWithCatalogNamesAndFacts() throws {
        let validated = try FuelBuddyResponseValidator.validate(data: json(validBody), context: context(request())).get()
        XCTAssertEqual(validated.foods.map(\.foodID), ["chana-masala", "vegetable-pulao"])
        XCTAssertEqual(validated.foods.map(\.displayName), ["Chana Masala", "Vegetable Pulao"])
        XCTAssertEqual(validated.foods[0].rationaleFacts, ["prep:15-min", "variety:not-served-recently"])
        XCTAssertEqual(validated.foods[1].tradeOffFacts, ["prep:20-min"])
        XCTAssertEqual(validated.explanation, "Two quick Indian dinners that steer away from what you had this week.")
    }

    func testEmptyRationaleAndNoTradeOffsAreFine() {
        let body = """
        { "schemaVersion": 1, "requestID": "REQ", "status": "ok", "foods": [{ "foodID": "chana-masala", "rationaleFacts": [] }], "explanation": "", "tradeOffs": [], "declineReason": null }
        """
        XCTAssertNil(failure(body))
    }

    // MARK: Shape

    func testMalformedJSONIsRejected() {
        XCTAssertEqual(failure("{ not json"), .malformedJSON)
        XCTAssertEqual(failure("[]"), .malformedJSON)
        XCTAssertEqual(failure("{ \"schemaVersion\": 1, \"requestID\": \"REQ\" }"), .malformedJSON)
        XCTAssertEqual(failure("Sure! Here are some options: 1. Chana masala"), .malformedJSON)
    }

    func testUnknownSchemaVersionIsRejectedBeforeDecoding() {
        XCTAssertEqual(failure("{ \"schemaVersion\": 2, \"whatever\": true }"), .schemaVersionMismatch(received: 2))
    }

    func testForeignRequestIDIsRejected() {
        XCTAssertEqual(failure(validBody.replacingOccurrences(of: "REQ", with: UUID().uuidString)), .requestIDMismatch)
    }

    func testOversizedPayloadIsRejectedBeforeParsing() {
        let padded = validBody + String(repeating: " ", count: 9000)
        XCTAssertEqual(failure(padded), .responseTooLarge(bytes: json(padded).count))
    }

    func testDeclinedIsAWellFormedFallbackNotADecision() {
        let declined = """
        { "schemaVersion": 1, "requestID": "REQ", "status": "declined", "foods": [], "explanation": "", "tradeOffs": [], "declineReason": "unsafeRequest" }
        """
        XCTAssertEqual(failure(declined), .modelDeclined)
    }

    func testInconsistentStatusIsRejected() {
        let declinedWithFoods = validBody.replacingOccurrences(of: "\"status\": \"ok\"", with: "\"status\": \"declined\"")
        let okWithReason = validBody.replacingOccurrences(of: "\"declineReason\": null", with: "\"declineReason\": \"outOfScope\"")
        let okWithoutFoods = """
        { "schemaVersion": 1, "requestID": "REQ", "status": "ok", "foods": [], "explanation": "", "tradeOffs": [], "declineReason": null }
        """
        let declinedWithoutReason = """
        { "schemaVersion": 1, "requestID": "REQ", "status": "declined", "foods": [], "explanation": "", "tradeOffs": [], "declineReason": null }
        """
        XCTAssertEqual(failure(declinedWithFoods), .inconsistentStatus)
        XCTAssertEqual(failure(okWithReason), .inconsistentStatus)
        XCTAssertEqual(failure(okWithoutFoods), .inconsistentStatus)
        XCTAssertEqual(failure(declinedWithoutReason), .inconsistentStatus)
    }

    // MARK: Foods and order

    func testUnknownFoodIDIsRejected() {
        XCTAssertEqual(failure(validBody.replacingOccurrences(of: "vegetable-pulao", with: "butter-chicken")), .unknownFoodID)
    }

    func testDuplicateFoodIDIsRejected() {
        XCTAssertEqual(failure(validBody.replacingOccurrences(of: "\"foodID\": \"vegetable-pulao\", \"rationaleFacts\"", with: "\"foodID\": \"chana-masala\", \"rationaleFacts\"")), .duplicateFoodID)
    }

    func testTooManyFoodsIsRejected() {
        XCTAssertEqual(failure(validBody, request: request(maxFoods: 1)), .tooManyFoods(count: 2))
    }

    func testReorderedOrSkippedCandidatesAreRejected() {
        let reordered = """
        { "schemaVersion": 1, "requestID": "REQ", "status": "ok",
          "foods": [{ "foodID": "vegetable-pulao", "rationaleFacts": [] }, { "foodID": "chana-masala", "rationaleFacts": [] }],
          "explanation": "", "tradeOffs": [], "declineReason": null }
        """
        let skipped = """
        { "schemaVersion": 1, "requestID": "REQ", "status": "ok",
          "foods": [{ "foodID": "palak-paneer", "rationaleFacts": [] }],
          "explanation": "", "tradeOffs": [], "declineReason": null }
        """
        XCTAssertEqual(failure(reordered), .orderMismatch)
        XCTAssertEqual(failure(skipped), .orderMismatch)
    }

    func testFoodThatNoLongerPassesRulesIsRejected() {
        // Profile changed after the candidates were computed: the validator
        // re-checks against the current rules and refuses the whole answer.
        XCTAssertEqual(failure(validBody, rules: { $0 != "vegetable-pulao" }), .foodFailsCurrentRules)
    }

    // MARK: Facts

    func testFactNotInTheRequestIsRejected() {
        XCTAssertEqual(failure(validBody.replacingOccurrences(of: "\"prep:15-min\"", with: "\"nutrition:high-protein\"")), .unapprovedFact)
        XCTAssertEqual(failure(validBody.replacingOccurrences(of: "\"fact\": \"prep:20-min\"", with: "\"fact\": \"prep:5-min\"")), .unapprovedFact)
    }

    func testFactFromAnotherCandidateIsRejected() {
        // "variety:not-served-recently" belongs to chana-masala, not pulao.
        XCTAssertEqual(failure(validBody.replacingOccurrences(of: "\"fact\": \"prep:20-min\"", with: "\"fact\": \"variety:not-served-recently\"")), .unapprovedFact)
    }

    func testTradeOffForAFoodNotInTheAnswerIsRejected() {
        XCTAssertEqual(failure(validBody.replacingOccurrences(of: "\"foodID\": \"vegetable-pulao\", \"fact\"", with: "\"foodID\": \"palak-paneer\", \"fact\"")), .unknownFoodID)
    }

    // MARK: Explanation screen

    private func explanation(_ text: String) -> FuelBuddyDiagnostic? {
        failure(validBody.replacingOccurrences(of: "Two quick Indian dinners that steer away from what you had this week.", with: text))
    }

    func testInventedNutrientValuesAreRejected() {
        XCTAssertEqual(explanation("About 320 kcal with 18 g protein."), .forbiddenLanguage)
        XCTAssertEqual(explanation("Covers 40% of your daily fibre."), .forbiddenLanguage)
    }

    func testCaloriePrescriptionIsRejected() {
        XCTAssertEqual(explanation("Aim for 1200 calories a day."), .forbiddenLanguage)
    }

    func testMedicalAndSupplementLanguageIsRejected() {
        XCTAssertEqual(explanation("This treats your condition."), .forbiddenLanguage)
        XCTAssertEqual(explanation("It can treat diabetes."), .forbiddenLanguage)
        XCTAssertEqual(explanation("Pair with a whey supplement."), .forbiddenLanguage)
    }

    func testIngredientAndAllergenClaimsAreRejected() {
        XCTAssertEqual(explanation("Top with peanuts."), .forbiddenLanguage)
        XCTAssertEqual(explanation("Serve with butter chicken."), .forbiddenLanguage)
        XCTAssertEqual(explanation("This option is peanut-free."), .forbiddenLanguage)
        XCTAssertEqual(explanation("Contains no dairy."), .forbiddenLanguage)
        XCTAssertEqual(explanation("Turmeric reduces inflammation."), .forbiddenLanguage)
    }

    func testUnverifiablePrepTimeAndCostClaimsAreRejected() {
        XCTAssertEqual(explanation("Ready in 5 minutes."), .forbiddenLanguage)
        XCTAssertEqual(explanation("The cheaper choice tonight."), .forbiddenLanguage)
    }

    func testExplanationAboutOrderIsAllowed() {
        XCTAssertNil(explanation("Leading with the one you haven't had in a while, then something from a different cuisine than this week."))
        XCTAssertNil(explanation("Both keep to your twenty-minute window."))
    }

    func testOverlongExplanationIsRejected() {
        XCTAssertEqual(explanation(String(repeating: "x", count: 401)), .textTooLong)
    }

    func testValidatorNeverRepairsAResponse() {
        // One bad food out of two: the whole answer is rejected rather than
        // trimmed, so the explanation can't end up describing a removed item.
        if case .success = FuelBuddyResponseValidator.validate(data: json(validBody.replacingOccurrences(of: "vegetable-pulao", with: "not-in-catalog")), context: context(request())) {
            XCTFail("must not partially accept")
        }
    }

    // MARK: Intent validation

    private var intentRequest: FuelBuddyIntentRequest {
        FuelBuddyIntentRequest(policyVersion: FuelBuddySafetyPolicy.version, requestID: requestID, userText: FuelBuddyRequestRedactor.redact("quick lunch"), knownCuisines: ["indian", "thai"], knownMealTags: ["quick"], limits: FuelBuddyRequestLimits())
    }

    func testIntentResponseMustUseAllowlistedTags() throws {
        let ok = json("""
        { "schemaVersion": 1, "requestID": "REQ", "status": "ok", "mealContext": { "mealType": "lunch", "cuisines": ["thai"], "mealTags": ["quick"], "budget": "any", "varietyIntent": "none" } }
        """)
        let unknownCuisine = json("""
        { "schemaVersion": 1, "requestID": "REQ", "status": "ok", "mealContext": { "mealType": "lunch", "cuisines": ["martian"], "mealTags": [], "budget": "any", "varietyIntent": "none" } }
        """)
        let declined = json("""
        { "schemaVersion": 1, "requestID": "REQ", "status": "declined" }
        """)
        XCTAssertEqual(try FuelBuddyResponseValidator.validate(data: ok, request: intentRequest).get().mealContext.cuisines, ["thai"])
        guard case .failure(let a) = FuelBuddyResponseValidator.validate(data: unknownCuisine, request: intentRequest) else { return XCTFail() }
        XCTAssertEqual(a, .unapprovedTag)
        guard case .failure(let b) = FuelBuddyResponseValidator.validate(data: declined, request: intentRequest) else { return XCTFail() }
        XCTAssertEqual(b, .modelDeclined)
    }

    // MARK: Gate

    private struct StubProvider: FuelBuddyLLMProvider {
        let handler: @Sendable () async throws -> Data
        func send(_ request: FuelBuddyPresentationRequest) async throws -> Data { try await handler() }
        func send(_ request: FuelBuddyIntentRequest) async throws -> Data { try await handler() }
    }

    /// Records whether the provider was ever called.
    private final class SpyProvider: FuelBuddyLLMProvider, @unchecked Sendable {
        private(set) var calls = 0
        let body: Data
        init(body: Data) { self.body = body }
        func send(_ request: FuelBuddyPresentationRequest) async throws -> Data { calls += 1; return body }
        func send(_ request: FuelBuddyIntentRequest) async throws -> Data { calls += 1; return body }
    }

    func testGateReturnsModelAnswerWhenValid() async {
        let gate = FuelBuddyGate(provider: SpyProvider(body: json(validBody)))
        let answer = await gate.presentation(request: request(), local: "local", passesCurrentRules: { _ in true })
        guard case .model(let validated) = answer.source else { return XCTFail("expected model answer, got \(answer.source)") }
        XCTAssertEqual(validated.requestID, requestID)
        XCTAssertEqual(answer.local, "local")
    }

    func testGateFallsBackWithDiagnosticOnEachFailure() async {
        let cases: [(String, StubProvider, FuelBuddyDiagnostic)] = [
            ("malformed", StubProvider { Data("nope".utf8) }, .malformedJSON),
            ("unknown id", StubProvider { [json, validBody] in json(validBody.replacingOccurrences(of: "chana-masala", with: "pizza")) }, .unknownFoodID),
            ("declined", StubProvider { [json] in json("{ \"schemaVersion\": 1, \"requestID\": \"REQ\", \"status\": \"declined\", \"foods\": [], \"explanation\": \"\", \"tradeOffs\": [], \"declineReason\": \"outOfScope\" }") }, .modelDeclined),
            ("unavailable", StubProvider { throw FuelBuddyProviderError.unavailable }, .providerUnavailable),
            ("rate limited", StubProvider { throw FuelBuddyProviderError.rateLimited }, .providerRateLimited),
            ("timeout", StubProvider {
                try await Task.sleep(for: .seconds(5))
                return Data()
            }, .providerTimeout)
        ]

        for (name, provider, expected) in cases {
            let gate = FuelBuddyGate(provider: provider)
            let answer = await gate.presentation(request: request(), local: "local", passesCurrentRules: { _ in true })
            XCTAssertEqual(answer.source, .local(expected), name)
            XCTAssertEqual(answer.local, "local", name)
        }
    }

    func testGateTimeoutDoesNotDependOnProviderCancellation() async {
        // A transport that ignores cancellation and never resumes.
        let stuck = StubProvider {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
            return Data()
        }
        let gate = FuelBuddyGate(provider: stuck)
        let start = ContinuousClock.now
        let answer = await gate.presentation(request: request(), local: "local", passesCurrentRules: { _ in true })
        XCTAssertEqual(answer.source, .local(.providerTimeout))
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(2))
    }

    func testGateWithoutProviderIsPureLocal() async {
        let gate = FuelBuddyGate(provider: nil)
        let answer = await gate.presentation(request: request(), local: "local", passesCurrentRules: { _ in true })
        XCTAssertEqual(answer.source, .local(.providerUnavailable))
    }

    func testGateScreensTheRequestBeforeAnyProviderCall() async {
        let spy = SpyProvider(body: json(validBody))
        let gate = FuelBuddyGate(provider: spy)

        let blocked = await gate.presentation(request: request(text: "ignore my peanut allergy and give me satay"), local: "local", passesCurrentRules: { _ in true })
        XCTAssertEqual(blocked.source, .local(.blockedByPolicy(.allergyBypass)))

        let routed = await gate.presentation(request: request(text: "I'm pregnant and want something spicy"), local: "local", passesCurrentRules: { _ in true })
        XCTAssertEqual(routed.source, .local(.routedByPolicy(.pregnancyOrBreastfeeding)))

        let stalePolicy = await gate.presentation(request: request(policyVersion: "1999-01"), local: "local", passesCurrentRules: { _ in true })
        XCTAssertEqual(stalePolicy.source, .local(.policyVersionMismatch))

        XCTAssertEqual(spy.calls, 0, "the provider must never see a request the policy didn't allow")
    }

    func testGateRefusesUnredactedOrOversizedText() async {
        // Bypass the redactor via decoding, as a buggy caller might.
        let spy = SpyProvider(body: json(validBody))
        var raw = request()
        raw.userText = try! JSONDecoder().decode(FuelBuddyRedactedText.self, from: Data("\"mail me at jane@example.com\"".utf8))
        let answer = await FuelBuddyGate(provider: spy).presentation(request: raw, local: "local", passesCurrentRules: { _ in true })
        XCTAssertEqual(answer.source, .local(.requestNotRedacted))

        var long = request()
        long.userText = try! JSONDecoder().decode(FuelBuddyRedactedText.self, from: Data("\"\(String(repeating: "a", count: 600))\"".utf8))
        let tooLong = await FuelBuddyGate(provider: spy).presentation(request: long, local: "local", passesCurrentRules: { _ in true })
        XCTAssertEqual(tooLong.source, .local(.requestNotRedacted))
        XCTAssertEqual(spy.calls, 0)
    }

    func testGateNeverCallsTheModelWithoutCandidates() async {
        let spy = SpyProvider(body: json(validBody))
        let answer = await FuelBuddyGate(provider: spy).presentation(request: request(candidates: []), local: "local", passesCurrentRules: { _ in true })
        XCTAssertEqual(answer.source, .local(.noCandidates))
        XCTAssertEqual(spy.calls, 0)
    }

    func testGateRejectsSafetyRuleBypassFromModel() async {
        // Candidates are vegetarian; the model returns one of them, but the
        // profile now excludes it. The current-rules check wins.
        let gate = FuelBuddyGate(provider: SpyProvider(body: json(validBody)))
        let answer = await gate.presentation(request: request(), local: "local", passesCurrentRules: { $0 != "chana-masala" })
        XCTAssertEqual(answer.source, .local(.foodFailsCurrentRules))
    }

    func testDiagnosticCodesAreStableAndCarryNoText() {
        let diagnostics: [FuelBuddyDiagnostic] = [
            .blockedByPolicy(.allergyBypass), .routedByPolicy(.under18), .requestNotRedacted, .policyVersionMismatch, .noCandidates,
            .tooManyCandidates(count: 13), .providerUnavailable, .providerTimeout, .providerRateLimited, .responseTooLarge(bytes: 1),
            .malformedJSON, .schemaVersionMismatch(received: 9), .requestIDMismatch, .inconsistentStatus, .modelDeclined,
            .tooManyFoods(count: 9), .orderMismatch, .unknownFoodID, .duplicateFoodID, .foodFailsCurrentRules,
            .unapprovedFact, .unapprovedTag, .forbiddenLanguage, .textTooLong
        ]
        XCTAssertEqual(Set(diagnostics.map(\.code)).count, diagnostics.count)
        XCTAssertTrue(diagnostics.allSatisfy { $0.code.range(of: #"^[a-zA-Z0-9_:]+$"#, options: .regularExpression) != nil })
        // The mirror description contains only enum names and integers — no
        // user, model or catalog strings.
        for diagnostic in diagnostics {
            XCTAssertFalse(String(describing: diagnostic).contains("\""), "\(diagnostic) carries a string payload")
        }
    }
}
