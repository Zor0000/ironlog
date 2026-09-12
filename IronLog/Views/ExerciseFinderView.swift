import SwiftUI
import UIKit

struct ExerciseRecommendation: Identifiable, Equatable {
    let template: ExerciseTemplate
    let muscle: Muscle
    let score: Int
    let movementStyle: String
    let reason: String

    var id: String { "\(muscle.id)/\(template.id)" }
}

/// A small, deterministic recommendation layer. The animation visualizes this
/// result; it never races the UI or changes the winner while the scan is running.
struct ExerciseRecommendationEngine {
    let library: ExerciseLibrary
    let sessions: [WorkoutSession]
    let currentExerciseNames: Set<String>
    var now = Date()

    func recommendations(for muscleID: String, limit: Int = 5) -> [ExerciseRecommendation] {
        guard let muscle = library.muscle(muscleID),
              let templates = library.library[muscleID],
              limit > 0 else { return [] }

        let currentNames = Set(currentExerciseNames.map { $0.lowercased() })
        let latestUse = latestUseByExercise()
        let currentHasCompound = library.library.values
            .joined()
            .contains { template in
                currentNames.contains(template.name.lowercased()) && Self.movementStyle(for: template) == "Compound"
            }

        let ranked = templates.enumerated().compactMap { index, template -> ExerciseRecommendation? in
            guard !currentNames.contains(template.name.lowercased()) else { return nil }

            let lastUsed = latestUse[template.name.lowercased()]
            let daysSinceUse = lastUsed.map(daysSince)
            var score = 120 - (index * 3) // The catalog's order is the editorial baseline.

            if let daysSinceUse {
                switch daysSinceUse {
                case 0...2: score -= 38
                case 3...6: score -= 20
                case 7...13: score -= 8
                default: score += 4
                }
                score += 3 // Familiar movements keep a small usability advantage.
            } else {
                score += 7 // Introduce some variety without overpowering catalog quality.
            }

            let style = Self.movementStyle(for: template)
            if !currentHasCompound && style == "Compound" { score += 9 }
            if currentHasCompound && style == "Isolation" { score += 5 }

            return ExerciseRecommendation(
                template: template,
                muscle: muscle,
                score: score,
                movementStyle: style,
                reason: reason(muscle: muscle, daysSinceUse: daysSinceUse)
            )
        }

        return Array(ranked.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.template.name.localizedStandardCompare($1.template.name) == .orderedAscending
        }.prefix(limit))
    }

    static func movementStyle(for template: ExerciseTemplate) -> String {
        if template.timed { return "Timed" }

        let name = template.name.lowercased()
        let compoundMarkers = [
            "press", "squat", "deadlift", "row", "pull-up", "chin-up",
            "lunge", "dip", "push-up", "step-up", "hip thrust"
        ]
        if compoundMarkers.contains(where: name.contains) { return "Compound" }
        if template.bodyweight { return "Bodyweight" }
        return "Isolation"
    }

    private func latestUseByExercise() -> [String: Date] {
        var dates: [String: Date] = [:]
        for session in sessions {
            for exercise in session.exercises {
                let key = exercise.name.lowercased()
                if dates[key].map({ session.createdAt > $0 }) ?? true {
                    dates[key] = session.createdAt
                }
            }
        }
        return dates
    }

    private func daysSince(_ date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(date, now))
        let end = calendar.startOfDay(for: now)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }

    private func reason(muscle: Muscle, daysSinceUse: Int?) -> String {
        guard let daysSinceUse else {
            return "A fresh choice from your \(muscle.label.lowercased()) library."
        }
        if daysSinceUse >= 14 {
            return "Back in rotation after \(daysSinceUse) days."
        }
        return "Balances catalog quality with your recent training."
    }
}

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
    case charging
    case scanning
    case narrowing
    case complete

    var isSearching: Bool {
        self == .charging || self == .scanning || self == .narrowing
    }
}

struct ExerciseFinderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let library: ExerciseLibrary
    let sessions: [WorkoutSession]
    let currentExerciseNames: Set<String>
    let onSelect: (ExerciseTemplate) -> Void

    @State private var selectedMuscleID: String
    @State private var recommendations: [ExerciseRecommendation] = []
    @State private var phase: ExerciseFinderPhase = .idle
    @State private var activeCandidateID: String?
    @State private var finalistIDs: Set<String> = []
    @State private var winner: ExerciseRecommendation?
    @State private var alternativeOffset = 0
    @State private var scanStep = 0
    @State private var hubPulse = false
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
            GeometryReader { proxy in
                ZStack {
                    NativeBackground()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            musclePicker
                            graph
                                .frame(height: max(330, min(410, proxy.size.height * 0.5)))
                            actionArea
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
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
        .onAppear(perform: refreshRecommendations)
        .onChange(of: selectedMuscleID) { _, _ in refreshRecommendations() }
        .onDisappear { searchTask?.cancel() }
    }

    private var selectedMuscle: Muscle? {
        library.muscle(selectedMuscleID)
    }

    private var musclePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Starting muscle group")
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
                            guard !phase.isSearching else { return }
                            NativeFeedback.selection()
                            withAnimation(AppMotion.quick) { selectedMuscleID = muscle.id }
                        } label: {
                            Pill(text: muscle.label, icon: muscle.systemImage, isActive: selectedMuscleID == muscle.id)
                        }
                        .buttonStyle(TactileButtonStyle())
                        .disabled(phase.isSearching)
                        .accessibilityAddTraits(selectedMuscleID == muscle.id ? .isSelected : [])
                        .accessibilityIdentifier("exercise-finder-muscle-\(muscle.id)")
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var graph: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let hub = CGPoint(x: size.width * 0.5, y: size.height * 0.49)
            let positions = candidatePositions(in: size)

            ZStack {
                FinderDotGrid()

                ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, recommendation in
                    if positions.indices.contains(index) {
                        let highlighted = isHighlighted(recommendation)
                        FinderConnection(from: hub, to: positions[index])
                            .stroke(
                                highlighted ? Theme.accent.opacity(0.34) : Theme.border.opacity(0.8),
                                style: StrokeStyle(lineWidth: highlighted ? 5 : 1, lineCap: .round)
                            )
                            .blur(radius: highlighted ? 4 : 0)
                        FinderConnection(from: hub, to: positions[index])
                            .stroke(
                                highlighted ? Theme.accent : Theme.muted.opacity(0.55),
                                style: StrokeStyle(lineWidth: highlighted ? 1.5 : 1, lineCap: .round)
                            )
                    }
                }

                FinderGraphNode(
                    title: hubTitle,
                    subtitle: hubSubtitle,
                    isHub: true,
                    isActive: phase.isSearching,
                    isFinalist: false,
                    isWinner: false,
                    isMuted: false,
                    isPulsing: hubPulse
                )
                .frame(width: 106, height: 106)
                .position(hub)
                .accessibilityLabel("\(selectedMuscle?.label ?? "Muscle") muscle group")

                ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, recommendation in
                    if positions.indices.contains(index) {
                        FinderGraphNode(
                            title: shortName(recommendation.template.name),
                            subtitle: recommendation.movementStyle,
                            isHub: false,
                            isActive: activeCandidateID == recommendation.id,
                            isFinalist: finalistIDs.contains(recommendation.id),
                            isWinner: winner?.id == recommendation.id,
                            isMuted: phase == .complete && winner?.id != recommendation.id,
                            isPulsing: false
                        )
                        .frame(width: 88, height: 88)
                        .position(positions[index])
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(recommendation.template.name), \(recommendation.movementStyle)")
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: phase == .complete ? "checkmark.circle.fill" : "sparkle.magnifyingglass")
                        .foregroundStyle(Theme.accent)
                    Text(statusText)
                    Spacer(minLength: 4)
                    Text(statusProgress)
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(Theme.muted2)
                .padding(.horizontal, 12)
                .position(x: size.width / 2, y: size.height - 16)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("exercise-finder-status")
            }
            .background(Theme.bg.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border.opacity(0.8))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Exercise recommendation graph")
    }

    @ViewBuilder
    private var actionArea: some View {
        if recommendations.isEmpty {
            ContentUnavailableView(
                "No matches available",
                systemImage: "dumbbell",
                description: Text("Every exercise in this muscle group is already in the workout.")
            )
            .foregroundStyle(Theme.muted2)
        } else if let winner {
            FinderResultCard(recommendation: winner) {
                alternativeOffset += 1
                beginSearch()
            } onAdd: {
                NativeFeedback.success()
                onSelect(winner.template)
                dismiss()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.98)))
        } else {
            VStack(spacing: 9) {
                Button {
                    beginSearch()
                } label: {
                    Label(phase.isSearching ? "Finding your match…" : "Find best match", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(phase.isSearching)
                .accessibilityIdentifier("find-best-exercise-button")

                Text("Uses your muscle choice, current workout and recent exercise history.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var hubTitle: String {
        switch phase {
        case .charging: return selectedMuscle?.label ?? "Muscle"
        case .scanning, .narrowing: return "Finding"
        case .complete: return "Matched"
        case .idle: return selectedMuscle?.label ?? "Muscle"
        }
    }

    private var hubSubtitle: String {
        switch phase {
        case .charging: return "Activating"
        case .scanning: return "Best match"
        case .narrowing: return "Finalists"
        case .complete: return selectedMuscle?.label.uppercased() ?? "COMPLETE"
        case .idle: return "Muscle group"
        }
    }

    private var statusText: String {
        switch phase {
        case .idle: return "Ready to evaluate exercises"
        case .charging: return "Activating muscle group"
        case .scanning: return "Comparing movement patterns"
        case .narrowing: return "Narrowing strongest matches"
        case .complete: return "Best match selected"
        }
    }

    private var statusProgress: String {
        switch phase {
        case .idle: return "\(recommendations.count) candidates"
        case .charging: return "Starting"
        case .scanning: return "\(scanStep)/10 checks"
        case .narrowing: return "\(finalistIDs.count) finalists"
        case .complete: return "Complete"
        }
    }

    private func candidatePositions(in size: CGSize) -> [CGPoint] {
        [
            CGPoint(x: size.width * 0.50, y: size.height * 0.15),
            CGPoint(x: size.width * 0.82, y: size.height * 0.32),
            CGPoint(x: size.width * 0.76, y: size.height * 0.73),
            CGPoint(x: size.width * 0.24, y: size.height * 0.73),
            CGPoint(x: size.width * 0.18, y: size.height * 0.32)
        ]
    }

    private func isHighlighted(_ recommendation: ExerciseRecommendation) -> Bool {
        activeCandidateID == recommendation.id || finalistIDs.contains(recommendation.id) || winner?.id == recommendation.id
    }

    private func shortName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "Barbell ", with: "")
            .replacingOccurrences(of: "Dumbbell ", with: "DB ")
            .replacingOccurrences(of: " (Machine)", with: "")
    }

    private func refreshRecommendations() {
        searchTask?.cancel()
        let engine = ExerciseRecommendationEngine(
            library: library,
            sessions: sessions,
            currentExerciseNames: currentExerciseNames
        )
        recommendations = engine.recommendations(for: selectedMuscleID)
        phase = .idle
        activeCandidateID = nil
        finalistIDs = []
        winner = nil
        alternativeOffset = 0
        scanStep = 0
        hubPulse = false
    }

    private func beginSearch() {
        guard !recommendations.isEmpty else { return }
        searchTask?.cancel()
        let candidates = recommendations
        let winnerIndex = alternativeOffset % candidates.count
        let selectedWinner = candidates[winnerIndex]

        winner = nil
        finalistIDs = []
        activeCandidateID = nil
        scanStep = 0
        phase = .charging
        hubPulse = !reduceMotion
        NativeFeedback.light()

        searchTask = Task { @MainActor in
            if reduceMotion {
                guard await pause(milliseconds: 120) else { return }
            } else {
                guard await pause(milliseconds: 430) else { return }
                phase = .scanning
                let timings: [UInt64] = [115, 115, 125, 125, 135, 145, 160, 185, 230, 300]
                for step in timings.indices {
                    guard !Task.isCancelled else { return }
                    let candidateIndex = step == timings.count - 1
                        ? winnerIndex
                        : ((step * 2) + 1) % candidates.count
                    withAnimation(.easeInOut(duration: 0.18)) {
                        activeCandidateID = candidates[candidateIndex].id
                        scanStep = step + 1
                    }
                    guard await pause(milliseconds: timings[step]) else { return }
                }

                phase = .narrowing
                activeCandidateID = nil
                let otherIndex = (winnerIndex + 1) % candidates.count
                finalistIDs = [selectedWinner.id, candidates[otherIndex].id]
                NativeFeedback.selection()
                guard await pause(milliseconds: 390) else { return }
            }

            withAnimation(AppMotion.smooth) {
                phase = .complete
                hubPulse = false
                activeCandidateID = nil
                finalistIDs = []
                winner = selectedWinner
            }
            NativeFeedback.success()
            UIAccessibility.post(notification: .announcement, argument: "Best match found: \(selectedWinner.template.name)")
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

private struct FinderResultCard: View {
    let recommendation: ExerciseRecommendation
    let onTryAnother: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 44, height: 44)
                .shadow(color: Theme.accent.opacity(0.28), radius: 16)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Best match found")
                        .cardLabel()
                        .foregroundStyle(Theme.accent)
                    Text(recommendation.template.name)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(Theme.muted2)
                }
                Spacer(minLength: 0)
            }

            Text(recommendation.reason)
                .font(.subheadline)
                .foregroundStyle(Theme.muted2)

            HStack(spacing: 9) {
                Button("Try another", action: onTryAnother)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("find-another-exercise-button")
                Button("Add exercise", action: onAdd)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("add-recommended-exercise-button")
            }
        }
        .cardStyle()
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.accent.opacity(0.34))
        }
        .accessibilityElement(children: .contain)
    }

    private var meta: String {
        let unit = recommendation.template.timed
            ? (recommendation.template.minutes ? "min" : "sec")
            : "reps"
        return "\(recommendation.movementStyle) · \(recommendation.template.sets)×\(recommendation.template.reps) \(unit)"
    }
}

private struct FinderGraphNode: View {
    let title: String
    let subtitle: String
    let isHub: Bool
    let isActive: Bool
    let isFinalist: Bool
    let isWinner: Bool
    let isMuted: Bool
    let isPulsing: Bool

    var body: some View {
        VStack(spacing: 4) {
            if isHub {
                Image(systemName: "ellipsis")
                    .font(.caption2.weight(.bold))
            }
            Text(title)
                .font(isHub ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(isWinner ? Color.black.opacity(0.62) : (isHub ? Theme.accent.opacity(0.78) : Theme.muted))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(isWinner ? Color.black : Theme.text)
        .background {
            Circle().fill(fill)
        }
        .overlay {
            Circle().stroke(border, lineWidth: isWinner || isActive ? 1.5 : 1)
        }
        .shadow(color: Theme.accent.opacity(primaryGlow), radius: isWinner ? 17 : 10)
        .shadow(color: Theme.accent.opacity(secondaryGlow), radius: isWinner ? 34 : 22)
        .scaleEffect(scale)
        .opacity(isMuted ? 0.26 : 1)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .animation(AppMotion.smooth, value: isWinner)
        .animation(AppMotion.quick, value: isMuted)
        .animation(isPulsing ? .easeInOut(duration: 0.46).repeatForever(autoreverses: true) : AppMotion.quick, value: isPulsing)
    }

    private var fill: some ShapeStyle {
        if isWinner { return AnyShapeStyle(Theme.accent) }
        return AnyShapeStyle(
            RadialGradient(
                colors: [Theme.accent.opacity(isActive || isFinalist || isHub ? 0.14 : 0.035), Theme.surface],
                center: .center,
                startRadius: 0,
                endRadius: 54
            )
        )
    }

    private var border: Color {
        if isWinner { return Theme.accent }
        if isActive { return Theme.accent.opacity(0.95) }
        if isFinalist || isHub { return Theme.accent.opacity(0.65) }
        return Theme.muted.opacity(0.52)
    }

    private var primaryGlow: Double {
        if isWinner { return 0.72 }
        if isActive { return 0.58 }
        if isFinalist || isHub { return 0.28 }
        return 0
    }

    private var secondaryGlow: Double {
        if isWinner { return 0.32 }
        if isActive { return 0.22 }
        if isHub { return 0.11 }
        return 0
    }

    private var scale: CGFloat {
        if isWinner { return 1.12 }
        if isActive { return 1.07 }
        if isPulsing { return 1.045 }
        if isMuted { return 0.94 }
        return 1
    }
}

private struct FinderConnection: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

private struct FinderDotGrid: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 9
            while x < size.width {
                var y: CGFloat = 9
                while y < size.height {
                    let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                    context.fill(dot, with: .color(Theme.muted.opacity(0.14)))
                    y += 19
                }
                x += 19
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
