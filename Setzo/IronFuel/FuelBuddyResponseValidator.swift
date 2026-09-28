import Foundation

/// Why a model response was thrown away. Non-sensitive by construction: it
/// carries no string from the user, the model or the catalog — only fixed
/// codes and small integers — so it can be logged as-is.
enum FuelBuddyDiagnostic: Error, Equatable, Hashable {
    // Request side
    case blockedByPolicy(FuelBuddySafetyPolicy.BlockReason)
    case routedByPolicy(FuelBuddySafetyPolicy.RoutingReason)
    case requestNotRedacted
    case policyVersionMismatch
    case noCandidates
    case tooManyCandidates(count: Int)
    // Transport
    case providerUnavailable
    case providerTimeout
    case providerRateLimited
    // Shape
    case responseTooLarge(bytes: Int)
    case malformedJSON
    case schemaVersionMismatch(received: Int)
    case requestIDMismatch
    case inconsistentStatus
    case modelDeclined
    // Content
    case tooManyFoods(count: Int)
    case orderMismatch
    case unknownFoodID
    case duplicateFoodID
    case foodFailsCurrentRules
    case unapprovedFact
    case unapprovedTag
    case forbiddenLanguage
    case textTooLong

    /// Stable string for logs and metrics.
    var code: String {
        switch self {
        case .blockedByPolicy(let reason): return "blocked_by_policy:\(reason.rawValue)"
        case .routedByPolicy(let reason): return "routed_by_policy:\(reason.rawValue)"
        case .requestNotRedacted: return "request_not_redacted"
        case .policyVersionMismatch: return "policy_version_mismatch"
        case .noCandidates: return "no_candidates"
        case .tooManyCandidates: return "too_many_candidates"
        case .providerUnavailable: return "provider_unavailable"
        case .providerTimeout: return "provider_timeout"
        case .providerRateLimited: return "provider_rate_limited"
        case .responseTooLarge: return "response_too_large"
        case .malformedJSON: return "malformed_json"
        case .schemaVersionMismatch: return "schema_version_mismatch"
        case .requestIDMismatch: return "request_id_mismatch"
        case .inconsistentStatus: return "inconsistent_status"
        case .modelDeclined: return "model_declined"
        case .tooManyFoods: return "too_many_foods"
        case .orderMismatch: return "order_mismatch"
        case .unknownFoodID: return "unknown_food_id"
        case .duplicateFoodID: return "duplicate_food_id"
        case .foodFailsCurrentRules: return "food_fails_current_rules"
        case .unapprovedFact: return "unapproved_fact"
        case .unapprovedTag: return "unapproved_tag"
        case .forbiddenLanguage: return "forbidden_language"
        case .textTooLong: return "text_too_long"
        }
    }
}

// MARK: - Validated results

/// A validated presentation answer. Constructed only by the validator, so
/// holding one is proof the contract was enforced.
struct FuelBuddyValidatedPresentation: Equatable {
    struct Food: Equatable {
        let foodID: String
        let displayName: String
        /// Facts the model chose to highlight; all from the catalog.
        let rationaleFacts: [String]
        let tradeOffFacts: [String]
    }

    let requestID: UUID
    /// In request order — the model cannot change it.
    let foods: [Food]
    /// Screened caption copy; carries no facts the UI relies on.
    let explanation: String
}

struct FuelBuddyValidatedIntent: Equatable {
    let requestID: UUID
    let mealContext: FuelBuddyMealContext
}

/// Everything the validator needs to know about the deterministic world at
/// the moment the response arrives.
struct FuelBuddyValidationContext {
    let request: FuelBuddyPresentationRequest
    /// Re-check every returned food against the *current* profile rules —
    /// the request's candidate list may be stale if the profile changed
    /// mid-flight. Return false to reject the food.
    let passesCurrentRules: (String) -> Bool
}

/// Parses raw bytes into the versioned contract and rejects anything that
/// could weaken the safety contract. Never repairs a response: a single
/// invalid food or fact fails the whole answer, because trimming silently
/// would change what the explanation refers to.
enum FuelBuddyResponseValidator {
    // MARK: Presentation

    static func validate(data: Data, context: FuelBuddyValidationContext) -> Result<FuelBuddyValidatedPresentation, FuelBuddyDiagnostic> {
        switch decode(FuelBuddyPresentationResponse.self, from: data, limits: context.request.limits, expectedVersion: context.request.schemaVersion) {
        case .failure(let diagnostic): return .failure(diagnostic)
        case .success(let response): return validate(response: response, context: context)
        }
    }

    static func validate(response: FuelBuddyPresentationResponse, context: FuelBuddyValidationContext) -> Result<FuelBuddyValidatedPresentation, FuelBuddyDiagnostic> {
        let request = context.request
        guard response.schemaVersion == request.schemaVersion else {
            return .failure(.schemaVersionMismatch(received: response.schemaVersion))
        }
        guard response.requestID == request.requestID else {
            return .failure(.requestIDMismatch)
        }

        // Shape first: a decline with foods attached, or an ok with a reason,
        // is a model trying to have it both ways.
        switch response.status {
        case .declined:
            guard response.foods.isEmpty, response.tradeOffs.isEmpty, response.declineReason != nil else {
                return .failure(.inconsistentStatus)
            }
            // The policy already allowed this request; a model refusal is a
            // fallback, never a decision.
            return .failure(.modelDeclined)
        case .ok:
            guard !response.foods.isEmpty, response.declineReason == nil else { return .failure(.inconsistentStatus) }
        }

        guard response.foods.count <= request.limits.maxFoods else {
            return .failure(.tooManyFoods(count: response.foods.count))
        }

        // The model may not choose, reorder or omit: `foods` must be exactly
        // the leading candidates in the deterministic order.
        let candidatesByID = Dictionary(request.candidates.map { ($0.foodID, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        for food in response.foods {
            guard candidatesByID[food.foodID] != nil else { return .failure(.unknownFoodID) }
            guard seen.insert(food.foodID).inserted else { return .failure(.duplicateFoodID) }
        }
        guard response.foods.map(\.foodID) == request.candidateFoodIDs.prefix(response.foods.count).map({ $0 }) else {
            return .failure(.orderMismatch)
        }

        // Facts can only point back at what the request supplied.
        var tradeOffsByFood: [String: [String]] = [:]
        for tradeOff in response.tradeOffs {
            guard seen.contains(tradeOff.foodID), let candidate = candidatesByID[tradeOff.foodID] else { return .failure(.unknownFoodID) }
            guard candidate.facts.contains(tradeOff.fact) else { return .failure(.unapprovedFact) }
            tradeOffsByFood[tradeOff.foodID, default: []].append(tradeOff.fact)
        }

        var validated: [FuelBuddyValidatedPresentation.Food] = []
        for food in response.foods {
            let candidate = candidatesByID[food.foodID]!
            guard context.passesCurrentRules(food.foodID) else { return .failure(.foodFailsCurrentRules) }
            guard Set(food.rationaleFacts).isSubset(of: candidate.facts) else { return .failure(.unapprovedFact) }
            validated.append(FuelBuddyValidatedPresentation.Food(
                foodID: food.foodID,
                displayName: candidate.displayName,
                rationaleFacts: food.rationaleFacts,
                tradeOffFacts: tradeOffsByFood[food.foodID] ?? []
            ))
        }

        if response.explanation.count > FuelBuddyLLMContract.maxExplanationLength { return .failure(.textTooLong) }
        if FuelBuddySafetyPolicy.containsForbiddenLanguage(response.explanation) { return .failure(.forbiddenLanguage) }

        return .success(FuelBuddyValidatedPresentation(requestID: response.requestID, foods: validated, explanation: response.explanation))
    }

    // MARK: Intent

    static func validate(data: Data, request: FuelBuddyIntentRequest) -> Result<FuelBuddyValidatedIntent, FuelBuddyDiagnostic> {
        switch decode(FuelBuddyIntentResponse.self, from: data, limits: request.limits, expectedVersion: request.schemaVersion) {
        case .failure(let diagnostic): return .failure(diagnostic)
        case .success(let response): return validate(response: response, request: request)
        }
    }

    static func validate(response: FuelBuddyIntentResponse, request: FuelBuddyIntentRequest) -> Result<FuelBuddyValidatedIntent, FuelBuddyDiagnostic> {
        guard response.schemaVersion == request.schemaVersion else {
            return .failure(.schemaVersionMismatch(received: response.schemaVersion))
        }
        guard response.requestID == request.requestID else { return .failure(.requestIDMismatch) }
        switch response.status {
        case .declined:
            guard response.mealContext == nil else { return .failure(.inconsistentStatus) }
            return .failure(.modelDeclined)
        case .ok:
            guard let context = response.mealContext else { return .failure(.inconsistentStatus) }
            guard Set(context.cuisines).isSubset(of: request.knownCuisines),
                  Set(context.mealTags).isSubset(of: request.knownMealTags),
                  context.cuisines.allSatisfy({ $0.count <= FuelBuddyLLMContract.maxTagLength }),
                  context.mealTags.allSatisfy({ $0.count <= FuelBuddyLLMContract.maxTagLength }) else {
                return .failure(.unapprovedTag)
            }
            if let minutes = context.maxPrepMinutes, minutes < 0 { return .failure(.inconsistentStatus) }
            return .success(FuelBuddyValidatedIntent(requestID: response.requestID, mealContext: context))
        }
    }

    // MARK: Shared decoding

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, limits: FuelBuddyRequestLimits, expectedVersion: Int) -> Result<T, FuelBuddyDiagnostic> {
        guard data.count <= limits.maxResponseBytes else {
            return .failure(.responseTooLarge(bytes: data.count))
        }
        // Peek at the version before decoding the whole thing so an unknown
        // future schema is reported as such rather than as "malformed".
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.malformedJSON)
        }
        if let version = object["schemaVersion"] as? Int, version != expectedVersion {
            return .failure(.schemaVersionMismatch(received: version))
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return .failure(.malformedJSON)
        }
        return .success(decoded)
    }
}

// MARK: - Gate: screen, sanitise, call under a timeout, fall back

/// Abstract model transport. The real implementation calls the Supabase Edge
/// Function with the user's session token; tests use closures.
protocol FuelBuddyLLMProvider: Sendable {
    func send(_ request: FuelBuddyPresentationRequest) async throws -> Data
    func send(_ request: FuelBuddyIntentRequest) async throws -> Data
}

enum FuelBuddyProviderError: Error, Equatable {
    case unavailable
    case rateLimited
}

/// What the user ultimately gets, and where it came from.
struct FuelBuddyAnswer<Model: Equatable, Local: Equatable>: Equatable {
    enum Source: Equatable {
        case model(Model)
        case local(FuelBuddyDiagnostic?)
    }

    let source: Source
    let local: Local
}

/// Runs an optional model call and returns the local deterministic answer
/// whenever the model can't be used or trusted. The local answer is computed
/// up front, so there is always something safe to return. The gate is the
/// *only* path to a provider, and it screens and sanitises before sending:
/// application code cannot bypass the policy by calling the provider itself.
struct FuelBuddyGate {
    var provider: FuelBuddyLLMProvider?
    var clock: any Clock<Duration> = ContinuousClock()

    func presentation<Local: Equatable>(
        request: FuelBuddyPresentationRequest,
        local: Local,
        passesCurrentRules: @escaping (String) -> Bool
    ) async -> FuelBuddyAnswer<FuelBuddyValidatedPresentation, Local> {
        if let diagnostic = preflight(userText: request.userText, policyVersion: request.policyVersion) {
            return FuelBuddyAnswer(source: .local(diagnostic), local: local)
        }
        guard !request.candidates.isEmpty else { return FuelBuddyAnswer(source: .local(.noCandidates), local: local) }
        guard request.candidates.count <= FuelBuddyLLMContract.maxCandidates,
              request.candidates.allSatisfy({ $0.facts.count <= FuelBuddyLLMContract.maxFactsPerCandidate }) else {
            return FuelBuddyAnswer(source: .local(.tooManyCandidates(count: request.candidates.count)), local: local)
        }
        guard let provider else { return FuelBuddyAnswer(source: .local(.providerUnavailable), local: local) }

        switch await transport(timeoutMilliseconds: request.limits.timeoutMilliseconds, { try await provider.send(request) }) {
        case .failure(let diagnostic):
            return FuelBuddyAnswer(source: .local(diagnostic), local: local)
        case .success(let data):
            let context = FuelBuddyValidationContext(request: request, passesCurrentRules: passesCurrentRules)
            switch FuelBuddyResponseValidator.validate(data: data, context: context) {
            case .success(let validated): return FuelBuddyAnswer(source: .model(validated), local: local)
            case .failure(let diagnostic): return FuelBuddyAnswer(source: .local(diagnostic), local: local)
            }
        }
    }

    func intent<Local: Equatable>(
        request: FuelBuddyIntentRequest,
        local: Local
    ) async -> FuelBuddyAnswer<FuelBuddyValidatedIntent, Local> {
        if let diagnostic = preflight(userText: request.userText, policyVersion: request.policyVersion) {
            return FuelBuddyAnswer(source: .local(diagnostic), local: local)
        }
        guard let provider else { return FuelBuddyAnswer(source: .local(.providerUnavailable), local: local) }

        switch await transport(timeoutMilliseconds: request.limits.timeoutMilliseconds, { try await provider.send(request) }) {
        case .failure(let diagnostic):
            return FuelBuddyAnswer(source: .local(diagnostic), local: local)
        case .success(let data):
            switch FuelBuddyResponseValidator.validate(data: data, request: request) {
            case .success(let validated): return FuelBuddyAnswer(source: .model(validated), local: local)
            case .failure(let diagnostic): return FuelBuddyAnswer(source: .local(diagnostic), local: local)
            }
        }
    }

    /// The deterministic checks every outbound request must pass: the policy
    /// verdict, and text that is actually in redacted form and within the
    /// contract limit.
    private func preflight(userText: FuelBuddyRedactedText, policyVersion: String) -> FuelBuddyDiagnostic? {
        guard policyVersion == FuelBuddySafetyPolicy.version else { return .policyVersionMismatch }
        guard FuelBuddyRequestRedactor.isRedacted(userText.value) else { return .requestNotRedacted }
        switch FuelBuddySafetyPolicy.screen(request: userText.value) {
        case .allowed: return nil
        case .blocked(let reason): return .blockedByPolicy(reason)
        case .routed(let reason): return .routedByPolicy(reason)
        }
    }

    /// Races the provider against the clock. The provider runs in its own
    /// task and is *not* awaited after the deadline, so a transport that
    /// ignores cancellation cannot hold the answer hostage.
    private func transport(timeoutMilliseconds: Int, _ operation: @escaping @Sendable () async throws -> Data) async -> Result<Data, FuelBuddyDiagnostic> {
        let clock = self.clock
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Data, FuelBuddyDiagnostic>, Never>) in
            let gate = FirstResult(continuation)
            let work = Task {
                do {
                    let data = try await operation()
                    await gate.resume(with: .success(data))
                } catch FuelBuddyProviderError.rateLimited {
                    await gate.resume(with: .failure(.providerRateLimited))
                } catch {
                    await gate.resume(with: .failure(.providerUnavailable))
                }
            }
            Task {
                try? await clock.sleep(for: .milliseconds(timeoutMilliseconds))
                if await gate.resume(with: .failure(.providerTimeout)) {
                    work.cancel() // best effort; we don't wait for it
                }
            }
        }
        return outcome
    }

    /// Resumes a continuation at most once, whichever racer gets there first.
    private actor FirstResult {
        private var continuation: CheckedContinuation<Result<Data, FuelBuddyDiagnostic>, Never>?

        init(_ continuation: CheckedContinuation<Result<Data, FuelBuddyDiagnostic>, Never>) {
            self.continuation = continuation
        }

        /// Returns true when this call won the race.
        @discardableResult
        func resume(with result: Result<Data, FuelBuddyDiagnostic>) -> Bool {
            guard let continuation else { return false }
            self.continuation = nil
            continuation.resume(returning: result)
            return true
        }
    }
}
