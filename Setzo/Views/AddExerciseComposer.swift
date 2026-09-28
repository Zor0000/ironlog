import SwiftUI

/// The inline "Add Exercise" card, shared by the live log and the session
/// editor. One intent at a time: browse/search the library, or type your own.
/// The optional Exercise Finder entry sits in the same intent bar so all three
/// paths are visible up front without any of them burying the others.
///
/// Query, filter and the custom name live here rather than in the sub-views so
/// switching intents never throws away what the user typed.
struct AddExerciseComposer: View {
    let library: ExerciseLibrary
    /// Muscle chip pre-selected on first appearance (the workout's target), if
    /// that muscle has catalog entries.
    var initialMuscle: String?
    @Binding var weighted: Bool
    /// Present the Exercise Finder. Omit to hide the entry (session editor).
    var onFindMatch: (() -> Void)?
    let onSelect: (ExerciseTemplate) -> Void
    let onAddCustom: (String) -> Void
    let onClose: () -> Void

    @State private var mode: AddExerciseMode = .browse
    @State private var search = ""
    @State private var filter: String?
    @State private var customName = ""
    @State private var showBrowser = false
    @State private var didPrime = false
    @FocusState private var searchFocused: Bool
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            intentBar

            switch mode {
            case .browse:
                ExerciseCatalogPicker(
                    library: library,
                    search: $search,
                    filter: $filter,
                    searchFocused: $searchFocused,
                    onSelect: select,
                    onBrowseAll: { showBrowser = true }
                )
                .transition(.opacity)
            case .custom:
                CustomExerciseField(name: $customName, weighted: $weighted, focused: $customFocused) { name in
                    onAddCustom(name)
                }
                .transition(.opacity)
            }
        }
        .animation(AppMotion.quick, value: mode)
        .onAppear(perform: prime)
        .sheet(isPresented: $showBrowser) {
            ExerciseBrowserSheet(library: library, search: $search, filter: $filter, onSelect: select)
        }
    }

    private var header: some View {
        HStack {
            Text("Add Exercise")
                .cardLabel()
            Spacer()
            Button {
                NativeFeedback.selection()
                clearFocus()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Theme.muted2)
                    .background(Theme.surface2)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.border))
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityLabel("Close add exercise")
            .accessibilityIdentifier("close-add-exercise-button")
        }
    }

    /// Library · Find a match · Add your own. The finder is a launcher, not a
    /// mode: it opens its own screen and leaves the current intent as it was.
    private var intentBar: some View {
        HStack(spacing: 4) {
            intentButton(title: "Library", icon: "books.vertical", isActive: mode == .browse, id: "add-exercise-mode-browse") {
                switchMode(.browse)
            }
            if let onFindMatch {
                intentButton(title: "Find a match", icon: "sparkles", isActive: false, id: "exercise-finder-entry-button") {
                    clearFocus()
                    onFindMatch()
                }
            }
            intentButton(title: "Add your own", icon: "pencil.line", isActive: mode == .custom, id: "add-exercise-mode-custom") {
                switchMode(.custom)
            }
        }
        .padding(4)
        .background(Theme.bg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add exercise options")
    }

    private func intentButton(title: String, icon: String, isActive: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button {
            NativeFeedback.selection()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 5)
            .foregroundStyle(isActive ? .black : (id == "exercise-finder-entry-button" ? Theme.accent : Theme.text))
            .background(isActive ? Theme.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func switchMode(_ next: AddExerciseMode) {
        guard mode != next else { return }
        withAnimation(AppMotion.quick) { mode = next }
        // Land the user straight in the field they asked for.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            searchFocused = false
            customFocused = next == .custom
        }
    }

    private func clearFocus() {
        searchFocused = false
        customFocused = false
    }

    private func select(_ template: ExerciseTemplate) {
        NativeFeedback.light()
        onSelect(template)
        search = ""
        clearFocus()
    }

    private func prime() {
        guard !didPrime else { return }
        didPrime = true
        if filter == nil, let muscle = initialMuscle, library.library[muscle] != nil {
            filter = muscle
        }
    }
}

enum AddExerciseMode: Equatable {
    case browse
    case custom
}

/// Search field, muscle chips and a *bounded* preview of results. The full
/// list never renders inline — past `previewLimit` the user is handed a
/// dedicated browse sheet — so picking a muscle can't balloon the parent card.
struct ExerciseCatalogPicker: View {
    let library: ExerciseLibrary
    @Binding var search: String
    @Binding var filter: String?
    var searchFocused: FocusState<Bool>.Binding
    let onSelect: (ExerciseTemplate) -> Void
    let onBrowseAll: () -> Void

    static let previewLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExerciseSearchField(text: $search, focused: searchFocused)
            ExerciseMuscleChips(library: library, filter: $filter)
            if showResults {
                preview
            } else {
                hint
            }
        }
    }

    private var preview: some View {
        let results = self.results
        let shown = Array(results.prefix(Self.previewLimit))
        return VStack(spacing: 7) {
            ForEach(shown) { item in
                Button {
                    onSelect(item.template)
                } label: {
                    ExerciseCatalogRow(item: item, showsMuscle: filter == nil)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityIdentifier("exercise-template-\(item.template.name)")
            }

            if results.isEmpty {
                ExerciseNoMatches()
            } else if results.count > shown.count {
                Button {
                    NativeFeedback.selection()
                    onBrowseAll()
                } label: {
                    HStack(spacing: 6) {
                        Text("See all \(results.count) \(scopeLabel)")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accentDim)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.accent.opacity(0.35)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityIdentifier("browse-all-exercises-button")
            }
        }
        .transition(.opacity)
    }

    private var scopeLabel: String {
        if let filter, let muscle = library.muscle(filter) {
            return "\(muscle.label.lowercased()) exercises"
        }
        return "matches"
    }

    private var hint: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Search or tap a muscle group to browse the library.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showResults: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != nil
    }

    private var results: [CatalogExercise] {
        library.catalogExercises(muscleID: filter, query: search)
    }
}

/// Full-library browser. A real, edge-to-edge scroller with its own search
/// and chips — no nested scroll region fighting the log's ScrollView.
struct ExerciseBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss

    let library: ExerciseLibrary
    @Binding var search: String
    @Binding var filter: String?
    let onSelect: (ExerciseTemplate) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                NativeBackground()
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(results) { item in
                            Button {
                                onSelect(item.template)
                                dismiss()
                            } label: {
                                ExerciseCatalogRow(item: item, showsMuscle: filter == nil)
                            }
                            .buttonStyle(TactileButtonStyle())
                            .accessibilityIdentifier("browse-exercise-\(item.template.name)")
                        }
                        if results.isEmpty {
                            ExerciseNoMatches()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 10) {
                        ExerciseSearchField(text: $search, focused: $searchFocused)
                        ExerciseMuscleChips(library: library, filter: $filter)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close exercise library")
                    .accessibilityIdentifier("close-exercise-browser-button")
                }
            }
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var title: String {
        if let filter, let muscle = library.muscle(filter) {
            return "\(muscle.label) · \(results.count)"
        }
        return "Exercise Library · \(results.count)"
    }

    private var results: [CatalogExercise] {
        library.catalogExercises(muscleID: filter, query: search)
    }
}

// MARK: - Shared pieces

struct ExerciseSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted2)
            TextField("Search exercises — e.g. walking lunges", text: $text)
                .font(.system(size: 14))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focused)
            if !text.isEmpty {
                Button {
                    NativeFeedback.selection()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused.wrappedValue ? Theme.accent.opacity(0.5) : Theme.border))
        .accessibilityIdentifier("exercise-template-search-field")
    }
}

struct ExerciseMuscleChips: View {
    let library: ExerciseLibrary
    @Binding var filter: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(title: "All", id: nil)
                ForEach(library.catalogMuscles) { muscle in
                    chip(title: muscle.label, id: muscle.id, icon: muscle.systemImage)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func chip(title: String, id: String?, icon: String? = nil) -> some View {
        Button {
            NativeFeedback.selection()
            withAnimation(AppMotion.quick) { filter = id }
        } label: {
            Pill(text: title, icon: icon, isActive: filter == id)
                .frame(minHeight: 34)
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel("\(title) exercises")
        .accessibilityAddTraits(filter == id ? .isSelected : [])
    }
}

struct ExerciseCatalogRow: View {
    let item: CatalogExercise
    var showsMuscle = false

    var body: some View {
        let template = item.template
        let icon = template.timed ? "timer" : (template.bodyweight ? "figure.strengthtraining.functional" : "dumbbell")
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Theme.accentDim).frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    if showsMuscle {
                        Text(item.muscle.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.bg.opacity(0.5))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                    }
                }
                Text(meta)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted2)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
        .padding(11)
        .frame(minHeight: 44)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border.opacity(0.8)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.name), \(meta)")
        .accessibilityHint("Adds to the workout")
    }

    private var meta: String {
        let template = item.template
        var parts = ["\(template.sets)×\(template.reps) \(template.timed ? (template.minutes ? "min" : "sec") : "reps")"]
        if template.bodyweight || template.timed {
            parts.append(template.timed ? "Timed" : "Bodyweight")
        }
        return parts.joined(separator: " · ")
    }
}

struct ExerciseNoMatches: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("No matching exercises")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Try fewer words — search covers the whole library.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// Name, weighted/reps-only choice and the add button. Name and focus are
/// owned by the caller so they survive switching intents.
struct CustomExerciseField: View {
    @Binding var name: String
    @Binding var weighted: Bool
    var focused: FocusState<Bool>.Binding
    let onAdd: (String) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Custom exercise name", text: $name)
                .fieldStyle()
                .submitLabel(.done)
                .focused(focused)
                .onSubmit { if !trimmedName.isEmpty { add() } }
                .accessibilityIdentifier("new-exercise-name-field")

            HStack(spacing: 8) {
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) { weighted = false }
                } label: {
                    Pill(text: "Reps only", isActive: !weighted)
                        .frame(minHeight: 34)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityAddTraits(weighted ? [] : .isSelected)
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) { weighted = true }
                } label: {
                    Pill(text: "Weight + Reps", isActive: weighted)
                        .frame(minHeight: 34)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityAddTraits(weighted ? .isSelected : [])
                Spacer(minLength: 0)
            }

            Button {
                NativeFeedback.light()
                add()
            } label: {
                Label("Add Custom Exercise", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            // PrimaryButtonStyle has no disabled look, so dim it here — and the
            // editor's sheet covers the toast layer, so a blocked tap there
            // would otherwise give no feedback at all.
            .opacity(trimmedName.isEmpty ? 0.45 : 1)
            .disabled(trimmedName.isEmpty)
            .animation(AppMotion.quick, value: trimmedName.isEmpty)
            .accessibilityIdentifier("confirm-add-exercise-button")
        }
    }

    private func add() {
        withAnimation(AppMotion.quick) {
            onAdd(trimmedName)
            name = ""
        }
    }
}
