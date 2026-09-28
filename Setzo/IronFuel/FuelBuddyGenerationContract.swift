import Foundation

/// V2 generates new dishes, rather than references to a fixed catalog.
/// Only meal preferences and redacted request text leave the device.
struct FuelBuddyGenerationRequest: Codable, Equatable {
    var schemaVersion = 2
    var policyVersion = FuelBuddySafetyPolicy.version
    var requestID = UUID()
    let userText: FuelBuddyRedactedText
    var maxOptions = 5
    let preferences: Preferences

    struct Preferences: Codable, Equatable {
        let dietaryIdentity: NutritionPassport.DietaryIdentity
        let excludedIngredients: [String]
        let dislikes: [String]
        let preferredCuisines: [String]
        let availableFoods: [String]
        let budget: NutritionPassport.Budget
        let maxCookingMinutes: Int
        let cookingAbility: NutritionPassport.CookingAbility

        init(passport: NutritionPassport) {
            dietaryIdentity = passport.dietaryIdentity
            excludedIngredients = Self.clean(passport.allergies + passport.intolerances + passport.exclusions + passport.neverSuggest)
            dislikes = Self.clean(passport.dislikes)
            preferredCuisines = Self.clean(passport.preferredCuisines)
            availableFoods = Self.clean(passport.availableFoods)
            budget = passport.budget
            maxCookingMinutes = passport.maxCookingMinutes
            cookingAbility = passport.cookingAbility
        }

        private static func clean(_ values: [String]) -> [String] {
            values.map { FuelBuddyRequestRedactor.redact($0).value.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }
}

struct FuelBuddyGenerationResponse: Codable, Equatable {
    enum Status: String, Codable { case ok, noMatch = "no_match" }
    let schemaVersion: Int
    let requestID: UUID
    let status: Status
    let options: [Dish]

    /// Hidden metadata supports checks. The product displays `name` only.
    struct Dish: Codable, Equatable {
        let name: String
        let mealType: FuelBuddyMealContext.MealType
        let cuisine: String
        let prepMinutes: Int
        let ingredients: [String]
        let proteinSources: [String]
        let dietaryTags: [String]
        let cookingAbility: NutritionPassport.CookingAbility
        let budget: NutritionPassport.Budget

        var option: FuelOption {
            FuelOption(id: name.lowercased(), name: name, cuisine: cuisine,
                       prepMinutes: prepMinutes, budget: budget, ingredients: Set(ingredients),
                       ruleTags: Set(dietaryTags), approvedFacts: [], mealTypes: [mealType.rawValue],
                       cookingAbility: cookingAbility)
        }
    }
}

enum FuelBuddyGenerationValidator {
    static func validate(_ data: Data, request: FuelBuddyGenerationRequest, passport: NutritionPassport) throws -> FuelBuddyOutcome {
        guard data.count <= 24_576 else { throw FuelBuddyGenerationError.invalidResponse }
        let response = try JSONDecoder().decode(FuelBuddyGenerationResponse.self, from: data)
        guard response.schemaVersion == 2, response.requestID == request.requestID else { throw FuelBuddyGenerationError.invalidResponse }
        if response.status == .noMatch {
            guard response.options.isEmpty else { throw FuelBuddyGenerationError.invalidResponse }
            return .noCompatibleResult
        }
        guard (1...request.maxOptions).contains(response.options.count) else { throw FuelBuddyGenerationError.invalidResponse }
        var names: Set<String> = []
        let allowedTags: Set<String> = ["vegan", "vegetarian", "jain", "halal", "kosher"]
        for dish in response.options {
            let name = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...100).contains(name.count), name == dish.name,
                  name.rangeOfCharacter(from: .newlines) == nil,
                  !name.contains("<"), !name.contains(">"), !name.contains("http"),
                  !FuelBuddySafetyPolicy.containsNumberWithUnit(name.lowercased()),
                  FuelBuddySafetyPolicy.screen(request: name) == .allowed,
                  names.insert(FuelBuddyRequestIntent.words(name).sorted().joined(separator: " ")).inserted,
                  (1...240).contains(dish.prepMinutes), (1...24).contains(dish.ingredients.count),
                  dish.ingredients.allSatisfy({ (1...80).contains($0.count) }),
                  (2...60).contains(dish.cuisine.count),
                  Set(dish.dietaryTags).isSubset(of: allowedTags),
                  Set(dish.proteinSources).isSubset(of: Set(dish.ingredients)),
                  FuelBuddyRecommendationEngine.passesHardRules(dish.option, passport: passport) else {
                throw FuelBuddyGenerationError.invalidResponse
            }
        }
        return .suggestions(response.options.map(\.option))
    }
}

enum FuelBuddyGenerationError: Error { case unavailable, rateLimited, invalidResponse }

protocol FuelBuddyRecipeProvider: Sendable {
    func generate(_ request: FuelBuddyGenerationRequest) async throws -> Data
}
