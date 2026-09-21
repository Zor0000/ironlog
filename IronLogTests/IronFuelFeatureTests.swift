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
