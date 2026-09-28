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
    var sexContext: SexContext? {
        didSet {
            if !supportsPregnancyQuestion { isPregnantOrBreastfeeding = false }
        }
    }
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

    var supportsPregnancyQuestion: Bool { sexContext == .female }

    /// Also clears legacy values restored from disk or cloud snapshots.
    var normalized: NutritionPassport {
        var copy = self
        if !supportsPregnancyQuestion { copy.isPregnantOrBreastfeeding = false }
        return copy
    }

    var requiresProfessionalGuidance: Bool {
        isMinor || (supportsPregnancyQuestion && isPregnantOrBreastfeeding)
            || hasEatingDisorderHistory || followsPrescribedDiet
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
    var mealTypes: Set<String> = []
    var mealTags: Set<String> = []
    var cookingAbility: NutritionPassport.CookingAbility = .basic
    var preparation: String = ""
    var recipeIngredients: [String] = []
}

enum FuelBuddyOutcome: Equatable {
    case suggestions([FuelOption])
    case noCompatibleResult
    case blocked(String)
    case routed(String)
    case offline([FuelOption])
    case error(String)
}
