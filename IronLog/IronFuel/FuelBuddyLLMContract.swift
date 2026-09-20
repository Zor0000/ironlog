import Foundation

/// Provider-neutral request/response contract for the optional LLM layer
/// behind Fuel Buddy. Mirrors `docs/ironfuel/fuel-buddy-llm-contract.md`.
///
/// The response deliberately has no field that can carry a new food, a
/// nutrient value, an ingredient or a calorie target: foods are catalog IDs,
/// everything else is bounded free text that the validator screens.
enum FuelBuddyLLMContract {
    static let schemaVersion = 1
    static let maxUserTextLength = 500
    static let maxRationaleLength = 140
    static let maxExplanationLength = 400
    static let maxTradeOffLength = 140
}

// MARK: - Request

struct FuelBuddyLLMRequest: Codable, Equatable {
    enum Stage: String, Codable { case intent, presentation }

    var schemaVersion = FuelBuddyLLMContract.schemaVersion
    /// Version of the deterministic safety policy that screened `userText`.
    var policyVersion: String
    var requestID: UUID
    var stage: Stage
    var userText: String
    var mealContext: FuelBuddyMealContext
    var profileContext: FuelBuddyProfileContext
    /// The only foods the model may reference — the survivors of the
    /// deterministic filters and the variety rotation.
    var candidateFoodIDs: [String]
    var limits: FuelBuddyRequestLimits
}

struct FuelBuddyMealContext: Codable, Equatable {
    enum MealType: String, Codable { case breakfast, lunch, dinner, snack, any }
    enum Budget: String, Codable { case low, moderate, any }
    enum VarietyIntent: String, Codable { case none, differentFromRecent, surpriseMe }

    var mealType: MealType = .any
    var cuisines: [String] = []
    var maxPrepMinutes: Int?
    var budget: Budget = .any
    var varietyIntent: VarietyIntent = .none
}

/// Only *resolved* rule tags and recent IDs — never raw conditions, body
/// metrics or identifiers.
struct FuelBuddyProfileContext: Codable, Equatable {
    var ruleTags: [String] = []
    var recentFoodIDs: [String] = []
}

struct FuelBuddyRequestLimits: Codable, Equatable {
    var timeoutMilliseconds = 4000
    var maxResponseBytes = 8192
    var maxFoods = 3
}

// MARK: - Response

struct FuelBuddyLLMResponse: Codable, Equatable {
    enum Status: String, Codable { case ok, refused, empty }
    enum RefusalReason: String, Codable { case unsafeRequest, outOfScope, noCandidates }

    struct Food: Codable, Equatable {
        var foodID: String
        var rationale: String
    }

    var schemaVersion: Int
    var requestID: UUID
    var status: Status
    var foods: [Food]
    var explanation: String
    var tradeOffs: [String]
    var refusalReason: RefusalReason?
}

extension FuelBuddyLLMRequest {
    /// Keys that must never appear anywhere in a request payload. Checked by
    /// tests against the encoded JSON so a future field can't smuggle them in.
    static let forbiddenKeys: Set<String> = [
        "email", "userID", "userId", "user_id", "name", "weight", "height", "age",
        "conditions", "diagnosis", "medications", "notes"
    ]
}
