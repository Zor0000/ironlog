import Foundation

/// Explicit meal/ingredient constraints survive any optional model interpretation.
/// Matching whole tokens keeps short foods (egg, dal) and avoids rice/price matches.
struct FuelBuddyRequestIntent: Equatable {
    var context = FuelBuddyMealContext()
    var ingredients: Set<String> = []
    var unmatchedWords: Set<String> = []

    static let aliases: [String: String] = [
        "eggs": "egg", "anda": "egg", "chana": "chickpea", "chickpeas": "chickpea",
        "garbanzo": "chickpea", "besan": "chickpea", "gram": "chickpea",
        "dal": "lentil", "daal": "lentil", "lentils": "lentil", "dhal": "lentil",
        "soya": "soy", "curd": "yogurt", "yoghurt": "yogurt", "oat": "oats",
        "potatoes": "potato", "tomatoes": "tomato", "onions": "onion",
        "groundnut": "peanut", "peanuts": "peanut", "rotis": "roti",
        "chapati": "roti", "chapatis": "roti", "pancakes": "chilla",
        "toast": "bread", "bananas": "banana", "wraps": "wrap"
    ]

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map {
            aliases[String($0)] ?? String($0)
        })
    }

    static func parse(_ query: String, catalog: [FuelOption]) -> Self {
        var result = Self()
        let tokens = words(query)
        var understood: Set<String> = [
            "a", "an", "the", "i", "me", "my", "please", "suggest", "suggestion", "suggestions",
            "recommend", "recommendation", "recommendations", "find", "give", "want", "need", "some",
            "for", "with", "and", "or", "of", "to", "have", "make", "cook", "can", "you",
            "meal", "meals", "food", "foods", "option", "options", "something", "recipe", "recipes",
            "today", "tonight", "under", "within", "up", "minute", "minutes", "min", "mins",
            "would", "like", "looking", "am", "m", "d", "could", "it", "that", "is", "be",
            "healthy", "balanced", "tasty", "delicious", "homemade", "keep", "feel",
            "in", "at", "most", "than", "less", "fried", "scrambled", "boiled"
        ]
        let mealNames: [(String, Set<String>)] = [
            ("breakfast", ["breakfast", "morning", "brunch"]),
            ("lunch", ["lunch", "midday"]), ("dinner", ["dinner", "supper", "tonight"]),
            ("snack", ["snack", "snacks"])
        ]
        for (meal, names) in mealNames {
            understood.formUnion(names)
            if !tokens.isDisjoint(with: names) { result.context.mealType = .init(rawValue: meal)! }
        }
        let tagNames: [(String, Set<String>)] = [
            ("quick", ["quick", "fast", "speedy", "busy"]),
            ("hearty", ["heavy", "hearty", "filling", "substantial", "big", "full", "satisfying"]),
            ("light", ["light", "small"]), ("simple", ["simple", "easy"])
        ]
        for (tag, names) in tagNames {
            understood.formUnion(names)
            if !tokens.isDisjoint(with: names) { result.context.mealTags.append(tag) }
        }
        if result.context.mealTags.contains("quick") { result.context.maxPrepMinutes = 20 }
        let pattern = #"\b(\d{1,3})\s*(?:min(?:ute)?s?)\b"#
        if let range = query.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
           let minutes = Int(query[range].prefix(while: { $0.isNumber })) {
            result.context.maxPrepMinutes = minutes
        }
        let budgetWords: Set<String> = ["cheap", "budget", "affordable", "inexpensive"]
        understood.formUnion(budgetWords)
        if !tokens.isDisjoint(with: budgetWords) { result.context.budget = .low }
        for cuisine in Set(catalog.map { $0.cuisine.lowercased() }).sorted() {
            let cuisineWords = words(cuisine)
            understood.formUnion(cuisineWords)
            if cuisineWords.isSubset(of: tokens) { result.context.cuisines.append(cuisine) }
        }
        let ingredientWords = catalog.reduce(into: Set<String>()) { $0.formUnion($1.ingredients.flatMap { words($0) }) }
        result.ingredients = tokens.intersection(ingredientWords)
        understood.formUnion(ingredientWords)
        // Dish names such as poha, roti, wraps remain meaningful constraints.
        let dishWords = catalog.reduce(into: Set<String>()) { $0.formUnion(words($1.name)) }.subtracting(understood)
        result.ingredients.formUnion(tokens.intersection(dishWords))
        understood.formUnion(dishWords)
        result.unmatchedWords = tokens.subtracting(understood).filter { Int($0) == nil }
        return result
    }

    func including(_ model: FuelBuddyMealContext) -> Self {
        var merged = self
        if context.mealType == .any { merged.context.mealType = model.mealType }
        if context.cuisines.isEmpty { merged.context.cuisines = model.cuisines }
        merged.context.mealTags = Array(Set(context.mealTags + model.mealTags)).sorted()
        if let minutes = model.maxPrepMinutes {
            merged.context.maxPrepMinutes = min(context.maxPrepMinutes ?? minutes, minutes)
        }
        if context.budget == .any { merged.context.budget = model.budget }
        return merged
    }

    func matches(_ option: FuelOption) -> Bool {
        guard unmatchedWords.isEmpty else { return false }
        guard context.mealType == .any || option.mealTypes.contains(context.mealType.rawValue) else { return false }
        guard context.cuisines.isEmpty || context.cuisines.contains(option.cuisine.lowercased()) else { return false }
        guard context.maxPrepMinutes.map({ option.prepMinutes <= $0 }) ?? true else { return false }
        guard context.budget != .low || option.budget == .value else { return false }
        let requiredTags = Set(context.mealTags).subtracting(["quick", "simple"])
        guard requiredTags.isSubset(of: option.mealTags) else { return false }
        if context.mealTags.contains("simple"), option.cookingAbility == .confident { return false }
        let foodWords = Self.words(([option.name] + option.ingredients.sorted()).joined(separator: " "))
        return ingredients.isSubset(of: foodWords)
    }
}
