import SwiftUI

struct IronFuelView: View {
    @EnvironmentObject private var app: AppState
    @State private var showPassportEditor = false
    @State private var showDeleteConfirmation = false
    @State private var request = ""
    @State private var outcome: FuelBuddyOutcome?

    private var status: EnergyFirewallStatus { EnergyFirewallStatus(passport: app.nutritionPassport) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TitleBlock(title: "IronFuel", subtitle: "Food guidance that respects your rules")
                firewallCard

                if let passport = app.nutritionPassport {
                    if passport.isComplete {
                        passportSummary(passport)
                        goalStack(passport)
                        fuelBuddy(passport)
                    } else {
                        incompletePassportCard
                    }
                } else {
                    firstUseCard
                }
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(isPresented: $showPassportEditor) {
            NutritionPassportEditor(passport: app.nutritionPassport ?? NutritionPassport()) { passport in
                app.saveNutritionPassport(passport)
            }
        }
        .overlay {
            if showDeleteConfirmation {
                ConfirmActionModal(
                    title: "Delete Nutrition Passport?",
                    message: "Your goals, preferences, safety answers, and hard rules will be removed from this device. Workout data is not affected.",
                    confirmTitle: "Delete Passport",
                    cancelTitle: "Keep Passport",
                    systemImage: "person.crop.circle.badge.minus"
                ) {
                    showDeleteConfirmation = false
                    outcome = nil
                    app.deleteNutritionPassport()
                } cancel: {
                    showDeleteConfirmation = false
                }
            }
        }
    }

    private var firewallCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status == .ready ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(status == .ready ? Theme.success : Theme.accent)
                .frame(width: 42, height: 42)
                .background((status == .ready ? Theme.success : Theme.accent).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                    .font(.system(size: 15, weight: .bold))
                Text(status.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("energy-firewall-status")
    }

    private var firstUseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Start with your Nutrition Passport")
                .font(.system(size: 22, weight: .black))
                .fontWidth(.condensed)
            Text("Tell IronFuel what must never be suggested, what you enjoy, and whether professional guidance should take the lead. Your Passport stays private and can be edited or deleted at any time.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted2)
                .fixedSize(horizontal: false, vertical: true)
            Label("Personalized options stay locked until the safety review is complete.", systemImage: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted2)
            Button {
                showPassportEditor = true
            } label: {
                Label("Create Nutrition Passport", systemImage: "arrow.right")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("create-nutrition-passport-button")
        }
        .cardStyle(radius: 18)
    }

    private var incompletePassportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Passport in progress", systemImage: "clock.badge.exclamationmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("Your answers are saved locally. Finish the required context, goals, and safety review before Fuel Buddy can run.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted2)
            Button("Continue Nutrition Passport") { showPassportEditor = true }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("continue-nutrition-passport-button")
        }
        .cardStyle()
    }

    private func passportSummary(_ passport: NutritionPassport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NUTRITION PASSPORT").cardLabel()
                Spacer()
                Button("Edit") { showPassportEditor = true }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("edit-nutrition-passport-button")
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(Theme.danger)
                .accessibilityLabel("Delete Nutrition Passport")
                .accessibilityIdentifier("delete-nutrition-passport-button")
            }
            HStack(spacing: 8) {
                PassportPill(text: passport.dietaryIdentity.rawValue)
                PassportPill(text: "\(passport.mealsPerDay) meals/day")
                PassportPill(text: "≤ \(passport.maxCookingMinutes) min")
            }
            .accessibilityElement(children: .combine)
            if passport.hardRules.isEmpty {
                Text("No allergies or never-suggest foods recorded.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted2)
            } else {
                Text(passport.hardRules.joined(separator: "  •  "))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func goalStack(_ passport: NutritionPassport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRIORITY GOALS").cardLabel()
            ForEach(Array(passport.goalStack.enumerated()), id: \.offset) { index, goal in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(Theme.accent)
                        .clipShape(Circle())
                    Text(goal)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .cardStyle()
    }

    private func fuelBuddy(_ passport: NutritionPassport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FUEL BUDDY").cardLabel()
                    Text("Ask for compatible food or meal options")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted2)
                }
                Spacer()
                Label("Local", systemImage: "iphone.and.arrow.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.success)
            }

            TextField("e.g. quick Indian dinner", text: $request, axis: .vertical)
                .lineLimit(2...4)
                .fieldStyle()
                .accessibilityIdentifier("fuel-buddy-request-field")
                .disabled(passport.requiresProfessionalGuidance)

            Button {
                NativeFeedback.light()
                outcome = debugOutcome ?? FuelBuddyRecommendationEngine.recommend(passport: passport, query: request)
            } label: {
                Label("Find compatible options", systemImage: "sparkles")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || passport.requiresProfessionalGuidance)
            .accessibilityIdentifier("fuel-buddy-submit-button")

            if passport.requiresProfessionalGuidance {
                responseMessage(icon: "stethoscope", title: "Use your care plan", detail: status.detail, color: Theme.accent)
            } else if let outcome {
                outcomeView(outcome)
            } else {
                Label("All results pass Passport hard rules and the Energy Firewall before presentation.", systemImage: "checkmark.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func outcomeView(_ outcome: FuelBuddyOutcome) -> some View {
        switch outcome {
        case .suggestions(let options):
            suggestionList(options, offline: false)
        case .offline(let options):
            suggestionList(options, offline: true)
        case .noCompatibleResult:
            responseMessage(icon: "magnifyingglass", title: "No compatible result", detail: "Nothing in the approved catalog satisfies every Passport hard rule and this request. Try a broader meal or add available foods—your rules were not relaxed.", color: Theme.muted2)
        case .blocked(let detail):
            responseMessage(icon: "hand.raised.fill", title: "That request is outside IronFuel", detail: detail, color: Theme.danger)
        case .routed(let detail):
            responseMessage(icon: "stethoscope", title: "Professional guidance recommended", detail: detail, color: Theme.accent)
        case .error(let detail):
            responseMessage(icon: "exclamationmark.triangle.fill", title: "Fuel Buddy could not finish", detail: detail, color: Theme.danger)
        }
    }

    private func suggestionList(_ options: [FuelOption], offline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if offline {
                Label("Offline — using the approved on-device catalog", systemImage: "wifi.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            ForEach(options) { option in
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.name)
                        .font(.system(size: 14, weight: .bold))
                    Text(option.approvedFacts.joined(separator: "  •  "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            }
            Text("Why these: ranked only by approved catalog facts such as cuisine, preparation time, budget, and your recorded preferences.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
        }
    }

    private func responseMessage(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.muted2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fuel-buddy-response")
    }

    private var debugOutcome: FuelBuddyOutcome? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "UITest_IronFuelState"), args.indices.contains(index + 1) else { return nil }
        switch args[index + 1] {
        case "offline": return FuelBuddyRecommendationEngine.recommend(passport: app.nutritionPassport, query: request, isOffline: true)
        case "error": return .error("The optional wording service is unavailable. Your Passport is safe; try again or use the local catalog.")
        case "no-results": return .noCompatibleResult
        default: return nil
        }
        #else
        return nil
        #endif
    }
}

private struct PassportPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.accentDim)
            .clipShape(Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

private struct NutritionPassportEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NutritionPassport
    @State private var step = 0
    let onSave: (NutritionPassport) -> Void

    init(passport: NutritionPassport, onSave: @escaping (NutritionPassport) -> Void) {
        _draft = State(initialValue: passport)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SwiftUI.ProgressView(value: Double(step + 1), total: 4)
                    .tint(Theme.accent)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(stepTitle)
                            .font(.system(size: 28, weight: .black))
                            .fontWidth(.condensed)
                        Text(stepDetail)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted2)
                        stepContent
                    }
                    .padding(18)
                }
                HStack(spacing: 10) {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button(step == 3 ? "Save Passport" : "Save & Continue") {
                        if step == 3 { draft.safetyReviewedAt = Date() }
                        onSave(draft)
                        if step == 3 { dismiss() } else { step += 1 }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canContinue)
                    .accessibilityIdentifier(step == 3 ? "save-nutrition-passport-button" : "passport-continue-button")
                }
                .padding(18)
                .background(Theme.surface)
                .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .top)
            }
            .background(NativeBackground())
            .navigationTitle("Nutrition Passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private var stepTitle: String {
        ["Your context and goals", "Targets and hard rules", "Make it practical", "Safety review"][step]
    }

    private var stepDetail: String {
        [
            "Sex context is recorded because nutrition guidance can depend on it. You can choose not to say. Put your goals in priority order.",
            "Allergies, intolerances, belief rules, and never-suggest foods are enforced as hard rules.",
            "Preferences guide ranking. They never override a hard rule.",
            "These gates pause personalized suggestions when professional support should lead."
        ][step]
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: contextStep
        case 1: rulesStep
        case 2: preferencesStep
        default: safetyStep
        }
    }

    private var contextStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SEX CONTEXT").cardLabel()
            Picker("Sex context", selection: $draft.sexContext) {
                Text("Choose…").tag(NutritionPassport.SexContext?.none)
                ForEach(NutritionPassport.SexContext.allCases) { value in
                    Text(value.rawValue).tag(Optional(value))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("passport-sex-context-picker")

            Text("GOALS — TAP IN PRIORITY ORDER").cardLabel()
            ForEach(NutritionPassport.Goal.allCases) { goal in
                Button {
                    if let index = draft.goals.firstIndex(of: goal) {
                        draft.goals.remove(at: index)
                    } else {
                        draft.goals.append(goal)
                    }
                } label: {
                    HStack {
                        Text(goal.rawValue)
                        Spacer()
                        if let index = draft.goals.firstIndex(of: goal) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(.black)
                                .frame(width: 24, height: 24)
                                .background(Theme.accent)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "circle")
                        }
                    }
                    .padding(12)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("passport-goal-\(goal.rawValue)")
            }
        }
        .cardStyle()
    }

    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DIETARY IDENTITY").cardLabel()
            Picker("Dietary identity", selection: $draft.dietaryIdentity) {
                ForEach(NutritionPassport.DietaryIdentity.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("passport-dietary-identity-picker")

            Text("ENERGY TARGET").cardLabel()
            Picker("Target source", selection: $draft.targetSource) {
                ForEach(NutritionPassport.TargetSource.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("passport-target-source-picker")
            if draft.targetSource != .none {
                TextField("Optional daily energy target", value: $draft.energyTarget, format: .number)
                    .keyboardType(.numberPad)
                    .fieldStyle()
                    .accessibilityIdentifier("passport-energy-target-field")
            }
            Text("IronFuel never calculates or silently changes this target.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted2)

            PassportListField(title: "Allergies", placeholder: "e.g. peanut, shellfish", values: $draft.allergies, identifier: "passport-allergies-field")
            PassportListField(title: "Intolerances", placeholder: "e.g. lactose", values: $draft.intolerances)
            PassportListField(title: "Religious / ethical exclusions", placeholder: "e.g. pork, alcohol", values: $draft.exclusions)
            PassportListField(title: "Never suggest", placeholder: "e.g. mushrooms", values: $draft.neverSuggest, identifier: "passport-never-suggest-field")
        }
        .cardStyle()
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            PassportListField(title: "Preferred cuisines", placeholder: "e.g. Indian, Mediterranean", values: $draft.preferredCuisines)
            PassportListField(title: "Dislikes", placeholder: "e.g. olives", values: $draft.dislikes)
            PassportListField(title: "Regularly available foods", placeholder: "e.g. rice, dal, eggs", values: $draft.availableFoods)
            Text("BUDGET").cardLabel()
            Picker("Budget", selection: $draft.budget) {
                ForEach(NutritionPassport.Budget.allCases) { value in Text(value.rawValue).tag(value) }
            }
            .pickerStyle(.segmented)
            Text("COOKING ABILITY").cardLabel()
            Picker("Cooking ability", selection: $draft.cookingAbility) {
                ForEach(NutritionPassport.CookingAbility.allCases) { value in Text(value.rawValue).tag(value) }
            }
            .pickerStyle(.menu)
            Stepper("Up to \(draft.maxCookingMinutes) minutes", value: $draft.maxCookingMinutes, in: 5...90, step: 5)
            Stepper("\(draft.mealsPerDay) meals per day", value: $draft.mealsPerDay, in: 1...8)
        }
        .cardStyle()
    }

    private var safetyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            SafetyToggle(title: "Under 18", detail: "A parent/guardian and qualified professional should guide nutrition.", isOn: $draft.isMinor)
            SafetyToggle(title: "Pregnant or breastfeeding", detail: "Nutrition needs should be discussed with your care team.", isOn: $draft.isPregnantOrBreastfeeding)
            SafetyToggle(title: "Eating-disorder history or concern", detail: "IronFuel will not personalize food suggestions.", isOn: $draft.hasEatingDisorderHistory)
            SafetyToggle(title: "Prescribed or professionally managed diet", detail: "Your clinician or dietitian's plan takes priority.", isOn: $draft.followsPrescribedDiet)
            Divider().overlay(Theme.border)
            Label("If any switch is on, your Passport is still saved and readable, but Fuel Buddy routes you to professional guidance.", systemImage: "shield.checkered")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
        .accessibilityIdentifier("passport-safety-step")
    }

    private var canContinue: Bool {
        switch step {
        case 0: draft.sexContext != nil && !draft.goals.isEmpty
        default: true
        }
    }
}

private struct PassportListField: View {
    let title: String
    let placeholder: String
    @Binding var values: [String]
    var identifier: String?
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).cardLabel()
            TextField(placeholder, text: $text)
                .fieldStyle()
                .accessibilityIdentifier(identifier ?? "passport-list-\(title)")
                .onAppear { text = values.joined(separator: ", ") }
                .onChange(of: text) { _, newValue in
                    values = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                }
        }
    }
}

private struct SafetyToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.muted2)
            }
        }
        .tint(Theme.accent)
    }
}
