import Foundation

/// Why a model response was thrown away. Non-sensitive by construction: it
/// never carries the request text, the profile, or the model output.
enum FuelBuddyDiagnostic: Error, Equatable, Hashable {
    case providerUnavailable
    case providerTimeout
    case providerRateLimited
    case responseTooLarge(bytes: Int)
    case malformedJSON
    case schemaVersionMismatch(received: Int)
    case requestIDMismatch
    case unknownFoodID(String)
    case duplicateFoodID(String)
    case tooManyFoods(count: Int)
    case foodFailsCurrentRules(String)
    case forbiddenLanguage(field: String)
    case textTooLong(field: String)
    case inconsistentStatus
    case missingRefusalReason

    /// Stable string for logs and metrics.
    var code: String {
        switch self {
        case .providerUnavailable: return "provider_unavailable"
        case .providerTimeout: return "provider_timeout"
        case .providerRateLimited: return "provider_rate_limited"
        case .responseTooLarge: return "response_too_large"
        case .malformedJSON: return "malformed_json"
        case .schemaVersionMismatch: return "schema_version_mismatch"
        case .requestIDMismatch: return "request_id_mismatch"
        case .unknownFoodID: return "unknown_food_id"
        case .duplicateFoodID: return "duplicate_food_id"
        case .tooManyFoods: return "too_many_foods"
        case .foodFailsCurrentRules: return "food_fails_current_rules"
        case .forbiddenLanguage: return "forbidden_language"
        case .textTooLong: return "text_too_long"
        case .inconsistentStatus: return "inconsistent_status"
        case .missingRefusalReason: return "missing_refusal_reason"
        }
    }
}

/// A validated model answer. Constructed only by the validator, so holding
/// one is proof the contract was enforced.
struct FuelBuddyValidatedResponse: Equatable {
    enum Outcome: Equatable {
        case foods([FuelBuddyLLMResponse.Food], explanation: String, tradeOffs: [String])
        case refused(FuelBuddyLLMResponse.RefusalReason)
        case empty
    }

    let requestID: UUID
    let outcome: Outcome
}

/// Everything the validator needs to know about the deterministic world at
/// the moment the response arrives.
struct FuelBuddyValidationContext {
    let request: FuelBuddyLLMRequest
    /// Re-check every returned food against the *current* profile rules —
    /// the request's candidate list may be stale if the profile changed
    /// mid-flight. Return false to reject the food.
    let passesCurrentRules: (String) -> Bool
}

/// Parses raw bytes into the versioned contract and rejects anything that
/// could weaken the safety contract. Never repairs a response: a single
/// invalid food fails the whole answer, because trimming silently would
/// change what the explanation refers to.
enum FuelBuddyResponseValidator {
    static func validate(data: Data, context: FuelBuddyValidationContext) -> Result<FuelBuddyValidatedResponse, FuelBuddyDiagnostic> {
        let limits = context.request.limits
        guard data.count <= limits.maxResponseBytes else {
            return .failure(.responseTooLarge(bytes: data.count))
        }

        // Peek at the version before decoding the whole thing so an unknown
        // future schema is reported as such rather than as "malformed".
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.malformedJSON)
        }
        if let version = object["schemaVersion"] as? Int, version != context.request.schemaVersion {
            return .failure(.schemaVersionMismatch(received: version))
        }
        guard let response = try? JSONDecoder().decode(FuelBuddyLLMResponse.self, from: data) else {
            return .failure(.malformedJSON)
        }
        return validate(response: response, context: context)
    }

    static func validate(response: FuelBuddyLLMResponse, context: FuelBuddyValidationContext) -> Result<FuelBuddyValidatedResponse, FuelBuddyDiagnostic> {
        let request = context.request
        guard response.schemaVersion == request.schemaVersion else {
            return .failure(.schemaVersionMismatch(received: response.schemaVersion))
        }
        guard response.requestID == request.requestID else {
            return .failure(.requestIDMismatch)
        }

        // Status/shape consistency first: a "refused" with foods attached is
        // a model trying to have it both ways.
        switch response.status {
        case .ok:
            guard !response.foods.isEmpty, response.refusalReason == nil else { return .failure(.inconsistentStatus) }
        case .refused:
            guard response.foods.isEmpty else { return .failure(.inconsistentStatus) }
            guard let reason = response.refusalReason else { return .failure(.missingRefusalReason) }
            return .success(FuelBuddyValidatedResponse(requestID: response.requestID, outcome: .refused(reason)))
        case .empty:
            guard response.foods.isEmpty else { return .failure(.inconsistentStatus) }
            guard response.refusalReason == .noCandidates else { return .failure(.missingRefusalReason) }
            return .success(FuelBuddyValidatedResponse(requestID: response.requestID, outcome: .empty))
        }

        guard response.foods.count <= request.limits.maxFoods else {
            return .failure(.tooManyFoods(count: response.foods.count))
        }

        let approved = Set(request.candidateFoodIDs)
        var seen: Set<String> = []
        for food in response.foods {
            guard approved.contains(food.foodID) else { return .failure(.unknownFoodID(food.foodID)) }
            guard seen.insert(food.foodID).inserted else { return .failure(.duplicateFoodID(food.foodID)) }
            guard context.passesCurrentRules(food.foodID) else { return .failure(.foodFailsCurrentRules(food.foodID)) }
            if let failure = checkText(food.rationale, field: "foods.rationale", limit: FuelBuddyLLMContract.maxRationaleLength) {
                return .failure(failure)
            }
        }
        if let failure = checkText(response.explanation, field: "explanation", limit: FuelBuddyLLMContract.maxExplanationLength) {
            return .failure(failure)
        }
        for tradeOff in response.tradeOffs {
            if let failure = checkText(tradeOff, field: "tradeOffs", limit: FuelBuddyLLMContract.maxTradeOffLength) {
                return .failure(failure)
            }
        }

        return .success(FuelBuddyValidatedResponse(
            requestID: response.requestID,
            outcome: .foods(response.foods, explanation: response.explanation, tradeOffs: response.tradeOffs)
        ))
    }

    private static func checkText(_ text: String, field: String, limit: Int) -> FuelBuddyDiagnostic? {
        if text.count > limit { return .textTooLong(field: field) }
        if FuelBuddySafetyPolicy.containsForbiddenLanguage(text) { return .forbiddenLanguage(field: field) }
        return nil
    }
}

// MARK: - Gate: provider + timeout + fallback

/// Abstract model transport. The real implementation calls the Supabase Edge
/// Function with the user's session token; tests use closures.
protocol FuelBuddyLLMProvider {
    func send(_ request: FuelBuddyLLMRequest) async throws -> Data
}

enum FuelBuddyProviderError: Error, Equatable {
    case unavailable
    case rateLimited
}

/// What the user ultimately gets, and where it came from.
struct FuelBuddyAnswer<Local: Equatable>: Equatable {
    enum Source: Equatable {
        case model(FuelBuddyValidatedResponse)
        case local(FuelBuddyDiagnostic?)
    }

    let source: Source
    let local: Local
}

/// Runs the optional model call under a hard timeout and returns the local
/// deterministic answer whenever the model can't be trusted. The local answer
/// is computed up front, so there is always something safe to return.
struct FuelBuddyGate<Local: Equatable> {
    var provider: FuelBuddyLLMProvider?
    var clock: any Clock<Duration> = ContinuousClock()

    func answer(
        request: FuelBuddyLLMRequest,
        local: Local,
        passesCurrentRules: @escaping (String) -> Bool
    ) async -> FuelBuddyAnswer<Local> {
        guard let provider else {
            return FuelBuddyAnswer(source: .local(.providerUnavailable), local: local)
        }

        let data: Data
        do {
            data = try await withTimeout(milliseconds: request.limits.timeoutMilliseconds) {
                try await provider.send(request)
            }
        } catch FuelBuddyProviderError.rateLimited {
            return FuelBuddyAnswer(source: .local(.providerRateLimited), local: local)
        } catch is TimeoutError {
            return FuelBuddyAnswer(source: .local(.providerTimeout), local: local)
        } catch {
            return FuelBuddyAnswer(source: .local(.providerUnavailable), local: local)
        }

        let context = FuelBuddyValidationContext(request: request, passesCurrentRules: passesCurrentRules)
        switch FuelBuddyResponseValidator.validate(data: data, context: context) {
        case .success(let validated):
            return FuelBuddyAnswer(source: .model(validated), local: local)
        case .failure(let diagnostic):
            return FuelBuddyAnswer(source: .local(diagnostic), local: local)
        }
    }

    struct TimeoutError: Error {}

    private func withTimeout<T: Sendable>(milliseconds: Int, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let clock = self.clock
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await clock.sleep(for: .milliseconds(milliseconds))
                throw TimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
