import Foundation

/// A catalog exercise paired with the muscle group it belongs to, used by the
/// "Add Exercise" search so results can show their muscle context.
struct CatalogExercise: Identifiable, Hashable {
    let template: ExerciseTemplate
    let muscle: Muscle
    var id: String { "\(muscle.id)/\(template.name)" }
}

struct ExerciseLibrary: Codable {
    var splits: [String]
    var muscles: [Muscle]
    var splitDays: [String: [SplitDay]]
    var workouts: [String: [String: [ExerciseTemplate]]]
    /// Full, split-independent exercise catalog keyed by muscle id. Powers the
    /// "Add Exercise" library.
    var library: [String: [ExerciseTemplate]]

    enum CodingKeys: String, CodingKey {
        case splits = "SPLITS"
        case muscles = "MUSCLES"
        case splitDays = "SPLIT_DAYS"
        case workouts = "WORKOUTS"
        case library = "LIBRARY"
    }

    init(
        splits: [String],
        muscles: [Muscle],
        splitDays: [String: [SplitDay]],
        workouts: [String: [String: [ExerciseTemplate]]],
        library: [String: [ExerciseTemplate]] = [:]
    ) {
        self.splits = splits
        self.muscles = muscles
        self.splitDays = splitDays
        self.workouts = workouts
        self.library = library
    }

    static let bundled: ExerciseLibrary = {
        guard let url = Bundle.main.url(forResource: "workouts", withExtension: "json") else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ExerciseLibrary.self, from: data)
        } catch {
            return .empty
        }
    }()

    static let empty = ExerciseLibrary(splits: [], muscles: [], splitDays: [:], workouts: [:])

    /// Preferred display order for catalog muscle filters.
    private static let catalogOrder = ["chest", "back", "legs", "shoulders", "biceps", "triceps", "arms", "core"]

    /// Muscle groups that have catalog entries, in display order.
    var catalogMuscles: [Muscle] {
        Self.catalogOrder.compactMap { id in
            (library[id]?.isEmpty == false) ? muscle(id) : nil
        }
    }

    /// Catalog exercises filtered by an optional muscle and a free-text query.
    func catalogExercises(muscleID: String?, query: String) -> [CatalogExercise] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let muscleIDs = muscleID.map { [$0] } ?? catalogMuscles.map(\.id)
        var results: [CatalogExercise] = []
        for id in muscleIDs {
            guard let muscle = muscle(id), let templates = library[id] else { continue }
            for template in templates where needle.isEmpty
                || template.name.lowercased().contains(needle)
                || template.tip.lowercased().contains(needle) {
                results.append(CatalogExercise(template: template, muscle: muscle))
            }
        }
        return results
    }

    func muscle(_ id: String?) -> Muscle? {
        guard let id else { return nil }
        return muscles.first { $0.id == id }
    }

    func visibleMuscles(split: String?, day: String?) -> [Muscle] {
        guard let split else { return [] }
        if let days = splitDays[split], let day {
            let ids = days.first { $0.day == day }?.muscles ?? []
            return ids.compactMap { id in muscles.first { $0.id == id } }
        }
        let ids = ["chest", "back", "legs", "shoulders", "arms", "core"]
        return ids.compactMap { id in muscles.first { $0.id == id } }
    }

    func exercises(split: String?, muscle: String?) -> [ExerciseTemplate] {
        guard let split, let muscle else { return [] }
        return workouts[split]?[muscle] ?? []
    }

    func muscleIDs(split: String?, day: String?, selectedMuscle: String?) -> [String] {
        guard let split else { return [] }
        if let day, let ids = splitDays[split]?.first(where: { $0.day == day })?.muscles {
            return ids
        }
        if let selectedMuscle {
            return [selectedMuscle]
        }
        return []
    }

    func exercises(split: String?, day: String?, selectedMuscle: String?) -> [ExerciseTemplate] {
        let ids = muscleIDs(split: split, day: day, selectedMuscle: selectedMuscle)
        return ids.flatMap { exercises(split: split, muscle: $0) }
    }
}
