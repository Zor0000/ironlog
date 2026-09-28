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

    enum BlockReason: String, Equatable, CaseIterable {
        case supplementsOrSteroids
        case diagnosisOrTreatment
        case crashDietOrCompensation
        case allergyBypass
        case dietaryRuleBypass
    }

    enum RoutingReason: String, Equatable, CaseIterable {
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

    /// True when model-authored text contains anything the model must never
    /// produce: medical/treatment or supplement language, a nutrient figure,
    /// an ingredient or allergen name, or a claim about a food's properties.
    /// The catalog owns every food fact; model text may only explain order.
    static func containsForbiddenLanguage(_ text: String) -> Bool {
        let normalized = normalize(text)
        if matches(medicalOutputPatterns, in: normalized) { return true }
        if matches(supplementPatterns, in: normalized) { return true }
        if matches(ingredientPatterns, in: normalized) { return true }
        if matches(propertyClaimPatterns, in: normalized) { return true }
        return containsNumberWithUnit(normalized)
    }

    /// Nutrient/energy figures are facts the catalog owns; a model stating
    /// one is hallucinating by definition.
    static func containsNumberWithUnit(_ text: String) -> Bool {
        text.range(of: #"\b\d+(\.\d+)?\s?(kcal|cal|calories|calorie|kj|g|grams|gram|mg|mcg|percent)\b|\b\d+(\.\d+)?\s?%"#, options: .regularExpression) != nil
    }

    // MARK: - Request vocabulary (regular expressions over normalized text)

    private static let supplementPatterns = [
        #"\bsupplements?\b"#, #"\bsteroids?\b"#, #"\banabolic"#, #"\bsarms?\b"#, #"\bcreatine\b"#, #"\bwhey\b"#,
        #"\bprotein powder"#, #"\bfat[\s-]?burners?\b"#, #"\bpre[\s-]?workout\b"#, #"\btestosterone\b"#,
        #"\bclenbuterol\b"#, #"\bozempic\b"#, #"\bsemaglutide\b"#, #"\bdiet pills?\b"#, #"\bappetite suppressant"#
    ]
    private static let medicalRequestPatterns = [
        #"\bdiagnos"#, #"\btreat(s|ed|ing)?\s+(my|our|his|her|their|the|a|an)\b"#, #"\btreatment"#, #"\bprescri"#,
        #"\bmedication"#, #"\bcures?\b"#, #"\bdos(e|age)\b"#, #"\bheal\s+(my|the)\b"#, #"\breverse my\b"#
    ]
    private static let crashDietPatterns = [
        #"\bcrash[\s-]?diet"#, #"\bstarv"#, #"\bwater fast"#, #"\bfast(ing)? for\b"#, #"\bvery low[\s-]calorie"#,
        #"\bvlcd\b"#, #"\bdetox"#, #"\bcleanse\b"#, #"\bjuice fast"#, #"\bzero[\s-]calorie diet"#,
        // Under 1000 calories a day, however phrased.
        #"\b[1-9]\d{2}\s?(kcal|cal|calories)\b"#,
        // Also matches the redactor's placeholder, since the gate screens
        // redacted text: "lose [measurement] in two weeks".
        #"\blose\s+(\d+\s?(kg|kgs|kilos?|lbs?|pounds?|stone)|\[measurement\])\s+(in|by|before|this|within)\b"#,
        #"\brapid weight loss\b"#, #"\bpunish"#, #"\bburn (it )?off\b"#, #"\bearn (my|the) food\b"#,
        #"\bcompensat"#, #"\bpurg"#, #"\bskip(ping)? meals?\b"#, #"\bno food (for|until|till)\b"#, #"\bnot eat(ing)? (for|until|till)\b"#
    ]
    private static let allergyBypassPatterns = [
        // An override instruction with an allergen name allowed in between:
        // "ignore my peanut allergy", "despite my shellfish intolerance".
        #"\b(ignore|ignoring|forget|skip|override|despite|disregard|bypass|don'?t care about|doesn'?t matter about|not worried about|never mind)\b[^.!?]{0,40}\b(allerg|intoleran)"#,
        // "I'm allergic to peanuts but include them anyway".
        #"\b(allergic|intolerant) to\b[^.!?]{0,60}\b(but|still|anyway|regardless|include|add|give|want)\b"#,
        #"\beven though (i'?m|i am|im) allergic"#
    ]
    private static let ruleBypassPatterns = [
        #"\b(ignore|ignoring|forget|skip|override|despite|disregard|bypass|don'?t care about)\b[^.!?]{0,30}\b(halal|kosher|religio|vegetarian|vegan|exclusion|restriction|diet rule|my rules)"#,
        #"\bnot really (a )?(vegetarian|vegan)"#, #"\bcheat on my\b"#, #"\bbreak my fast early\b"#,
        #"\b(vegetarian|vegan|halal|kosher) but (give|include|add|i want|i'?ll have)\b"#
    ]
    private static let pregnancyPatterns = [#"\bpregnan"#, #"\bbreast[\s-]?feed"#, #"\bnursing my\b"#, #"\btrimester\b"#, #"\bpostpartum\b"#]
    private static let disorderedEatingPatterns = [
        #"\banorexi"#, #"\bbulimi"#, #"\bbinge"#, #"\beating disorder"#, #"\bpurging\b"#, #"\bhate my body\b"#,
        #"\bfeel fat\b"#, #"\btoo fat to eat\b"#, #"\barfid\b"#, #"\borthorexi"#, #"\brestrict(ing)? (again|more)\b"#
    ]
    // Conditions where a meal list is the wrong answer: route to the person
    // managing the diet instead of blocking or guessing.
    private static let clinicianPatterns = [
        #"\bdietitian"#, #"\bdietician"#, #"\bnutritionist (told|said)"#, #"\bdoctor (told|said)"#, #"\brenal diet"#,
        #"\bdialysis"#, #"\bchemo"#, #"\btube feed"#, #"\blow[\s-]fodmap for my\b"#, #"\bc(o)?eliac"#, #"\binsulin\b"#,
        #"\bthyroid"#, #"\bdiabet"#, #"\bcholesterol"#, #"\bblood pressure"#, #"\bkidney disease"#, #"\bliver disease"#,
        #"\bcrohn"#, #"\bcolitis"#, #"\bpancreatit"#, #"\bgestational"#
    ]
    private static let minorPatterns = [
        #"\b(i am|i'm|im|age|aged)\s(1[0-7]|[1-9])\b"#,
        #"\b(1[0-7]|[1-9])[\s-]?(years?|yrs?)[\s-]?old\b"#,
        #"\b\d+[\s-]?(months?|weeks?|days?)[\s-]?old\b"#,
        #"\b(i am|i'm|im|age|aged)\s(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen)\b"#,
        #"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen)[\s-](years?|yrs?)[\s-]old\b"#,
        #"\b(infant|toddler|newborn|baby|babies|preschooler|kindergart)"#, #"\bmy (kid|child|children|son|daughter|little one)s?\b"#,
        #"\bfor (a|my) teen(ager)?s?\b"#, #"\bschool lunch for my\b"#, #"\bweaning\b"#
    ]

    // MARK: - Output vocabulary

    /// Stricter than the request screen: model copy has no business saying
    /// "treat" at all.
    private static let medicalOutputPatterns = [
        #"\bdiagnos"#, #"\btreat(s|ed|ing|ment|ments)?\b"#, #"\bprescri"#, #"\bmedication"#, #"\bmedicine"#,
        #"\bcur(e|es|ed|ing)\b"#, #"\bdos(e|age)\b"#, #"\bheal(s|ed|ing)?\b"#, #"\bremedy\b"#, #"\btherap"#,
        #"\bsymptom"#, #"\bcondition\b"#, #"\bdisease"#, #"\binflammation\b"#, #"\bimmune\b"#, #"\bdetox"#
    ]
    /// The 14 major allergens, their common forms, and everyday proteins.
    /// Any of these in model copy is an ingredient claim the catalog didn't make.
    private static let ingredientPatterns = [
        #"\bpeanuts?\b"#, #"\bnuts?\b"#, #"\bnutty\b"#, #"\balmonds?\b"#, #"\bcashews?\b"#, #"\bwalnuts?\b"#, #"\bhazelnuts?\b"#, #"\bpistachios?\b"#,
        #"\bmilk\b"#, #"\bdairy\b"#, #"\bcheese\b"#, #"\bbutter\b"#, #"\bcream\b"#, #"\byog(h)?urt\b"#, #"\bpaneer\b"#, #"\bghee\b"#, #"\blactose\b"#,
        #"\beggs?\b"#, #"\bwheat\b"#, #"\bgluten\b"#, #"\bflour\b"#, #"\bbread\b"#, #"\bsoy(a)?\b"#, #"\btofu\b"#, #"\bsesame\b"#, #"\btahini\b"#,
        #"\bfish\b"#, #"\bshellfish\b"#, #"\bprawns?\b"#, #"\bshrimps?\b"#, #"\bcrab\b"#, #"\blobster\b"#, #"\bmussels?\b"#, #"\boysters?\b"#, #"\bsquid\b"#, #"\btuna\b"#, #"\bsalmon\b"#,
        #"\bmustard\b"#, #"\bcelery\b"#, #"\blupin\b"#, #"\bsulph?ites?\b"#, #"\bmolluscs?\b"#,
        #"\bchicken\b"#, #"\bbeef\b"#, #"\bpork\b"#, #"\bbacon\b"#, #"\bham\b"#, #"\blamb\b"#, #"\bmutton\b"#, #"\bturkey\b"#, #"\bmeat\b"#, #"\bgelatin(e)?\b"#,
        #"\balcohol\b"#, #"\bwine\b"#, #"\bbeer\b"#, #"\bhoney\b"#, #"\bturmeric\b"#, #"\bgarlic\b"#, #"\bonions?\b"#, #"\bsugar\b"#, #"\bsalt\b"#, #"\boil\b"#,
        #"\bingredients?\b"#, #"\ballergens?\b"#, #"\bcontamination\b"#
    ]
    /// Phrasing that asserts something about a food. The explanation may say
    /// why this order, not what a food is.
    private static let propertyClaimPatterns = [
        #"\bcontains?\b"#, #"\bcontaining\b"#, #"\bfree of\b"#, #"\bfree from\b"#, #"[\w-]+-free\b"#, #"\bwithout\b"#,
        #"\bno (added )?[a-z]+ (in|inside)\b"#, #"\brich in\b"#, #"\bhigh in\b"#, #"\blow in\b"#, #"\bsource of\b"#, #"\bpacked with\b"#,
        #"\bloaded with\b"#, #"\bfull of\b"#, #"\breduc(e|es|ed|ing)\b"#, #"\bboost(s|ed|ing)?\b"#, #"\bimprov(e|es|ed|ing)\b"#,
        #"\bhelps? (with|you|to)\b"#, #"\bgood for\b"#, #"\bbad for\b"#, #"\bhealthy\b"#, #"\bunhealthy\b"#, #"\bsafe for\b"#,
        #"\bsuitable for\b"#, #"\bsuits? (your|a)\b"#, #"\bnutritious\b"#, #"\bnutrient"#, #"\bprotein\b"#, #"\bcarb(s|ohydrate)"#,
        #"\bfat\b"#, #"\bfibre\b"#, #"\bfiber\b"#, #"\bvitamin"#, #"\bmineral"#, #"\bcalori"#, #"\bkcal\b"#, #"\bmacro"#,
        #"\bmade (with|from)\b"#, #"\bcooked (with|in)\b"#, #"\bserved? with\b"#, #"\btop(ped)? with\b"#, #"\bpair(ed|s)? (it )?with\b"#,
        #"\badd(ed)? (some|a|an)\b"#, #"\bside of\b"#,
        // Prep time and cost are catalog facts too.
        #"\b\d+\s?(minutes?|mins?|hours?|hrs?)\b"#, #"\bready in\b"#, #"\btakes? (about |around |only |just )?\d"#,
        #"\bcheap(er|est)?\b"#, #"\bexpensive\b"#, #"\bcost(s|ly)?\b"#, #"\bbudget\b"#
    ]

    // MARK: - Screening

    private static func routingReason(in text: String) -> RoutingReason? {
        if matches(pregnancyPatterns, in: text) { return .pregnancyOrBreastfeeding }
        if matches(disorderedEatingPatterns, in: text) { return .disorderedEating }
        if matches(clinicianPatterns, in: text) { return .clinicianManagedDiet }
        if matches(minorPatterns, in: text) { return .under18 }
        return nil
    }

    private static func blockReason(in text: String) -> BlockReason? {
        if matches(allergyBypassPatterns, in: text) { return .allergyBypass }
        if matches(ruleBypassPatterns, in: text) { return .dietaryRuleBypass }
        if matches(supplementPatterns, in: text) { return .supplementsOrSteroids }
        if matches(medicalRequestPatterns, in: text) { return .diagnosisOrTreatment }
        if matches(crashDietPatterns, in: text) { return .crashDietOrCompensation }
        return nil
    }

    private static func matches(_ patterns: [String], in text: String) -> Bool {
        patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
