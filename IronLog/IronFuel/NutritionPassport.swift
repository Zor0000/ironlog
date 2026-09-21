import Foundation

struct NutritionPassport: Codable, Equatable, Identifiable {
    enum SexContext: String, Codable, CaseIterable, Identifiable {
        case female = "Female"
        case male = "Male"
        case intersex = "Intersex"
        case preferNotToSay = "Prefer not to say"
        var id: Self { self }
    }

    enum Goal: String, Codable, CaseIterable, Identifiable {
        case supportTraining = "Support training"
        case buildMuscle = "Build muscle"
        case improveRecovery = "Improve recovery"
        case steadyEnergy = "Steady energy"
        case weightManagement = "Weight management"
        var id: Self { self }
    }

    enum TargetSource: String, Codable, CaseIterable, Identifiable {
        case selfSelected = "Set by me"
        case dietitian = "Dietitian"
        case clinician = "Clinician"
        case none = "No energy target"
        var id: Self { self }
    }

    enum DietaryIdentity: String, Codable, CaseIterable, Identifiable {
        case omnivore = "No dietary identity"
        case vegetarian = "Vegetarian"
        case vegan = "Vegan"
        case jain = "Jain"
        case halal = "Halal"
        case kosher = "Kosher"
        var id: Self { self }
    }

    enum Budget: String, Codable, CaseIterable, Identifiable {
        case value = "Value"
        case flexible = "Flexible"
        var id: Self { self }
    }

    enum CookingAbility: String, Codable, CaseIterable, Identifiable {
        case assemble = "Assemble only"
        case basic = "Basic cooking"
        case confident = "Confident cook"
        var id: Self { self }
    }

    var id = UUID()
    var sexContext: SexContext?
    var goals: [Goal] = []
    var energyTarget: Int?
    var targetSource: TargetSource = .none
    var dietaryIdentity: DietaryIdentity = .omnivore
    var allergies: [String] = []
    var intolerances: [String] = []
    var exclusions: [String] = []
    var neverSuggest: [String] = []
    var dislikes: [String] = []
    var preferredCuisines: [String] = []
    var budget: Budget = .flexible
    var maxCookingMinutes = 30
    var cookingAbility: CookingAbility = .basic
    var mealsPerDay = 3
    var availableFoods: [String] = []
    var isMinor = false
    var isPregnantOrBreastfeeding = false
    var hasEatingDisorderHistory = false
    var followsPrescribedDiet = false
    var safetyReviewedAt: Date?

    var isComplete: Bool {
        sexContext != nil && !goals.isEmpty && safetyReviewedAt != nil
    }

    var requiresProfessionalGuidance: Bool {
        isMinor || isPregnantOrBreastfeeding || hasEatingDisorderHistory || followsPrescribedDiet
    }

    var goalStack: [String] { goals.map(\.rawValue) }

    var hardRules: [String] {
        let identity = dietaryIdentity == .omnivore ? [] : [dietaryIdentity.rawValue]
        return identity + allergies.map { "Allergy: \($0)" }
            + intolerances.map { "Intolerance: \($0)" }
            + exclusions + neverSuggest.map { "Never: \($0)" }
    }
}

enum EnergyFirewallStatus: Equatable {
    case passportRequired
    case incomplete
    case ready
    case professionalGuidance

    init(passport: NutritionPassport?) {
        guard let passport else { self = .passportRequired; return }
        guard passport.isComplete else { self = .incomplete; return }
        self = passport.requiresProfessionalGuidance ? .professionalGuidance : .ready
    }

    var title: String {
        switch self {
        case .passportRequired: "Passport required"
        case .incomplete: "Safety questions incomplete"
        case .ready: "Energy Firewall active"
        case .professionalGuidance: "Professional guidance route"
        }
    }

    var detail: String {
        switch self {
        case .passportRequired: "Create your private Passport before requesting personalized options."
        case .incomplete: "Finish the safety review to unlock Fuel Buddy."
        case .ready: "Hard rules are checked locally before every option is shown."
        case .professionalGuidance: "Fuel Buddy stays paused while your nutrition needs professional oversight."
        }
    }
}

struct FuelOption: Identifiable, Equatable {
    let id: String
    let name: String
    let cuisine: String
    let prepMinutes: Int
    let budget: NutritionPassport.Budget
    let ingredients: Set<String>
    let ruleTags: Set<String>
    let approvedFacts: [String]
}

enum FuelBuddyOutcome: Equatable {
    case suggestions([FuelOption])
    case noCompatibleResult
    case blocked(String)
    case routed(String)
    case offline([FuelOption])
    case error(String)
}

enum FuelBuddyRecommendationEngine {
    static let catalog: [FuelOption] = [
        FuelOption(id: "chana-rice", name: "Chana masala with rice", cuisine: "Indian", prepMinutes: 25, budget: .value,
                   ingredients: ["chickpea", "tomato", "onion", "rice"], ruleTags: ["vegan", "vegetarian", "halal"],
                   approvedFacts: ["25 minute preparation", "value-friendly pantry ingredients", "Indian cuisine"]),
        FuelOption(id: "paneer-roti", name: "Paneer bhurji with roti", cuisine: "Indian", prepMinutes: 20, budget: .flexible,
                   ingredients: ["milk", "paneer", "wheat", "tomato", "onion"], ruleTags: ["vegetarian", "halal"],
                   approvedFacts: ["20 minute preparation", "Indian cuisine", "requires basic cooking"]),
        FuelOption(id: "tofu-bowl", name: "Ginger tofu rice bowl", cuisine: "East Asian", prepMinutes: 20, budget: .flexible,
                   ingredients: ["soy", "tofu", "rice", "ginger"], ruleTags: ["vegan", "vegetarian", "halal"],
                   approvedFacts: ["20 minute preparation", "East Asian cuisine", "one-bowl meal"]),
        FuelOption(id: "chicken-wrap", name: "Chicken hummus wrap", cuisine: "Mediterranean", prepMinutes: 15, budget: .flexible,
                   ingredients: ["chicken", "sesame", "wheat", "hummus"], ruleTags: ["halal"],
                   approvedFacts: ["15 minute preparation", "Mediterranean cuisine", "assembly-friendly"]),
        FuelOption(id: "yogurt-oats", name: "Fruit and yogurt oats", cuisine: "Everyday", prepMinutes: 5, budget: .value,
                   ingredients: ["milk", "yogurt", "oats", "fruit"], ruleTags: ["vegetarian", "halal"],
                   approvedFacts: ["5 minute preparation", "no stove required", "value-friendly"]),
        FuelOption(id: "jain-poha", name: "Jain vegetable poha", cuisine: "Indian", prepMinutes: 20, budget: .value,
                   ingredients: ["rice flakes", "peas", "peanut"], ruleTags: ["vegan", "vegetarian", "jain", "halal"],
                   approvedFacts: ["20 minute preparation", "Jain rules supported", "value-friendly"]),
        FuelOption(id: "salmon-potato", name: "Salmon with potatoes", cuisine: "European", prepMinutes: 30, budget: .flexible,
                   ingredients: ["fish", "salmon", "potato"], ruleTags: ["kosher"],
                   approvedFacts: ["30 minute preparation", "European cuisine", "requires confident cooking"])
    ]

    static func recommend(passport: NutritionPassport?, query: String, isOffline: Bool = false) -> FuelBuddyOutcome {
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

        let matches = catalog
            .filter { passesHardRules($0, passport: passport) }
            .filter { option in
                let normalized = query.lowercased()
                guard !normalized.isEmpty else { return true }
                let searchable = ([option.name, option.cuisine] + option.approvedFacts).joined(separator: " ").lowercased()
                let usefulWords = normalized.split(separator: " ").filter { $0.count > 3 }
                return usefulWords.isEmpty || usefulWords.contains { searchable.contains($0) }
            }
            .sorted { lhs, rhs in
                let lhsCuisine = passport.preferredCuisines.contains { lhs.cuisine.localizedCaseInsensitiveContains($0) }
                let rhsCuisine = passport.preferredCuisines.contains { rhs.cuisine.localizedCaseInsensitiveContains($0) }
                if lhsCuisine != rhsCuisine { return lhsCuisine }
                if lhs.prepMinutes != rhs.prepMinutes { return lhs.prepMinutes < rhs.prepMinutes }
                return lhs.name < rhs.name
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
        guard !forbidden.contains(where: { rule in optionTerms.contains(where: { $0.contains(rule) || rule.contains($0) }) }) else {
            return false
        }
        guard option.prepMinutes <= passport.maxCookingMinutes else { return false }
        if passport.budget == .value, option.budget != .value { return false }
        return !passport.dislikes.map(normalize).contains { dislike in
            optionTerms.contains { $0.contains(dislike) || dislike.contains($0) }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
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
