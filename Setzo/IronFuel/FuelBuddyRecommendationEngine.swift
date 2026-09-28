import Foundation

enum FuelBuddyRecommendationEngine {
    static let catalog: [FuelOption] = [
        FuelOption(id: "chana-rice", name: "Chana masala with rice", cuisine: "Indian", prepMinutes: 25, budget: .value,
                   ingredients: ["chickpea", "tomato", "onion", "rice", "cumin", "oil"], ruleTags: ["vegan", "vegetarian", "halal"],
                   approvedFacts: ["25 minutes · cooked chickpeas", "Value budget"], mealTypes: ["lunch", "dinner"], mealTags: ["hearty"],
                   preparation: "Cook rice. Soften chopped onion and tomato in a little oil with cumin, stir in cooked chickpeas and water, and simmer. Serve with the rice.",
                   recipeIngredients: ["cooked chickpeas", "rice", "tomato", "onion", "cumin", "oil"]),
        FuelOption(id: "paneer-roti", name: "Paneer bhurji with roti", cuisine: "Indian", prepMinutes: 20, budget: .flexible,
                   ingredients: ["milk", "paneer", "wheat", "roti", "tomato", "onion", "oil"], ruleTags: ["vegetarian", "halal"],
                   approvedFacts: ["20 minutes · ready-made roti", "Basic cooking"], mealTypes: ["breakfast", "lunch", "dinner"], mealTags: ["hearty"],
                   preparation: "Soften onion and tomato in a little oil. Stir in crumbled paneer and heat through. Warm the ready-made roti and serve alongside.",
                   recipeIngredients: ["paneer", "ready-made roti", "tomato", "onion", "oil"]),
        FuelOption(id: "tofu-bowl", name: "Ginger tofu rice bowl", cuisine: "East Asian", prepMinutes: 20, budget: .flexible,
                   ingredients: ["soy", "tofu", "rice", "ginger", "oil"], ruleTags: ["vegan", "vegetarian", "halal"],
                   approvedFacts: ["20 minutes", "One-bowl meal"], mealTypes: ["lunch", "dinner"], mealTags: ["hearty"],
                   preparation: "Cook rice. Pan-cook cubed tofu in a little oil with grated ginger until heated through, then serve over rice.",
                   recipeIngredients: ["tofu", "rice", "ginger", "oil"]),
        FuelOption(id: "chicken-wrap", name: "Chicken hummus wrap", cuisine: "Mediterranean", prepMinutes: 15, budget: .flexible,
                   ingredients: ["chicken", "chickpea", "sesame", "wheat", "hummus"], ruleTags: ["halal"],
                   approvedFacts: ["15 minutes · pre-cooked chicken", "No stove required"], mealTypes: ["lunch", "dinner"], mealTags: ["hearty"], cookingAbility: .assemble,
                   preparation: "Use ready-to-eat cooked chicken. Spread hummus on a wheat wrap, add the chicken, and roll. Check chicken sourcing against your dietary rules.",
                   recipeIngredients: ["ready-to-eat cooked chicken", "hummus", "wheat wrap"]),
        FuelOption(id: "yogurt-oats", name: "Fruit and yogurt oats", cuisine: "Everyday", prepMinutes: 5, budget: .value,
                   ingredients: ["milk", "yogurt", "oats", "banana"], ruleTags: ["vegetarian", "halal"],
                   approvedFacts: ["5 minutes · ready-to-eat oats", "No stove required", "Value budget"], mealTypes: ["breakfast", "snack"], mealTags: ["hearty"], cookingAbility: .assemble,
                   preparation: "Mix ready-to-eat oats with yogurt and sliced banana. Let the oats soften to your preferred texture before serving.",
                   recipeIngredients: ["ready-to-eat oats", "plain yogurt", "banana"]),
        FuelOption(id: "jain-poha", name: "Jain vegetable poha", cuisine: "Indian", prepMinutes: 20, budget: .value,
                   ingredients: ["rice flakes", "peas", "peanut", "cumin", "oil"], ruleTags: ["vegan", "vegetarian", "jain", "halal"],
                   approvedFacts: ["20 minutes", "Value budget"], mealTypes: ["breakfast", "snack"], mealTags: ["light"],
                   preparation: "Rinse and drain rice flakes. Heat a little oil with cumin, cook peas and peanuts, then fold in the softened flakes and heat through.",
                   recipeIngredients: ["rice flakes", "peas", "peanuts", "cumin", "oil"]),
        FuelOption(id: "salmon-potato", name: "Salmon with potatoes", cuisine: "European", prepMinutes: 30, budget: .flexible,
                   ingredients: ["fish", "salmon", "potato", "oil"], ruleTags: ["kosher"],
                   approvedFacts: ["30 minutes", "Confident cooking"], mealTypes: ["lunch", "dinner"], mealTags: ["hearty"], cookingAbility: .confident,
                   preparation: "Cut potatoes into small pieces and roast with a little oil. Add salmon and cook until the fish and potatoes are fully cooked. Check sourcing against your dietary rules.",
                   recipeIngredients: ["salmon", "potatoes", "oil"]),
        FuelOption(id: "egg-rice", name: "Quick egg fried rice", cuisine: "Indian", prepMinutes: 15, budget: .value,
                   ingredients: ["egg", "rice", "peas", "onion", "oil"], ruleTags: ["halal"],
                   approvedFacts: ["15 minutes · pre-cooked rice", "Value budget"], mealTypes: ["breakfast", "lunch", "dinner"], mealTags: ["hearty"],
                   preparation: "Use freshly cooked or properly chilled cooked rice. Soften onion and peas in a little oil, add beaten egg and cook through. Stir in rice and heat until steaming throughout.",
                   recipeIngredients: ["eggs", "cooked rice", "peas", "onion", "oil"]),
        FuelOption(id: "egg-toast", name: "Eggs on toast with yogurt", cuisine: "Everyday", prepMinutes: 10, budget: .value,
                   ingredients: ["egg", "wheat", "bread", "milk", "yogurt", "oil"], ruleTags: ["halal"],
                   approvedFacts: ["10 minutes", "Toast, eggs and a yogurt side", "Value budget"], mealTypes: ["breakfast"], mealTags: ["hearty"],
                   preparation: "Toast the bread. Scramble eggs in a little oil until fully cooked, serve on the toast, and add plain yogurt on the side.",
                   recipeIngredients: ["eggs", "bread", "plain yogurt", "oil"]),
        FuelOption(id: "besan-chilla", name: "Besan chilla with tomato", cuisine: "Indian", prepMinutes: 20, budget: .value,
                   ingredients: ["chickpea", "tomato", "onion", "cumin", "oil"], ruleTags: ["vegan", "vegetarian", "halal"],
                   approvedFacts: ["20 minutes", "Chickpea-flour pancakes", "Value budget"], mealTypes: ["breakfast", "lunch"], mealTags: ["hearty"],
                   preparation: "Whisk chickpea flour with water and cumin into a pourable batter. Fold in chopped onion and tomato. Spread in a lightly oiled pan and cook on both sides until the center is set.",
                   recipeIngredients: ["chickpea flour (besan)", "tomato", "onion", "cumin", "oil"])
    ]

    static func recommend(passport: NutritionPassport?, query: String, isOffline: Bool = false, intent: FuelBuddyRequestIntent? = nil) -> FuelBuddyOutcome {
        guard let passport, passport.isComplete else {
            return .blocked("Finish your Nutrition Passport before requesting personalized options.")
        }
        guard !passport.requiresProfessionalGuidance else {
            return .routed("Your Passport calls for professional guidance. Use advice from your clinician or dietitian rather than personalized app suggestions.")
        }

        switch FuelBuddySafetyPolicy.screen(request: query) {
        case .blocked(let reason):
            return .blocked(blockedCopy(reason))
        case .routed:
            return .routed("This request needs support from a qualified clinician or dietitian. Fuel Buddy will not improvise a recommendation.")
        case .allowed:
            break
        }

        // Free text is not a reliable source of structured dietary constraints.
        // Fail closed and ask the user to save them before offering catalog food.
        let restrictionPattern = #"\b(allerg\w*|intoleran\w*|celiac|coeliac|gluten|dairy|lactose|vegan|vegetarian|jain|halal|kosher|avoid\w*|without|exclude\w*|restrict\w*|sensitiv\w*|react\w*|omit\w*|except|pescatarian|pescetarian|no|not|free|cannot|can.t|don.t|won.t)\b"#
        if query.range(of: restrictionPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return .blocked("Save any allergies or dietary restrictions in your Nutrition Passport first, then request a meal without restriction instructions. Fuel Buddy cannot safely interpret those instructions from free text.")
        }

        let resolved = intent ?? FuelBuddyRequestIntent.parse(query, catalog: catalog)
        let matches = catalog
            .filter { passesHardRules($0, passport: passport) }
            .filter { resolved.matches($0) }
            .sorted { lhs, rhs in
                let lhsScore = preferenceScore(lhs, passport: passport)
                let rhsScore = preferenceScore(rhs, passport: passport)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                if lhs.prepMinutes != rhs.prepMinutes { return lhs.prepMinutes < rhs.prepMinutes }
                return lhs.id < rhs.id
            }

        guard !matches.isEmpty else { return .noCompatibleResult }
        let result = Array(matches.prefix(3))
        return isOffline ? .offline(result) : .suggestions(result)
    }

    static func passesHardRules(_ option: FuelOption, passport: NutritionPassport) -> Bool {
        let identityAllowed: Bool = switch passport.dietaryIdentity {
        case .omnivore: true
        case .vegetarian: option.ruleTags.contains("vegetarian")
        case .vegan: option.ruleTags.contains("vegan")
        case .jain: option.ruleTags.contains("jain")
        case .halal: option.ruleTags.contains("halal")
        case .kosher: option.ruleTags.contains("kosher")
        }
        guard identityAllowed else { return false }

        let forbidden = (passport.allergies + passport.intolerances + passport.exclusions + passport.neverSuggest)
            .map(normalize)
            .filter { !$0.isEmpty }
        let optionTerms = option.ingredients.map(normalize) + [normalize(option.name)]
        guard !forbidden.contains(where: { rule in optionTerms.contains(where: { matchesRule(rule, ingredient: $0) }) }) else {
            return false
        }
        guard option.prepMinutes <= passport.maxCookingMinutes else { return false }
        if passport.budget == .value, option.budget != .value { return false }
        switch passport.cookingAbility {
        case .assemble: return option.cookingAbility == .assemble
        case .basic: return option.cookingAbility != .confident
        case .confident: return true
        }
    }

    private static func preferenceScore(_ option: FuelOption, passport: NutritionPassport) -> Int {
        let available = FuelBuddyRequestIntent.words(passport.availableFoods.joined(separator: " "))
        let ingredients = FuelBuddyRequestIntent.words(option.ingredients.joined(separator: " "))
        let preferredCuisine = passport.preferredCuisines.contains { option.cuisine.localizedCaseInsensitiveContains($0) }
        let disliked = passport.dislikes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .contains { dislike in option.ingredients.contains { matchesRule(normalize(dislike), ingredient: normalize($0)) } }
        return (preferredCuisine ? 4 : 0) + available.intersection(ingredients).count * 2 - (disliked ? 10 : 0)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Match common food-family names as well as ingredient spellings. A
    /// simple substring check misses "dairy" versus milk or "groundnut"
    /// versus peanut. This remains a catalog filter, not a label or
    /// cross-contact verification for a prepared food.
    private static func matchesRule(_ rule: String, ingredient: String) -> Bool {
        let singular = rule.hasSuffix("s") && rule.count > 3 ? String(rule.dropLast()) : rule
        if ingredient.contains(rule) || rule.contains(ingredient)
            || ingredient.contains(singular) || singular.contains(ingredient) { return true }
        let families: [Set<String>] = [
            ["dairy", "milk", "lactose", "paneer", "yogurt", "curd", "cheese"],
            ["gluten", "wheat", "roti", "wrap", "oat"],
            ["soy", "soya", "tofu"],
            ["peanut", "groundnut", "nut"],
            ["chickpea", "garbanzo", "hummus"],
            ["sesame", "tahini"],
            ["fish", "seafood", "salmon"]
        ]
        return families.contains { family in
            (family.contains(rule) || family.contains(singular)) && ingredient.split(whereSeparator: { !$0.isLetter }).contains { word in
                let term = String(word)
                let singularTerm = term.hasSuffix("s") && term.count > 3 ? String(term.dropLast()) : term
                return family.contains(term) || family.contains(singularTerm)
            }
        }
    }

    private static func blockedCopy(_ reason: FuelBuddySafetyPolicy.BlockReason) -> String {
        switch reason {
        case .supplementsOrSteroids: "Fuel Buddy only suggests catalog foods, not supplements or steroids."
        case .diagnosisOrTreatment: "Fuel Buddy cannot diagnose or treat a condition. Please ask a qualified clinician."
        case .crashDietOrCompensation: "Fuel Buddy will not use food as punishment or support unsafe restriction."
        case .allergyBypass: "Passport allergies are hard rules and cannot be overridden."
        case .dietaryRuleBypass: "Passport belief and dietary rules are hard rules and cannot be overridden."
        }
    }
}
