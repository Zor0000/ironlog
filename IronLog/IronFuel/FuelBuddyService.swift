import Foundation

struct FuelBuddyResult: Equatable {
    enum Source: Equatable { case ai, unavailable, safety }
    let outcome: FuelBuddyOutcome
    let source: Source
}

/// Every eligible request goes to the recipe generator. No catalog lookup or
/// local suggestion fallback is part of the production path.
struct FuelBuddyService {
    var provider: FuelBuddyRecipeProvider?

    func recommend(passport: NutritionPassport?, query: String) async -> FuelBuddyResult {
        guard let passport, passport.isComplete else {
            return .init(outcome: .blocked("Finish your Nutrition Passport first."), source: .safety)
        }
        guard !passport.requiresProfessionalGuidance else {
            return .init(outcome: .routed("Use your clinician or dietitian's plan for personalized food guidance."), source: .safety)
        }
        switch FuelBuddySafetyPolicy.screen(request: query) {
        case .blocked:
            return .init(outcome: .blocked("Fuel Buddy suggests meals. It cannot bypass your dietary rules or provide unsafe dieting, supplement or treatment advice."), source: .safety)
        case .routed:
            return .init(outcome: .routed("This request needs guidance from a qualified clinician or dietitian."), source: .safety)
        case .allowed: break
        }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .init(outcome: .error("Describe the meal you would like."), source: .safety)
        }
        guard let provider else { return unavailable() }
        let request = FuelBuddyGenerationRequest(userText: FuelBuddyRequestRedactor.redact(query), preferences: .init(passport: passport))
        do {
            let data = try await provider.generate(request)
            try Task.checkCancellation()
            let outcome = try FuelBuddyGenerationValidator.validate(data, request: request, passport: passport)
            return .init(outcome: outcome, source: .ai)
        } catch FuelBuddyGenerationError.rateLimited {
            return .init(outcome: .error("Too many requests right now. Please try again in a minute."), source: .unavailable)
        } catch {
            return unavailable()
        }
    }

    private func unavailable() -> FuelBuddyResult {
        .init(outcome: .error("AI suggestions could not be generated. Check your connection and try again."), source: .unavailable)
    }
}

struct FuelBuddyHTTPProvider: FuelBuddyRecipeProvider {
    let endpoint: URL
    let publicKey: String
    let accessToken: @Sendable () async throws -> String
    var session: URLSession = .shared

    func generate(_ request: FuelBuddyGenerationRequest) async throws -> Data {
        var http = URLRequest(url: endpoint)
        http.httpMethod = "POST"
        http.timeoutInterval = 30
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue(publicKey, forHTTPHeaderField: "apikey")
        http.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        http.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await session.data(for: http)
        guard let response = response as? HTTPURLResponse else { throw FuelBuddyGenerationError.unavailable }
        if response.statusCode == 429 { throw FuelBuddyGenerationError.rateLimited }
        guard response.statusCode == 200, data.count <= 24_576 else { throw FuelBuddyGenerationError.unavailable }
        return data
    }
}
