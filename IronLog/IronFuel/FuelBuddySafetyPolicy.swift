import Foundation

/// Deterministic screen that runs on the user's request *before* anything is
/// sent to a model, and on any model text *after* it comes back. It is a
/// keyword/pattern policy on purpose: it must be auditable, versioned, and
/// impossible for a model to talk its way around.
enum FuelBuddySafetyPolicy {
    static let version = "2026-09"

    enum Verdict: Equatable {
        case allowed
        /// The request itself is out of bounds; show refusal copy.
        case blocked(BlockReason)
        /// The request is fine but the person should be routed to
        /// professional guidance rather than a meal list.
        case routed(RoutingReason)
    }

    enum BlockReason: String, Equatable {
        case supplementsOrSteroids
        case diagnosisOrTreatment
        case crashDietOrCompensation
        case allergyBypass
        case dietaryRuleBypass
    }

    enum RoutingReason: String, Equatable {
        case under18
        case pregnancyOrBreastfeeding
        case disorderedEating
        case clinicianManagedDiet
    }

    /// Screen a user request. Routing takes precedence over blocking so a
    /// vulnerable user is pointed at help rather than told "no".
    static func screen(request text: String) -> Verdict {
        let normalized = normalize(text)
        if let routing = routingReason(in: normalized) { return .routed(routing) }
        if let block = blockReason(in: normalized) { return .blocked(block) }
        return .allowed
    }

    /// True when model-authored text contains language the model must never
    /// produce: medical/treatment advice, supplement talk, or invented facts
    /// expressed as numbers with units.
    static func containsForbiddenLanguage(_ text: String) -> Bool {
        let normalized = normalize(text)
        if medicalTerms.contains(where: { normalized.contains($0) }) { return true }
        if supplementTerms.contains(where: { normalized.contains($0) }) { return true }
        return containsNumberWithUnit(normalized)
    }

    /// Nutrient/energy figures are facts the catalog owns; a model stating
    /// one is hallucinating by definition.
    static func containsNumberWithUnit(_ text: String) -> Bool {
        text.range(of: #"\b\d+(\.\d+)?\s?(kcal|cal|calories|calorie|kj|g|grams|gram|mg|mcg|percent)\b|\b\d+(\.\d+)?\s?%"#, options: .regularExpression) != nil
    }

    // MARK: - Vocabulary

    private static let supplementTerms = [
        "supplement", "steroid", "anabolic", "sarm", "creatine", "whey", "protein powder",
        "fat burner", "pre-workout", "preworkout", "testosterone", "clenbuterol", "ozempic", "semaglutide"
    ]
    private static let medicalTerms = [
        "diagnos", "treat my", "treatment", "prescri", "medication", "cure", "dose", "dosage", "heal my"
    ]
    private static let crashDietTerms = [
        "starve", "starving", "fast for", "water fast", "500 calories", "600 calories", "700 calories",
        "800 calories", "lose 10 kg in", "lose 5 kg in", "punish", "burn off", "earn my food",
        "compensate", "purge", "skip meals", "no food for"
    ]
    private static let allergyBypassTerms = [
        "ignore my allerg", "ignore allerg", "despite my allerg", "even though i'm allergic",
        "even though im allergic", "forget my allerg", "override my allerg", "i don't care about my allerg",
        "ignore my intoleran", "despite my intoleran"
    ]
    private static let ruleBypassTerms = [
        "ignore halal", "ignore kosher", "ignore my religio", "not really vegetarian", "not really vegan",
        "ignore vegetarian", "ignore vegan", "cheat on my", "ignore my exclusion", "ignore my restriction",
        "break my fast early", "ignore my diet rule"
    ]
    private static let under18Terms = ["my kid", "my child", "my son", "my daughter", "for a teenager", "for my teen", "school lunch for my"]
    private static let pregnancyTerms = ["pregnan", "breastfeed", "breast feed", "nursing my", "trimester"]
    private static let disorderedEatingTerms = ["anorexi", "bulimi", "binge", "eating disorder", "purging", "hate my body", "feel fat", "too fat to eat"]
    // Conditions where a meal list is the wrong answer: route to the person
    // managing the diet instead of blocking or guessing.
    private static let clinicianTerms = [
        "dietitian", "dietician", "nutritionist told", "doctor told", "doctor said", "renal diet", "dialysis",
        "chemo", "tube feed", "low fodmap for my", "celiac", "coeliac", "insulin", "thyroid", "diabet",
        "cholesterol", "blood pressure", "kidney disease", "liver disease"
    ]

    private static func routingReason(in text: String) -> RoutingReason? {
        if pregnancyTerms.contains(where: { text.contains($0) }) { return .pregnancyOrBreastfeeding }
        if disorderedEatingTerms.contains(where: { text.contains($0) }) { return .disorderedEating }
        if clinicianTerms.contains(where: { text.contains($0) }) { return .clinicianManagedDiet }
        if isUnder18(text) { return .under18 }
        return nil
    }

    private static func blockReason(in text: String) -> BlockReason? {
        if allergyBypassTerms.contains(where: { text.contains($0) }) { return .allergyBypass }
        if ruleBypassTerms.contains(where: { text.contains($0) }) { return .dietaryRuleBypass }
        if supplementTerms.contains(where: { text.contains($0) }) { return .supplementsOrSteroids }
        if medicalTerms.contains(where: { text.contains($0) }) { return .diagnosisOrTreatment }
        if crashDietTerms.contains(where: { text.contains($0) }) { return .crashDietOrCompensation }
        return nil
    }

    /// "I am 15", "for my 12 year old", "my kid" — anything that says the
    /// eater is a minor.
    private static func isUnder18(_ text: String) -> Bool {
        if text.range(of: #"\b(i am|i'm|im|age|aged)\s(1[0-7]|[1-9])\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"\b(1[0-7]|[1-9])[\s-]?(years?|yrs?)[\s-]?old\b"#, options: .regularExpression) != nil { return true }
        return under18Terms.contains(where: { text.contains($0) })
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
