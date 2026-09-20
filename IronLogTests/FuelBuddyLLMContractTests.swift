import XCTest
@testable import IronLog

/// The contract's Swift types must round-trip the documented JSON examples
/// exactly, must not be able to carry sensitive fields, and must not be
/// buildable from unredacted text.
final class FuelBuddyLLMContractTests: XCTestCase {
    private let requestID = UUID(uuidString: "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10")!

    private var decoder: JSONDecoder { JSONDecoder() }
    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func keys(in data: Data) throws -> Set<String> {
        var keys: Set<String> = []
        func collect(_ value: Any) {
            if let dict = value as? [String: Any] {
                keys.formUnion(dict.keys)
                dict.values.forEach(collect)
            } else if let array = value as? [Any] {
                array.forEach(collect)
            }
        }
        collect(try JSONSerialization.jsonObject(with: data))
        return keys
    }

    // MARK: Redaction

    func testRedactorStripsIdentifiersAndMeasurements() {
        let raw = "I'm jane@example.com, 90 kg and 5 ft 11, call +44 7911 123456 — quick lunch? see https://x.y/z"
        let redacted = FuelBuddyRequestRedactor.redact(raw).value

        XCTAssertFalse(redacted.contains("jane@example.com"))
        XCTAssertFalse(redacted.contains("90 kg"))
        XCTAssertFalse(redacted.contains("5 ft"))
        XCTAssertFalse(redacted.contains("7911"))
        XCTAssertFalse(redacted.contains("https://"))
        XCTAssertTrue(redacted.contains("[email]"))
        XCTAssertTrue(redacted.contains("[measurement]"))
        XCTAssertTrue(redacted.contains("[phone]"))
        XCTAssertTrue(redacted.contains("[url]"))
        XCTAssertTrue(redacted.contains("quick lunch?"))
        XCTAssertTrue(FuelBuddyRequestRedactor.isRedacted(redacted), "redaction is idempotent")
    }

    func testRedactorLeavesOrdinaryMealTextAlone() {
        for text in [
            "Suggest an Indian vegetarian dinner under 20 minutes",
            "3 quick high-protein lunches for the week",
            "something different from yesterday, ready in 10 minutes"
        ] {
            XCTAssertEqual(FuelBuddyRequestRedactor.redact(text).value, text)
            XCTAssertTrue(FuelBuddyRequestRedactor.isRedacted(text))
        }
    }

    func testRedactorTruncatesToTheContractLimit() {
        let long = String(repeating: "lunch ", count: 200)
        let redacted = FuelBuddyRequestRedactor.redact(long).value
        XCTAssertEqual(redacted.count, FuelBuddyLLMContract.maxUserTextLength)
        XCTAssertFalse(FuelBuddyRequestRedactor.isRedacted(long))
    }

    // MARK: Intent

    func testIntentRequestAndResponseRoundTripDocumentedExamples() throws {
        let requestJSON = """
        {
          "schemaVersion": 1, "policyVersion": "2026-09",
          "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10",
          "userText": "Suggest an Indian vegetarian dinner under 20 minutes",
          "knownCuisines": ["indian", "mexican", "italian", "thai"],
          "knownMealTags": ["quick", "high-protein", "comfort", "light"],
          "limits": { "timeoutMilliseconds": 4000, "maxResponseBytes": 2048, "maxFoods": 3, "maxOutputTokens": 120 }
        }
        """
        let responseJSON = """
        {
          "schemaVersion": 1, "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10", "status": "ok",
          "mealContext": { "mealType": "dinner", "cuisines": ["indian"], "mealTags": ["quick"], "maxPrepMinutes": 20, "budget": "any", "varietyIntent": "none" }
        }
        """
        let request = try decoder.decode(FuelBuddyIntentRequest.self, from: Data(requestJSON.utf8))
        let response = try decoder.decode(FuelBuddyIntentResponse.self, from: Data(responseJSON.utf8))

        XCTAssertEqual(request.knownCuisines.count, 4)
        XCTAssertEqual(request.limits.maxOutputTokens, 120)
        XCTAssertEqual(response.mealContext?.mealType, .dinner)
        XCTAssertEqual(response.mealContext?.maxPrepMinutes, 20)
        XCTAssertEqual(try decoder.decode(FuelBuddyIntentRequest.self, from: encoder.encode(request)), request)
        XCTAssertEqual(try decoder.decode(FuelBuddyIntentResponse.self, from: encoder.encode(response)), response)
    }

    func testIntentResponseHasNoFreeText() throws {
        let response = FuelBuddyIntentResponse(schemaVersion: 1, requestID: requestID, status: .ok, mealContext: FuelBuddyMealContext(mealType: .lunch))
        let allKeys = try keys(in: encoder.encode(response))
        XCTAssertEqual(allKeys, ["schemaVersion", "requestID", "status", "mealContext", "mealType", "cuisines", "mealTags", "budget", "varietyIntent"])
    }

    // MARK: Presentation

    private var presentationRequest: FuelBuddyPresentationRequest {
        FuelBuddyPresentationRequest(
            policyVersion: "2026-09",
            requestID: requestID,
            userText: FuelBuddyRequestRedactor.redact("Suggest an Indian vegetarian dinner under 20 minutes"),
            mealContext: FuelBuddyMealContext(mealType: .dinner, cuisines: ["indian"], mealTags: ["quick"], maxPrepMinutes: 20, varietyIntent: .differentFromRecent),
            profileContext: FuelBuddyProfileContext(ruleTags: ["vegetarian", "no-peanut"], recentFoodIDs: ["dal-tadka", "paneer-bhurji"]),
            candidates: [
                FuelBuddyCandidate(foodID: "chana-masala", displayName: "Chana Masala", facts: ["cuisine:indian", "diet:vegetarian", "prep:15-min", "budget:low", "variety:not-served-recently"]),
                FuelBuddyCandidate(foodID: "vegetable-pulao", displayName: "Vegetable Pulao", facts: ["cuisine:indian", "diet:vegetarian", "prep:20-min", "budget:low", "variety:new-cuisine-this-week"]),
                FuelBuddyCandidate(foodID: "palak-paneer", displayName: "Palak Paneer", facts: ["cuisine:indian", "diet:vegetarian", "prep:25-min", "budget:moderate"])
            ],
            limits: FuelBuddyRequestLimits(maxFoods: 2)
        )
    }

    func testPresentationRequestRoundTripsAndCarriesOrderedCandidates() throws {
        let request = presentationRequest
        let decoded = try decoder.decode(FuelBuddyPresentationRequest.self, from: encoder.encode(request))
        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.candidateFoodIDs, ["chana-masala", "vegetable-pulao", "palak-paneer"])
        XCTAssertEqual(decoded.userText.value, "Suggest an Indian vegetarian dinner under 20 minutes")
    }

    func testRequestsNeverCarrySensitiveKeys() throws {
        let intent = FuelBuddyIntentRequest(
            policyVersion: "2026-09", requestID: requestID,
            userText: FuelBuddyRequestRedactor.redact("quick high-protein lunch"),
            knownCuisines: ["thai"], knownMealTags: ["quick"], limits: FuelBuddyRequestLimits()
        )
        for data in [try encoder.encode(intent), try encoder.encode(presentationRequest)] {
            let leaked = try keys(in: data).intersection(FuelBuddyIntentRequest.forbiddenKeys)
            XCTAssertTrue(leaked.isEmpty, "leaked: \(leaked)")
        }
    }

    func testValidPresentationResponseRoundTrips() throws {
        let json = """
        {
          "schemaVersion": 1,
          "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10",
          "status": "ok",
          "foods": [
            { "foodID": "chana-masala", "rationaleFacts": ["prep:15-min", "variety:not-served-recently"] },
            { "foodID": "vegetable-pulao", "rationaleFacts": ["variety:new-cuisine-this-week"] }
          ],
          "explanation": "Two quick Indian dinners that steer away from what you had this week.",
          "tradeOffs": [ { "foodID": "vegetable-pulao", "fact": "prep:20-min" } ],
          "declineReason": null
        }
        """
        let response = try decoder.decode(FuelBuddyPresentationResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.foods.map(\.foodID), ["chana-masala", "vegetable-pulao"])
        XCTAssertEqual(response.tradeOffs.first?.fact, "prep:20-min")
        XCTAssertNil(response.declineReason)
        XCTAssertEqual(try decoder.decode(FuelBuddyPresentationResponse.self, from: encoder.encode(response)), response)
    }

    func testDeclinedResponseDecodes() throws {
        let json = """
        { "schemaVersion": 1, "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10", "status": "declined",
          "foods": [], "explanation": "", "tradeOffs": [], "declineReason": "outOfScope" }
        """
        let response = try decoder.decode(FuelBuddyPresentationResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.status, .declined)
        XCTAssertEqual(response.declineReason, .outOfScope)
    }

    func testMalformedAndUnknownEnumValuesFailToDecode() {
        let wrongEnum = """
        { "schemaVersion": 1, "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10", "status": "maybe",
          "foods": [], "explanation": "", "tradeOffs": [] }
        """
        let missingKeys = """
        { "schemaVersion": 2, "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10", "status": "ok", "foods": [] }
        """
        XCTAssertThrowsError(try decoder.decode(FuelBuddyPresentationResponse.self, from: Data(wrongEnum.utf8)))
        XCTAssertThrowsError(try decoder.decode(FuelBuddyPresentationResponse.self, from: Data(missingKeys.utf8)))
        XCTAssertThrowsError(try decoder.decode(FuelBuddyPresentationResponse.self, from: Data("not json".utf8)))
        XCTAssertThrowsError(try decoder.decode(FuelBuddyIntentResponse.self, from: Data("{\"status\":\"ok\"}".utf8)))
    }

    func testPresentationResponseHasNoFieldForFoodsNutrientsOrTargets() throws {
        // Structural guarantee: the only place a food can appear is
        // `foods[].foodID` / `tradeOffs[].foodID`; facts are references; the
        // only numeric field is the schema version.
        let response = FuelBuddyPresentationResponse(
            schemaVersion: 1, requestID: requestID, status: .ok,
            foods: [.init(foodID: "x", rationaleFacts: ["prep:15-min"])],
            explanation: "e", tradeOffs: [.init(foodID: "x", fact: "prep:15-min")], declineReason: nil
        )
        let object = try JSONSerialization.jsonObject(with: encoder.encode(response)) as! [String: Any]
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "requestID", "status", "foods", "explanation", "tradeOffs"])
        XCTAssertEqual(Set((object["foods"] as! [[String: Any]])[0].keys), ["foodID", "rationaleFacts"])
        XCTAssertEqual(Set((object["tradeOffs"] as! [[String: Any]])[0].keys), ["foodID", "fact"])
        XCTAssertEqual(object.values.filter { $0 is NSNumber }.count, 1, "only schemaVersion may be numeric")
    }
}
