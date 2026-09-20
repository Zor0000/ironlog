import Foundation

/// Provider-neutral contracts for the optional LLM layer behind Fuel Buddy.
/// Mirrors `docs/ironfuel/fuel-buddy-llm-contract.md`.
///
/// Two request shapes share one version: **intent** (before candidates
/// exist; the model returns enums and allowlisted tags) and **presentation**
/// (after the deterministic pipeline; the model returns caption copy and
/// *pointers* to catalog facts it was handed). Neither response has a field
/// that can carry a new food, a nutrient value, an ingredient, a food
/// property or a calorie target.
enum FuelBuddyLLMContract {
    static let schemaVersion = 1
    static let maxUserTextLength = 500
    static let maxExplanationLength = 400
    static let maxCandidates = 12
    static let maxFactsPerCandidate = 12
    static let maxTagLength = 40
}

// MARK: - Shared

struct FuelBuddyMealContext: Codable, Equatable {
    enum MealType: String, Codable, CaseIterable { case breakfast, lunch, dinner, snack, any }
    enum Budget: String, Codable, CaseIterable { case low, moderate, any }
    enum VarietyIntent: String, Codable, CaseIterable { case none, differentFromRecent, surpriseMe }

    var mealType: MealType = .any
    /// Lowercase cuisine tags from the curated catalog.
    var cuisines: [String] = []
    /// Lowercase meal tags from the curated catalog ("quick", "high-protein").
    var mealTags: [String] = []
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
    /// Forwarded to the provider by the gateway; the cost control for output.
    var maxOutputTokens = 400
}

/// User text that has been through `FuelBuddyRequestRedactor`. Only the
/// redactor can make one, so a request cannot be built from raw input.
struct FuelBuddyRedactedText: Codable, Equatable {
    let value: String

    fileprivate init(redacted value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Deterministic, on-device scrubbing of the free-text request before it can
/// leave the phone. Replaces identifiers and body measurements with
/// placeholders and truncates to the contract limit. Conditions and ages are
/// handled by `FuelBuddySafetyPolicy` routing, which runs after this.
enum FuelBuddyRequestRedactor {
    static let placeholders = ["[email]", "[phone]", "[url]", "[measurement]", "[number]"]

    private static let rules: [(pattern: String, replacement: String)] = [
        (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "[email]"),
        (#"https?://\S+|www\.\S+"#, "[url]"),
        (#"\+?\d[\d\s().-]{7,}\d"#, "[phone]"),
        (#"\b\d+(\.\d+)?\s?(kg|kgs|kilos?|kilograms?|lb|lbs|pounds?|stone|cm|centimet(?:re|er)s?|metres?|meters?|ft|feet|foot|inches)\b"#, "[measurement]"),
        (#"\b\d{5,}\b"#, "[number]")
    ]

    static func redact(_ text: String) -> FuelBuddyRedactedText {
        var output = text
        for rule in rules {
            output = output.replacingOccurrences(of: rule.pattern, with: rule.replacement, options: [.regularExpression, .caseInsensitive])
        }
        output = output
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if output.count > FuelBuddyLLMContract.maxUserTextLength {
            output = String(output.prefix(FuelBuddyLLMContract.maxUserTextLength))
        }
        return FuelBuddyRedactedText(redacted: output)
    }

    /// True when `text` is already in redacted form: running the redactor
    /// again changes nothing. The gate refuses anything else.
    static func isRedacted(_ text: String) -> Bool {
        redact(text).value == text && text.count <= FuelBuddyLLMContract.maxUserTextLength
    }
}

// MARK: - Intent stage

struct FuelBuddyIntentRequest: Codable, Equatable {
    var schemaVersion = FuelBuddyLLMContract.schemaVersion
    var policyVersion: String
    var requestID: UUID
    var userText: FuelBuddyRedactedText
    /// Allowlists the model must choose from; anything else is rejected.
    var knownCuisines: [String]
    var knownMealTags: [String]
    var limits: FuelBuddyRequestLimits
}

struct FuelBuddyIntentResponse: Codable, Equatable {
    enum Status: String, Codable { case ok, declined }

    var schemaVersion: Int
    var requestID: UUID
    var status: Status
    /// Present when `status == ok`. Cuisines/tags must be subsets of the
    /// request's allowlists.
    var mealContext: FuelBuddyMealContext?
}

// MARK: - Presentation stage

/// One approved food as the model sees it: its ID, display name, and the
/// catalog facts it may point at. Facts are `namespace:value` tokens
/// (`prep:15-min`, `cuisine:indian`, `diet:vegetarian`, `budget:low`,
/// `tag:high-protein`, `variety:not-served-recently`).
struct FuelBuddyCandidate: Codable, Equatable {
    var foodID: String
    var displayName: String
    var facts: [String]
}

struct FuelBuddyPresentationRequest: Codable, Equatable {
    var schemaVersion = FuelBuddyLLMContract.schemaVersion
    var policyVersion: String
    var requestID: UUID
    var userText: FuelBuddyRedactedText
    var mealContext: FuelBuddyMealContext
    var profileContext: FuelBuddyProfileContext
    /// In the order `MealVarietyRotation` produced. The response must keep it.
    var candidates: [FuelBuddyCandidate]
    var limits: FuelBuddyRequestLimits

    var candidateFoodIDs: [String] { candidates.map(\.foodID) }
}

struct FuelBuddyPresentationResponse: Codable, Equatable {
    enum Status: String, Codable { case ok, declined }
    enum DeclineReason: String, Codable { case unsafeRequest, outOfScope, noCandidates }

    struct Food: Codable, Equatable {
        var foodID: String
        /// Subset of that candidate's `facts`; what the UI highlights.
        var rationaleFacts: [String]
    }

    struct TradeOff: Codable, Equatable {
        var foodID: String
        /// One of that candidate's `facts`.
        var fact: String
    }

    var schemaVersion: Int
    var requestID: UUID
    var status: Status
    /// Exactly the first N request candidates, in order, when `status == ok`.
    var foods: [Food]
    /// Caption copy. Screened; carries no facts the UI relies on.
    var explanation: String
    var tradeOffs: [TradeOff]
    var declineReason: DeclineReason?
}

extension FuelBuddyIntentRequest {
    /// Keys that must never appear anywhere in a request payload. Checked by
    /// tests against the encoded JSON so a future field can't smuggle them in.
    static let forbiddenKeys: Set<String> = [
        "email", "userID", "userId", "user_id", "name", "weight", "height", "age",
        "conditions", "diagnosis", "medications", "notes"
    ]
}
