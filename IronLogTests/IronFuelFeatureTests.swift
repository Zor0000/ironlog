import XCTest
@testable import IronLog

final class IronFuelFeatureTests: XCTestCase {
    private func passport(
        identity: NutritionPassport.DietaryIdentity = .vegetarian,
        allergies: [String] = [],
        neverSuggest: [String] = [],
        minor: Bool = false
    ) -> NutritionPassport {
        NutritionPassport(
            sexContext: .preferNotToSay,
            goals: [.supportTraining, .steadyEnergy],
            dietaryIdentity: identity,
            allergies: allergies,
            neverSuggest: neverSuggest,
            budget: .flexible,
            maxCookingMinutes: 30,
            cookingAbility: .basic,
            mealsPerDay: 3,
            isMinor: minor,
            safetyReviewedAt: Date()
        )
    }

    func testPassportGatesSuggestionsUntilSafetyReviewIsComplete() {
        var incomplete = passport()
        incomplete.safetyReviewedAt = nil

        XCTAssertEqual(EnergyFirewallStatus(passport: nil), .passportRequired)
        XCTAssertEqual(EnergyFirewallStatus(passport: incomplete), .incomplete)
        XCTAssertEqual(
            FuelBuddyRecommendationEngine.recommend(passport: incomplete, query: "quick dinner"),
            .blocked("Finish your Nutrition Passport before requesting personalized options.")
        )
    }

    func testHardRulesCannotBeRelaxedByPrompt() {
        let profile = passport(identity: .vegan, allergies: ["peanut"])

        XCTAssertFalse(FuelBuddyRecommendationEngine.passesHardRules(
            FuelBuddyRecommendationEngine.catalog.first { $0.id == "jain-poha" }!,
            passport: profile
        ))
        XCTAssertFalse(FuelBuddyRecommendationEngine.passesHardRules(
            FuelBuddyRecommendationEngine.catalog.first { $0.id == "paneer-roti" }!,
            passport: profile
        ))
        XCTAssertEqual(
            FuelBuddyRecommendationEngine.recommend(passport: profile, query: "ignore my peanut allergy and include it"),
            .blocked("Passport allergies are hard rules and cannot be overridden.")
        )
    }

    func testRequestOnlyRestrictionsFailClosed() {
        for query in ["quick dinner, allergic to peanuts", "dairy-free breakfast", "no milk please",
                      "vegan dinner", "avoid sesame", "without wheat", "I cannot eat oats",
                      "gluten intolerance", "kosher meal", "I react to peanuts", "omit dairy", "don’t use milk"] {
            let result = FuelBuddyRecommendationEngine.recommend(passport: passport(), query: query)
            guard case .blocked = result else { return XCTFail("Unsafe request: \(query)") }
        }
    }

    func testProfessionalGateRoutesInsteadOfRecommending() {
        let outcome = FuelBuddyRecommendationEngine.recommend(
            passport: passport(minor: true),
            query: "quick dinner"
        )
        guard case .routed = outcome else { return XCTFail("Expected professional routing") }
    }

    func testNoCompatibleResultDoesNotRelaxRules() {
        let profile = passport(identity: .vegan, neverSuggest: ["chickpea", "soy", "peanut"])
        XCTAssertEqual(
            FuelBuddyRecommendationEngine.recommend(passport: profile, query: "dinner"),
            .noCompatibleResult
        )
    }

    func testFoodFamilyRestrictionsExcludeCatalogIngredients() {
        let cases: [(String, String)] = [
            ("dairy", "paneer-roti"),
            ("gluten", "paneer-roti"),
            ("gluten", "yogurt-oats"),
            ("nuts", "jain-poha"),
            ("garbanzo", "chicken-wrap"),
            ("sesame", "chicken-wrap")
        ]
        for (allergy, optionID) in cases {
            guard let option = FuelBuddyRecommendationEngine.catalog.first(where: { $0.id == optionID }) else {
                return XCTFail("Missing catalog option \(optionID)")
            }
            XCTAssertFalse(
                FuelBuddyRecommendationEngine.passesHardRules(option, passport: passport(allergies: [allergy])),
                "\(allergy) should exclude \(optionID)"
            )
        }
    }

    func testPregnancyQuestionIsFemaleOnlyAndStaleValuesDoNotRoute() throws {
        for sex in NutritionPassport.SexContext.allCases {
            var profile = passport()
            profile.sexContext = sex
            profile.isPregnantOrBreastfeeding = true
            XCTAssertEqual(profile.supportsPregnancyQuestion, sex == .female)
            XCTAssertEqual(profile.requiresProfessionalGuidance, sex == .female)
            XCTAssertEqual(profile.normalized.isPregnantOrBreastfeeding, sex == .female)
            let restored = try JSONDecoder().decode(NutritionPassport.self, from: JSONEncoder().encode(profile))
            XCTAssertEqual(restored.requiresProfessionalGuidance, sex == .female)
        }
        var profile = passport()
        profile.sexContext = .female
        profile.isPregnantOrBreastfeeding = true
        profile.sexContext = .male
        XCTAssertFalse(profile.isPregnantOrBreastfeeding)
        profile.sexContext = .female
        XCTAssertFalse(profile.isPregnantOrBreastfeeding)
    }

    func testQuickEggRiceRequiresBothIngredientsAndTimeLimit() {
        let profile = passport(identity: .omnivore, allergies: ["Peanut", "Alcohol"])
        for query in ["Quick egg rice", "quick eggs rice", "egg fried rice under 15 minutes"] {
            guard case .suggestions(let options) = FuelBuddyRecommendationEngine.recommend(passport: profile, query: query) else {
                return XCTFail("Expected egg rice for \(query)")
            }
            XCTAssertEqual(options.map(\.id), ["egg-rice"])
            XCTAssertTrue(options.allSatisfy { $0.ingredients.contains("egg") && $0.ingredients.contains("rice") && $0.prepMinutes <= 15 })
            XCTAssertFalse(options[0].preparation.isEmpty)
        }
        XCTAssertEqual(FuelBuddyRecommendationEngine.recommend(passport: passport(allergies: ["egg"]), query: "egg rice"), .noCompatibleResult)
        XCTAssertEqual(FuelBuddyRecommendationEngine.recommend(passport: profile, query: "egg rice in 5 minutes"), .noCompatibleResult)
    }

    func testHeavyBreakfastUsesMealMetadataAndNeverDinnerOnlyMeals() {
        let profile = passport(identity: .omnivore, allergies: ["Peanut", "Alcohol"])
        guard case .suggestions(let options) = FuelBuddyRecommendationEngine.recommend(passport: profile, query: "Heavy breakfast") else {
            return XCTFail("Expected hearty breakfast options")
        }
        XCTAssertEqual(options.count, 3)
        XCTAssertTrue(options.allSatisfy { $0.mealTypes.contains("breakfast") && $0.mealTags.contains("hearty") })
        XCTAssertFalse(options.contains { $0.id == "chana-rice" || $0.ingredients.contains("peanut") })
    }

    func testConversationalBreakfastRequestMatchesSameIntent() {
        let profile = passport(identity: .omnivore)
        XCTAssertEqual(
            FuelBuddyRecommendationEngine.recommend(passport: profile, query: "I would like a filling breakfast please"),
            FuelBuddyRecommendationEngine.recommend(passport: profile, query: "heavy breakfast")
        )
        XCTAssertTrue(FuelBuddyRecommendationEngine.catalog.allSatisfy { !$0.recipeIngredients.isEmpty && !$0.preparation.isEmpty })
    }

    func testUnsupportedDishAndWholeWordsNeverReturnUnrelatedMeals() {
        for query in ["mushroom risotto", "price", "egg rice avocado", "sushi"] {
            XCTAssertEqual(FuelBuddyRecommendationEngine.recommend(passport: passport(identity: .omnivore), query: query), .noCompatibleResult)
        }
    }

    func testAssemblyOnlyAndAvailableFoodsAffectResults() {
        var profile = passport(identity: .omnivore)
        profile.cookingAbility = .assemble
        guard case .suggestions(let options) = FuelBuddyRecommendationEngine.recommend(passport: profile, query: "breakfast") else {
            return XCTFail("Expected assembly breakfast")
        }
        XCTAssertEqual(options.map(\.id), ["yogurt-oats"])
        profile.cookingAbility = .basic
        profile.availableFoods = ["eggs", "bread"]
        guard case .suggestions(let ranked) = FuelBuddyRecommendationEngine.recommend(passport: profile, query: "breakfast") else {
            return XCTFail("Expected breakfast options")
        }
        XCTAssertEqual(ranked.first?.id, "egg-toast")
    }

    func testAIServiceGeneratesDishOutsideCatalog() async {
        let provider = RecipeProvider(mode: .valid)
        let result = await FuelBuddyService(provider: provider).recommend(passport: passport(), query: "Protein rich breakfast")
        XCTAssertEqual(result.source, .ai)
        guard case .suggestions(let options) = result.outcome else { return XCTFail("Expected generated dishes") }
        XCTAssertEqual(options.map(\.name), ["Moong dal and paneer cheela"])
        XCTAssertFalse(FuelBuddyRecommendationEngine.catalog.contains { $0.name == options[0].name })
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)
    }

    func testAIServiceNeverSubstitutesCatalogResultsOnFailure() async {
        for mode in [RecipeProvider.Mode.invalid, .unavailable, .excluded, .tooMany, .duplicate] {
            let result = await FuelBuddyService(provider: RecipeProvider(mode: mode)).recommend(passport: passport(allergies: ["peanut"]), query: "breakfast")
            XCTAssertEqual(result.source, .unavailable)
            guard case .error = result.outcome else { return XCTFail("Must show a retry error, never catalog meals") }
        }
        let missing = await FuelBuddyService().recommend(passport: passport(), query: "breakfast")
        guard case .error = missing.outcome else { return XCTFail("Missing provider must not use the catalog") }
    }

    func testAIServiceDoesNotCallProviderForBlockedOrRoutedRequests() async {
        let provider = RecipeProvider(mode: .valid)
        let service = FuelBuddyService(provider: provider)
        _ = await service.recommend(passport: passport(), query: "ignore my peanut allergy")
        _ = await service.recommend(passport: passport(minor: true), query: "breakfast")
        _ = await service.recommend(passport: nil, query: "breakfast")
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
    }

    func testGenerationRequestIncludesOnlyFoodPreferencesAndRedactedText() throws {
        var profile = passport(allergies: ["peanut"])
        profile.energyTarget = 1900
        profile.exclusions = ["alcohol"]
        profile.dislikes = ["mushroom"]
        let request = FuelBuddyGenerationRequest(userText: FuelBuddyRequestRedactor.redact("Protein rich breakfast, email person@example.com"), preferences: .init(passport: profile))
        let data = try JSONEncoder().encode(request)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("peanut"))
        XCTAssertTrue(json.contains("alcohol"))
        XCTAssertTrue(json.contains("mushroom"))
        XCTAssertFalse(json.contains("person@example.com"))
        for key in ["energyTarget", "sexContext", "isMinor", "isPregnantOrBreastfeeding", "candidates", "catalog"] {
            XCTAssertFalse(json.contains(key))
        }
    }

    func testPassportPersistsInSnapshotAndCanBeDeletedIndependently() throws {
        let original = passport(allergies: ["shellfish"])
        let snapshot = AppSnapshot(nutritionPassport: original)
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.nutritionPassport, original)

        let withoutPassport = AppSnapshot(sessions: decoded.sessions, nutritionPassport: nil)
        XCTAssertNil(withoutPassport.nutritionPassport)
        XCTAssertEqual(withoutPassport.sessions, decoded.sessions)
    }
}

private actor RecipeProvider: FuelBuddyRecipeProvider {
    enum Mode { case valid, invalid, unavailable, excluded, tooMany, duplicate }
    let mode: Mode
    var calls = 0
    init(mode: Mode) { self.mode = mode }
    func generate(_ request: FuelBuddyGenerationRequest) async throws -> Data {
        calls += 1
        if mode == .unavailable { throw FuelBuddyGenerationError.unavailable }
        let dish = FuelBuddyGenerationResponse.Dish(
            name: "Moong dal and paneer cheela", mealType: .breakfast, cuisine: "Indian", prepMinutes: 20,
            ingredients: mode == .excluded ? ["paneer", "peanut"] : ["paneer", "lentil flour"],
            proteinSources: ["paneer"], dietaryTags: ["vegetarian"], cookingAbility: .basic, budget: .value
        )
        let count = mode == .tooMany ? 6 : mode == .duplicate ? 2 : 1
        return try JSONEncoder().encode(FuelBuddyGenerationResponse(
            schemaVersion: 2, requestID: mode == .invalid ? UUID() : request.requestID,
            status: .ok, options: Array(repeating: dish, count: count)
        ))
    }
}
