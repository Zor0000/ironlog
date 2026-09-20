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

/// The graph's route plan stays valid even when the current workout excludes
/// most of a muscle group's catalog. Keeping it separate from the view makes
/// the animated path deterministic and independently testable.
struct ExerciseFinderGraphRoute: Equatable {
    let from: String
    let to: String
}

enum ExerciseFinderGraphPlan {
    static let originNodeID = "origin"
    static let historyNodeID = "history"
    static let patternNodeID = "pattern"
    static let goalNodeID = "goal"

    static func decisionNodeID(for candidateIndex: Int) -> String {
        candidateIndex < 2 ? historyNodeID : patternNodeID
    }

    static func scanRoutes(candidateNodeIDs: [String]) -> [ExerciseFinderGraphRoute] {
        guard !candidateNodeIDs.isEmpty else { return [] }

        var routes = [ExerciseFinderGraphRoute(from: originNodeID, to: historyNodeID)]
        routes += candidateNodeIDs.prefix(2).map {
            ExerciseFinderGraphRoute(from: historyNodeID, to: $0)
        }

        let patternCandidates = candidateNodeIDs.dropFirst(2)
        guard !patternCandidates.isEmpty else { return routes }

        routes.append(ExerciseFinderGraphRoute(from: originNodeID, to: patternNodeID))
        routes += patternCandidates.map {
            ExerciseFinderGraphRoute(from: patternNodeID, to: $0)
        }
        return routes
    }
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
    @State private var activeNodeID: String?
    @State private var activeEdgeID: String?
    @State private var visitedNodeIDs: Set<String> = []
    @State private var visitedEdgeIDs: Set<String> = []
    @State private var routeProgress: CGFloat = 0
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
            let layout = graphLayout(in: size)
            let edges = graphEdges

            ZStack {
                FinderDotGrid()

                ForEach(edges) { edge in
                    if let from = layout[edge.from], let to = layout[edge.to] {
                        let isActive = activeEdgeID == edge.id
                        let isVisited = visitedEdgeIDs.contains(edge.id)
                        let isWinningPath = winningPathEdgeIDs.contains(edge.id)
                        FinderConnection(from: from, to: to)
                            .stroke(
                                (isActive || isWinningPath) ? Theme.accent.opacity(0.28) : Theme.border.opacity(0.8),
                                style: StrokeStyle(lineWidth: (isActive || isWinningPath) ? 5 : 1, lineCap: .round)
                            )
                            .blur(radius: (isActive || isWinningPath) ? 4 : 0)
                        FinderConnection(from: from, to: to)
                            .stroke(
                                (isActive || isWinningPath) ? Theme.accent : (isVisited ? Theme.accent.opacity(0.48) : Theme.muted.opacity(0.42)),
                                style: StrokeStyle(lineWidth: (isActive || isWinningPath) ? 1.7 : 1, lineCap: .round)
                            )
                    }
                }

                FinderGraphNode(
                    title: hubTitle,
                    subtitle: hubSubtitle,
                    isHub: true,
                    isGoal: false,
                    isActive: activeNodeID == Self.rootNodeID,
                    isVisited: visitedNodeIDs.contains(Self.rootNodeID),
                    isFinalist: false,
                    isWinner: false,
                    isMuted: phase == .complete,
                    isPulsing: hubPulse
                )
                .frame(width: 78, height: 78)
                .position(layout[Self.rootNodeID] ?? .zero)
                .accessibilityLabel("\(selectedMuscle?.label ?? "Muscle") muscle group")

                ForEach(graphDecisionNodes) { node in
                    FinderGraphNode(
                        title: node.title,
                        subtitle: node.subtitle,
                        isHub: false,
                        isGoal: false,
                        isActive: activeNodeID == node.id,
                        isVisited: visitedNodeIDs.contains(node.id),
                        isFinalist: false,
                        isWinner: false,
                        isMuted: phase == .complete,
                        isPulsing: false
                    )
                    .frame(width: 74, height: 74)
                    .position(layout[node.id] ?? .zero)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(node.title) evaluation node")
                }

                ForEach(Array(recommendations.enumerated()), id: \.element.id) { _, recommendation in
                    if layout[candidateNodeID(recommendation)] != nil {
                        FinderGraphNode(
                            title: shortName(recommendation.template.name),
                            subtitle: recommendation.movementStyle,
                            isHub: false,
                            isGoal: false,
                            isActive: activeNodeID == candidateNodeID(recommendation),
                            isVisited: visitedNodeIDs.contains(candidateNodeID(recommendation)),
                            isFinalist: finalistIDs.contains(recommendation.id),
                            isWinner: winner?.id == recommendation.id,
                            isMuted: phase == .complete && winner?.id != recommendation.id,
                            isPulsing: false
                        )
                        .frame(width: 80, height: 80)
                        .position(layout[candidateNodeID(recommendation)] ?? .zero)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(recommendation.template.name), \(recommendation.movementStyle)")
                    }
                }

                FinderGraphNode(
                    title: winner.map { shortName($0.template.name) } ?? "Best fit",
                    subtitle: winner == nil ? "Destination" : "Matched",
                    isHub: false,
                    isGoal: true,
                    isActive: activeNodeID == Self.goalNodeID,
                    isVisited: visitedNodeIDs.contains(Self.goalNodeID),
                    isFinalist: false,
                    isWinner: winner != nil,
                    isMuted: false,
                    isPulsing: false
                )
                .frame(width: 68, height: 68)
                .position(layout[Self.goalNodeID] ?? .zero)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(winner.map { "Best match: \($0.template.name)" } ?? "Best-match destination")

                if let activeEdgeID,
                   let edge = edges.first(where: { $0.id == activeEdgeID }),
                   let from = layout[edge.from],
                   let to = layout[edge.to] {
                    FinderTraversalPulse(from: from, to: to, progress: routeProgress)
                }

                HStack(spacing: 8) {
                    Image(systemName: phase == .complete ? "checkmark.circle.fill" : "point.topleft.down.curvedto.point.bottomright.up")
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
        case .charging: return "Start"
        case .scanning, .narrowing: return "Search"
        case .complete: return "Origin"
        case .idle: return selectedMuscle?.label ?? "Muscle"
        }
    }

    private var hubSubtitle: String {
        switch phase {
        case .charging: return "Muscle group"
        case .scanning: return "Traversing"
        case .narrowing: return "Shortest path"
        case .complete: return selectedMuscle?.label.uppercased() ?? "MUSCLE"
        case .idle: return "Muscle group"
        }
    }

    private var statusText: String {
        switch phase {
        case .idle: return "Ready to trace the best route"
        case .charging: return "Setting the starting node"
        case .scanning: return "Exploring the decision graph"
        case .narrowing: return "Locking the shortest path"
        case .complete: return "Best exercise reached"
        }
    }

    private var statusProgress: String {
        switch phase {
        case .idle: return "\(recommendations.count) endpoints"
        case .charging: return "Origin"
        case .scanning: return "\(scanStep)/\(scanningRoutes(for: recommendations).count) paths"
        case .narrowing: return "\(finalistIDs.count) routes"
        case .complete: return "Reached"
        }
    }

    private static let rootNodeID = ExerciseFinderGraphPlan.originNodeID
    private static let historyNodeID = ExerciseFinderGraphPlan.historyNodeID
    private static let patternNodeID = ExerciseFinderGraphPlan.patternNodeID
    private static let goalNodeID = ExerciseFinderGraphPlan.goalNodeID

    private var graphDecisionNodes: [FinderGraphDecisionNode] {
        var nodes = [FinderGraphDecisionNode(id: Self.historyNodeID, title: "Rotation", subtitle: "Recent use")]
        if recommendations.count > 2 {
            nodes.append(FinderGraphDecisionNode(id: Self.patternNodeID, title: "Fit", subtitle: "Movement"))
        }
        return nodes
    }

    private var graphEdges: [FinderGraphEdge] {
        guard !recommendations.isEmpty else { return [] }

        var edges = [FinderGraphEdge(from: Self.rootNodeID, to: Self.historyNodeID)]
        if recommendations.count > 2 {
            edges.append(FinderGraphEdge(from: Self.rootNodeID, to: Self.patternNodeID))
        }
        edges += recommendations.enumerated().map { index, recommendation in
            FinderGraphEdge(from: decisionNodeID(for: index), to: candidateNodeID(recommendation))
        }
        edges += recommendations.map { recommendation in
            FinderGraphEdge(from: candidateNodeID(recommendation), to: Self.goalNodeID)
        }
        return edges
    }

    private var winningPathEdgeIDs: Set<String> {
        guard let winner,
              let index = recommendations.firstIndex(where: { $0.id == winner.id }) else { return [] }
        let decision = decisionNodeID(for: index)
        let candidate = candidateNodeID(winner)
        return [
            FinderGraphEdge.id(from: Self.rootNodeID, to: decision),
            FinderGraphEdge.id(from: decision, to: candidate),
            FinderGraphEdge.id(from: candidate, to: Self.goalNodeID)
        ]
    }

    private func graphLayout(in size: CGSize) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [
            Self.rootNodeID: CGPoint(x: size.width * 0.13, y: size.height * 0.50),
            Self.historyNodeID: CGPoint(x: size.width * 0.38, y: size.height * 0.30),
            Self.patternNodeID: CGPoint(x: size.width * 0.38, y: size.height * 0.70),
            Self.goalNodeID: CGPoint(x: size.width * 0.89, y: size.height * 0.50)
        ]
        for (index, recommendation) in recommendations.enumerated() {
            positions[candidateNodeID(recommendation)] = CGPoint(
                x: size.width * 0.65,
                y: candidateYPosition(for: index, height: size.height)
            )
        }
        return positions
    }

    private func candidateYPosition(for index: Int, height: CGFloat) -> CGFloat {
        guard recommendations.count > 1 else { return height * 0.5 }
        let clampedIndex = min(max(index, 0), recommendations.count - 1)
        let progress = CGFloat(clampedIndex) / CGFloat(recommendations.count - 1)
        return height * (0.13 + (0.74 * progress))
    }

    private func candidateNodeID(_ recommendation: ExerciseRecommendation) -> String {
        "candidate/\(recommendation.id)"
    }

    private func decisionNodeID(for candidateIndex: Int) -> String {
        ExerciseFinderGraphPlan.decisionNodeID(for: candidateIndex)
    }

    private func scanningRoutes(for candidates: [ExerciseRecommendation]) -> [ExerciseFinderGraphRoute] {
        ExerciseFinderGraphPlan.scanRoutes(candidateNodeIDs: candidates.map(candidateNodeID))
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
        activeNodeID = nil
        activeEdgeID = nil
        visitedNodeIDs = []
        visitedEdgeIDs = []
        routeProgress = 0
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
        activeNodeID = Self.rootNodeID
        activeEdgeID = nil
        visitedNodeIDs = [Self.rootNodeID]
        visitedEdgeIDs = []
        routeProgress = 0
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
                let routes = scanningRoutes(for: candidates)
                for (index, route) in routes.enumerated() {
                    guard await traverse(from: route.from, to: route.to, duration: 170) else { return }
                    scanStep = index + 1
                    guard await pause(milliseconds: index == routes.indices.last ? 220 : 80) else { return }
                }

                phase = .narrowing
                let otherIndex = (winnerIndex + 1) % candidates.count
                finalistIDs = [selectedWinner.id, candidates[otherIndex].id]
                NativeFeedback.selection()
                if otherIndex != winnerIndex {
                    guard await traverse(
                        from: decisionNodeID(for: otherIndex),
                        to: candidateNodeID(candidates[otherIndex]),
                        duration: 180
                    ) else { return }
                }
                guard await traverse(
                    from: decisionNodeID(for: winnerIndex),
                    to: candidateNodeID(selectedWinner),
                    duration: 210
                ) else { return }
                guard await pause(milliseconds: 180) else { return }
                guard await traverse(
                    from: candidateNodeID(selectedWinner),
                    to: Self.goalNodeID,
                    duration: 290
                ) else { return }
            }

            withAnimation(AppMotion.smooth) {
                phase = .complete
                hubPulse = false
                activeNodeID = Self.goalNodeID
                activeEdgeID = nil
                finalistIDs = []
                winner = selectedWinner
            }
            NativeFeedback.success()
            UIAccessibility.post(notification: .announcement, argument: "Best match found: \(selectedWinner.template.name)")
        }
    }

    @MainActor
    private func traverse(from: String, to: String, duration: UInt64) async -> Bool {
        guard !Task.isCancelled else { return false }
        let edgeID = FinderGraphEdge.id(from: from, to: to)
        guard graphEdges.contains(where: { $0.id == edgeID }) else { return false }
        activeNodeID = from
        activeEdgeID = edgeID
        routeProgress = 0
        withAnimation(.linear(duration: Double(duration) / 1_000)) {
            routeProgress = 1
        }
        guard await pause(milliseconds: duration) else { return false }
        visitedEdgeIDs.insert(edgeID)
        visitedNodeIDs.insert(to)
        withAnimation(AppMotion.quick) {
            activeNodeID = to
        }
        return true
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
    let isGoal: Bool
    let isActive: Bool
    let isVisited: Bool
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
                colors: [Theme.accent.opacity(isActive || isVisited || isFinalist || isHub ? 0.14 : (isGoal ? 0.06 : 0.035)), Theme.surface],
                center: .center,
                startRadius: 0,
                endRadius: 54
            )
        )
    }

    private var border: Color {
        if isWinner { return Theme.accent }
        if isActive { return Theme.accent.opacity(0.95) }
        if isVisited || isFinalist || isHub { return Theme.accent.opacity(0.65) }
        return Theme.muted.opacity(0.52)
    }

    private var primaryGlow: Double {
        if isWinner { return 0.72 }
        if isActive { return 0.58 }
        if isVisited || isFinalist || isHub { return 0.28 }
        return 0
    }

    private var secondaryGlow: Double {
        if isWinner { return 0.32 }
        if isActive { return 0.22 }
        if isVisited || isHub { return 0.11 }
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

private struct FinderGraphDecisionNode: Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

private struct FinderGraphEdge: Identifiable {
    let from: String
    let to: String

    var id: String { Self.id(from: from, to: to) }

    static func id(from: String, to: String) -> String {
        "\(from)→\(to)"
    }
}

/// A single traveling signal makes the recommendation process legible: it
/// leaves the selected muscle, visits each decision branch, then lands on the
/// chosen exercise. The result itself is deterministic; this only visualizes it.
private struct FinderTraversalPulse: View {
    let from: CGPoint
    let to: CGPoint
    let progress: CGFloat

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 11, height: 11)
            .shadow(color: Theme.accent.opacity(0.95), radius: 9)
            .shadow(color: Theme.accent.opacity(0.54), radius: 20)
            .position(
                x: from.x + ((to.x - from.x) * progress),
                y: from.y + ((to.y - from.y) * progress)
            )
            .accessibilityHidden(true)
            .allowsHitTesting(false)
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
