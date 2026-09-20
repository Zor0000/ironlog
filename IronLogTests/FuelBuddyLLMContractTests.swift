import XCTest
@testable import IronLog

/// The contract's Swift types must round-trip the documented JSON examples
/// exactly, and must not be able to carry sensitive fields.
final class FuelBuddyLLMContractTests: XCTestCase {
    private let requestID = UUID(uuidString: "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10")!

    private var decoder: JSONDecoder { JSONDecoder() }
    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    func testRequestRoundTripsDocumentedExample() throws {
        let json = """
        {
          "schemaVersion": 1,
          "policyVersion": "2026-09",
          "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10",
          "stage": "presentation",
          "userText": "Suggest an Indian vegetarian dinner under 20 minutes",
          "mealContext": {
            "mealType": "dinner",
            "cuisines": ["indian"],
            "maxPrepMinutes": 20,
            "budget": "moderate",
            "varietyIntent": "differentFromRecent"
          },
          "profileContext": {
            "ruleTags": ["vegetarian", "no-peanut"],
            "recentFoodIDs": ["dal-tadka", "paneer-bhurji"]
          },
          "candidateFoodIDs": ["chana-masala", "vegetable-pulao", "palak-paneer", "masala-oats"],
          "limits": { "timeoutMilliseconds": 4000, "maxResponseBytes": 8192, "maxFoods": 3 }
        }
        """
        let request = try decoder.decode(FuelBuddyLLMRequest.self, from: Data(json.utf8))

        XCTAssertEqual(request.schemaVersion, 1)
        XCTAssertEqual(request.stage, .presentation)
        XCTAssertEqual(request.mealContext.mealType, .dinner)
        XCTAssertEqual(request.mealContext.maxPrepMinutes, 20)
        XCTAssertEqual(request.mealContext.varietyIntent, .differentFromRecent)
        XCTAssertEqual(request.profileContext.ruleTags, ["vegetarian", "no-peanut"])
        XCTAssertEqual(request.candidateFoodIDs.count, 4)
        XCTAssertEqual(request.limits.maxFoods, 3)

        let reencoded = try decoder.decode(FuelBuddyLLMRequest.self, from: encoder.encode(request))
        XCTAssertEqual(reencoded, request)
    }

    func testRequestNeverCarriesSensitiveKeys() throws {
        let request = FuelBuddyLLMRequest(
            policyVersion: "2026-09",
            requestID: requestID,
            stage: .intent,
            userText: "quick high-protein lunch",
            mealContext: FuelBuddyMealContext(mealType: .lunch),
            profileContext: FuelBuddyProfileContext(ruleTags: ["halal"]),
            candidateFoodIDs: ["grilled-chicken-wrap"],
            limits: FuelBuddyRequestLimits()
        )
        let object = try JSONSerialization.jsonObject(with: encoder.encode(request)) as! [String: Any]

        var keys: Set<String> = []
        func collect(_ value: Any) {
            if let dict = value as? [String: Any] {
                keys.formUnion(dict.keys)
                dict.values.forEach(collect)
            } else if let array = value as? [Any] {
                array.forEach(collect)
            }
        }
        collect(object)

        XCTAssertTrue(keys.isDisjoint(with: FuelBuddyLLMRequest.forbiddenKeys), "leaked: \(keys.intersection(FuelBuddyLLMRequest.forbiddenKeys))")
    }

    func testValidResponseRoundTrips() throws {
        let json = """
        {
          "schemaVersion": 1,
          "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10",
          "status": "ok",
          "foods": [
            { "foodID": "chana-masala", "rationale": "fits vegetarian, ready in 20 minutes" },
            { "foodID": "vegetable-pulao", "rationale": "different from the dal you had recently" }
          ],
          "explanation": "Two quick Indian vegetarian dinners that avoid what you ate this week.",
          "tradeOffs": ["Vegetable pulao takes the full 20 minutes."],
          "refusalReason": null
        }
        """
        let response = try decoder.decode(FuelBuddyLLMResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.foods.map(\.foodID), ["chana-masala", "vegetable-pulao"])
        XCTAssertNil(response.refusalReason)
        XCTAssertEqual(try decoder.decode(FuelBuddyLLMResponse.self, from: encoder.encode(response)), response)
    }

    func testRefusedAndEmptyResponsesDecode() throws {
        let refused = """
        { "schemaVersion": 1, "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10", "status": "refused",
          "foods": [], "explanation": "", "tradeOffs": [], "refusalReason": "unsafeRequest" }
        """
        let empty = """
        { "schemaVersion": 1, "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10", "status": "empty",
          "foods": [], "explanation": "", "tradeOffs": [], "refusalReason": "noCandidates" }
        """
        XCTAssertEqual(try decoder.decode(FuelBuddyLLMResponse.self, from: Data(refused.utf8)).refusalReason, .unsafeRequest)
        XCTAssertEqual(try decoder.decode(FuelBuddyLLMResponse.self, from: Data(empty.utf8)).status, .empty)
    }

    func testMalformedAndUnknownEnumValuesFailToDecode() {
        let wrongEnum = """
        { "schemaVersion": 1, "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10", "status": "maybe",
          "foods": [], "explanation": "", "tradeOffs": [] }
        """
        let missingKeys = """
        { "schemaVersion": 2, "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10", "status": "ok", "foods": [] }
        """
        XCTAssertThrowsError(try decoder.decode(FuelBuddyLLMResponse.self, from: Data(wrongEnum.utf8)))
        XCTAssertThrowsError(try decoder.decode(FuelBuddyLLMResponse.self, from: Data(missingKeys.utf8)))
        XCTAssertThrowsError(try decoder.decode(FuelBuddyLLMResponse.self, from: Data("not json".utf8)))
    }

    func testResponseHasNoFieldForFoodsNutrientsOrTargets() throws {
        // Structural guarantee: the only place a food can appear is `foods[].foodID`,
        // and there is no numeric field at all besides the schema version.
        let response = FuelBuddyLLMResponse(
            schemaVersion: 1, requestID: requestID, status: .ok,
            foods: [.init(foodID: "x", rationale: "y")],
            explanation: "e", tradeOffs: ["t"], refusalReason: nil
        )
        let object = try JSONSerialization.jsonObject(with: encoder.encode(response)) as! [String: Any]
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "requestID", "status", "foods", "explanation", "tradeOffs"])
        let food = (object["foods"] as! [[String: Any]])[0]
        XCTAssertEqual(Set(food.keys), ["foodID", "rationale"])
        XCTAssertTrue(object.values.filter { $0 is NSNumber }.count == 1, "only schemaVersion may be numeric")
    }
}
