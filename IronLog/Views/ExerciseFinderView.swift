import SwiftUI
import UIKit

struct ExerciseFinderEntryCard: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button {
            NativeFeedback.light()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.accent)
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(14)
            .background(Theme.accentDim)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.accent.opacity(0.42))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityIdentifier("exercise-finder-entry-button")
    }
}

private enum ExerciseFinderPhase: Equatable {
    case idle
    case scanning
    case complete
}

/// Match reveal: pick a muscle, run a short scan, land on one clear result
/// with the reasons behind it and the runners-up one tap away. Everything is
/// laid out in a vertical stack — nothing is absolutely positioned — so long
/// names, Dynamic Type and small screens reflow instead of colliding.
struct ExerciseFinderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let library: ExerciseLibrary
    let sessions: [WorkoutSession]
    let currentExerciseNames: Set<String>
    let onSelect: (ExerciseTemplate) -> Void

    @State private var selectedMuscleID: String
    @State private var candidates: [ExerciseRecommendation] = []
    @State private var selector = ExerciseFinderSelector(generator: SystemRandomNumberGenerator())
    @State private var phase: ExerciseFinderPhase = .idle
    @State private var result: ExerciseFinderResult?
    @State private var tickerIndex = 0
    @State private var sweeping = false
    @State private var searchTask: Task<Void, Never>?

    init(
        library: ExerciseLibrary,
        sessions: [WorkoutSession],
        currentExerciseNames: Set<String> = [],
        initialMuscleID: String? = nil,
        onSelect: @escaping (ExerciseTemplate) -> Void
    ) {
        self.library = library
        self.sessions = sessions
        self.currentExerciseNames = currentExerciseNames
        self.onSelect = onSelect

        let requestedIsAvailable = initialMuscleID.flatMap { library.library[$0] }?.isEmpty == false
        let initial = requestedIsAvailable ? initialMuscleID : library.catalogMuscles.first?.id
        _selectedMuscleID = State(initialValue: initial ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NativeBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        musclePicker
                        stage
                        actionArea
                        // Runners-up sit below the primary actions so "Add" is
                        // never pushed off a compact screen.
                        if phase == .complete, let result, !result.alternates.isEmpty {
                            alternates(result.alternates)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                    .animation(reduceMotion ? nil : AppMotion.smooth, value: phase)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Exercise Finder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        searchTask?.cancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close exercise finder")
                    .accessibilityIdentifier("close-exercise-finder-button")
                }
            }
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: refreshCandidates)
        .onChange(of: selectedMuscleID) { _, _ in refreshCandidates() }
        .onDisappear { searchTask?.cancel() }
    }

    private var selectedMuscle: Muscle? {
        library.muscle(selectedMuscleID)
    }

    private var isSearching: Bool { phase == .scanning }

    // MARK: Muscle picker

    private var musclePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Muscle group")
                    .cardLabel()
                Spacer()
                Text(selectedMuscle?.label ?? "Unavailable")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(library.catalogMuscles) { muscle in
                        Button {
                            guard !isSearching else { return }
                            NativeFeedback.selection()
                            withAnimation(AppMotion.quick) { selectedMuscleID = muscle.id }
                        } label: {
                            Pill(text: muscle.label, icon: muscle.systemImage, isActive: selectedMuscleID == muscle.id)
                        }
                        .buttonStyle(TactileButtonStyle())
                        .disabled(isSearching)
                        .accessibilityAddTraits(selectedMuscleID == muscle.id ? .isSelected : [])
                        .accessibilityIdentifier("exercise-finder-muscle-\(muscle.id)")
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: Stage

    /// The single focal point: status strip, reticle, then the headline that
    /// moves from "ready" → cycling names → the chosen exercise.
    private var stage: some View {
        VStack(spacing: 14) {
            statusStrip

            FinderReticle(
                phase: phase,
                sweeping: sweeping,
                reduceMotion: reduceMotion,
                symbol: selectedMuscle?.systemImage ?? "dumbbell"
            )
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            headline
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface.opacity(0.9))
                .overlay {
                    LinearGradient(
                        colors: [Theme.accent.opacity(phase == .complete ? 0.16 : 0.07), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(phase == .complete ? Theme.accent.opacity(0.45) : Theme.border.opacity(0.9))
        }
        .shadow(color: Theme.accent.opacity(phase == .complete ? 0.16 : 0), radius: 28, y: 10)
        .animation(reduceMotion ? nil : AppMotion.smooth, value: phase)
        .accessibilityElement(children: .contain)
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(phase == .complete ? Theme.success : Theme.accent)
                .frame(width: 7, height: 7)
                .opacity(isSearching && sweeping ? 0.35 : 1)
                .animation(isSearching && !reduceMotion ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true) : .default, value: sweeping)
            Text(statusText)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(phase == .complete ? Theme.success : Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text(poolText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("exercise-finder-status")
    }

    private var statusText: String {
        switch phase {
        case .idle: return "Ready"
        case .scanning: return "Scanning \(selectedMuscle?.label ?? "")"
        case .complete: return result?.cycleRestarted == true ? "Rotation restarted" : "Match found"
        }
    }

    private var poolText: String {
        switch candidates.count {
        case 0: return "No options"
        case 1: return "1 option"
        default: return "\(candidates.count) options"
        }
    }

    @ViewBuilder
    private var headline: some View {
        switch phase {
        case .idle:
            VStack(spacing: 6) {
                Text(candidates.isEmpty ? "Nothing left to suggest" : "Find a \(selectedMuscle?.label.lowercased() ?? "muscle") match")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text(candidates.isEmpty
                     ? "Every exercise in this group is already in your workout."
                     : "Weighs what you've logged recently and what's already in today's workout.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)

        case .scanning:
            VStack(spacing: 6) {
                Text(tickerName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                    .id("ticker-\(tickerIndex)")
                Text("Comparing \(candidates.count) options…")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted2)
            }
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Scanning \(candidates.count) options")

        case .complete:
            if let result {
                resultHeadline(result.selected)
            }
        }
    }

    private var tickerName: String {
        guard !candidates.isEmpty else { return "" }
        return candidates[tickerIndex % candidates.count].template.name
    }

    private func resultHeadline(_ recommendation: ExerciseRecommendation) -> some View {
        VStack(spacing: 10) {
            Text(recommendation.template.name)
                .font(.title2.weight(.black))
                .fontWidth(.condensed)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("exercise-finder-result-name")
            Text(meta(for: recommendation))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.muted2)
                .multilineTextAlignment(.center)
            Text(recommendation.reason)
                .font(.subheadline)
                .foregroundStyle(Theme.text.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !recommendation.factors.isEmpty {
                FinderFlowLayout(spacing: 6) {
                    ForEach(recommendation.factors, id: \.self) { factor in
                        FinderFactorChip(factor: factor)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Why this pick")
            }
        }
        .frame(maxWidth: .infinity)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
    }

    private func meta(for recommendation: ExerciseRecommendation) -> String {
        let unit = recommendation.template.timed
            ? (recommendation.template.minutes ? "min" : "sec")
            : "reps"
        return "\(recommendation.movementStyle) · \(recommendation.template.sets)×\(recommendation.template.reps) \(unit)"
    }

    // MARK: Alternates

    private func alternates(_ items: [ExerciseRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Also fits")
                .cardLabel()
            VStack(spacing: 6) {
                ForEach(items) { item in
                    Button {
                        NativeFeedback.selection()
                        guard let chosen = selector.choose(item, from: candidates) else { return }
                        withAnimation(reduceMotion ? nil : AppMotion.smooth) { result = chosen }
                        UIAccessibility.post(notification: .announcement, argument: "Selected \(item.template.name)")
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.template.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.text)
                                    .multilineTextAlignment(.leading)
                                Text("\(item.movementStyle) · \(item.factors.first(where: \.isPositive)?.label ?? "Qualified")")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted2)
                                    .multilineTextAlignment(.leading)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.left")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .background(Theme.surface2.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TactileButtonStyle())
                    .accessibilityLabel("Use \(item.template.name) instead")
                    .accessibilityIdentifier("exercise-finder-alternate-\(item.template.id)")
                }
            }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actionArea: some View {
        if candidates.isEmpty {
            Button {
                dismiss()
            } label: {
                Text("Back to workout")
            }
            .buttonStyle(SecondaryButtonStyle())
        } else if phase == .complete, let result {
            HStack(spacing: 9) {
                if result.poolSize > 1 {
                    Button("Try another") {
                        beginSearch()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("find-another-exercise-button")
                }
                Button("Add exercise") {
                    NativeFeedback.success()
                    onSelect(result.selected.template)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("add-recommended-exercise-button")
            }
        } else {
            Button {
                beginSearch()
            } label: {
                Label(isSearching ? "Scanning…" : "Find a match", systemImage: "sparkles")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSearching)
            .accessibilityIdentifier("find-best-exercise-button")
        }
    }

    // MARK: Search

    private func refreshCandidates() {
        searchTask?.cancel()
        let engine = ExerciseRecommendationEngine(
            library: library,
            sessions: sessions,
            currentExerciseNames: currentExerciseNames
        )
        candidates = engine.candidates(for: selectedMuscleID)
        selector.reset()
        phase = .idle
        result = nil
        tickerIndex = 0
        sweeping = false
    }

    private func beginSearch() {
        guard !candidates.isEmpty else { return }
        searchTask?.cancel()
        // Decide first; the animation only reveals it.
        guard let outcome = selector.select(from: candidates) else { return }

        result = nil
        phase = .scanning
        tickerIndex = 0
        NativeFeedback.light()

        searchTask = Task { @MainActor in
            if reduceMotion || candidates.count == 1 {
                guard await pause(milliseconds: 120) else { return }
            } else {
                sweeping = true
                let ticks = min(max(candidates.count * 2, 6), 12)
                for tick in 0..<ticks {
                    guard await pause(milliseconds: tick < ticks - 3 ? 85 : 150) else { return }
                    tickerIndex = tick + 1
                    if tick % 3 == 0 { NativeFeedback.selection() }
                }
                sweeping = false
            }

            withAnimation(reduceMotion ? nil : AppMotion.smooth) {
                phase = .complete
                result = outcome
            }
            NativeFeedback.success()
            UIAccessibility.post(notification: .announcement, argument: "Match found: \(outcome.selected.template.name). \(outcome.selected.reason)")
        }
    }

    @MainActor
    private func pause(milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

// MARK: - Reticle

/// Concentric rings with a sweeping beam while scanning and a solid core once
/// matched. Purely decorative; it never encodes anything the engine didn't do.
private struct FinderReticle: View {
    let phase: ExerciseFinderPhase
    let sweeping: Bool
    let reduceMotion: Bool
    let symbol: String

    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(Theme.accent.opacity(ringOpacity(ring)), lineWidth: ring == 0 ? 1.4 : 1)
                    .frame(width: ringSize(ring), height: ringSize(ring))
            }

            if phase == .scanning && !reduceMotion {
                AngularGradient(
                    colors: [.clear, .clear, Theme.accent.opacity(0.05), Theme.accent.opacity(0.55)],
                    center: .center
                )
                .clipShape(Circle())
                .frame(width: ringSize(2), height: ringSize(2))
                .rotationEffect(.degrees(angle))
                .blendMode(.screen)
            }

            core
        }
        .frame(maxWidth: .infinity)
        .onChange(of: sweeping) { _, active in
            guard !reduceMotion else { return }
            if active {
                angle = 0
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { angle = 360 }
            } else {
                withAnimation(AppMotion.quick) { angle = 0 }
            }
        }
    }

    private var core: some View {
        ZStack {
            Circle()
                .fill(phase == .complete ? Theme.accent : Theme.surface2)
                .shadow(color: Theme.accent.opacity(phase == .complete ? 0.6 : 0.18), radius: phase == .complete ? 22 : 12)
            Circle()
                .stroke(phase == .complete ? Theme.accent : Theme.accent.opacity(0.55), lineWidth: 1.5)
            Image(systemName: phase == .complete ? "checkmark" : symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(phase == .complete ? .black : Theme.accent)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 64, height: 64)
        .scaleEffect(phase == .complete ? 1.08 : (phase == .scanning ? 0.96 : 1))
        .animation(reduceMotion ? nil : AppMotion.smooth, value: phase)
    }

    private func ringSize(_ ring: Int) -> CGFloat {
        [92, 118, 146][ring]
    }

    private func ringOpacity(_ ring: Int) -> Double {
        switch phase {
        case .idle: return [0.45, 0.28, 0.16][ring]
        case .scanning: return [0.7, 0.42, 0.24][ring]
        case .complete: return [0.85, 0.35, 0.14][ring]
        }
    }
}

// MARK: - Factor chips

private struct FinderFactorChip: View {
    let factor: ExerciseRecommendationFactor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: factor.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(factor.label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(factor.isPositive ? Theme.accent : Theme.muted2)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(factor.isPositive ? Theme.accentDim : Theme.surface2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(factor.isPositive ? Theme.accent.opacity(0.4) : Theme.border))
        .accessibilityLabel(factor.label)
    }
}

/// Wraps chips onto new lines instead of letting a long factor list clip or
/// overflow at large Dynamic Type.
struct FinderFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(width: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = arrange(width: bounds.width, subviews: subviews)
        // Center each row within the available width.
        for (index, frame) in placement.frames.enumerated() {
            let rowOffset = (bounds.width - placement.rowWidths[placement.rows[index]]) / 2
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX + max(rowOffset, 0), y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct Arrangement {
        var frames: [CGRect] = []
        var rows: [Int] = []
        var rowWidths: [CGFloat] = []
        var size: CGSize = .zero
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> Arrangement {
        var arrangement = Arrangement()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var row = 0
        var rowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                arrangement.rowWidths.append(rowWidth)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
                row += 1
                rowWidth = 0
            }
            arrangement.frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            arrangement.rows.append(row)
            x += size.width + spacing
            rowWidth = x - spacing
            rowHeight = max(rowHeight, size.height)
        }
        arrangement.rowWidths.append(rowWidth)
        arrangement.size = CGSize(width: width.isFinite ? width : rowWidth, height: y + rowHeight)
        return arrangement
    }
}
