import Foundation

/// A catalog exercise paired with the muscle group it belongs to, used by the
/// "Add Exercise" search so results can show their muscle context.
struct CatalogExercise: Identifiable, Hashable {
    let template: ExerciseTemplate
    let muscle: Muscle
    var id: String { "\(muscle.id)/\(template.name)" }
}

struct ExerciseLibrary: Codable {
    /// Day-less split that trains the whole body in one session, resolving to
    /// every muscle group at once (every other split is day-based).
    static let fullBodySplit = "Full Body"
    static let fullBodyMuscleIDs = ["chest", "back", "legs", "shoulders", "arms", "core"]

    var splits: [String]
    var muscles: [Muscle]
    var splitDays: [String: [SplitDay]]
    var workouts: [String: [String: [ExerciseTemplate]]]
    /// Full, split-independent exercise catalog keyed by muscle id. Powers the
    /// "Add Exercise" library. Falls back to a deduped view of `workouts` when
    /// the bundled data predates the catalog.
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
        self.library = library.isEmpty ? Self.derivedCatalog(from: workouts) : library
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        splits = try container.decode([String].self, forKey: .splits)
        muscles = try container.decode([Muscle].self, forKey: .muscles)
        splitDays = try container.decode([String: [SplitDay]].self, forKey: .splitDays)
        workouts = try container.decode([String: [String: [ExerciseTemplate]]].self, forKey: .workouts)
        let decoded = try container.decodeIfPresent([String: [ExerciseTemplate]].self, forKey: .library) ?? [:]
        library = decoded.isEmpty ? Self.derivedCatalog(from: workouts) : decoded
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

    private static func derivedCatalog(from workouts: [String: [String: [ExerciseTemplate]]]) -> [String: [ExerciseTemplate]] {
        var result: [String: [ExerciseTemplate]] = [:]
        for byMuscle in workouts.values {
            for (muscleID, templates) in byMuscle {
                var seen = Set(result[muscleID]?.map(\.name) ?? [])
                var merged = result[muscleID] ?? []
                for template in templates where seen.insert(template.name).inserted {
                    merged.append(template)
                }
                result[muscleID] = merged
            }
        }
        return result
    }

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

    func exercises(split: String?, muscle: String?) -> [ExerciseTemplate] {
        guard let split, let muscle else { return [] }
        return workouts[split]?[muscle] ?? []
    }

    /// Muscle groups trained by a split's selection. A picked day resolves to its
    /// muscles; the day-less Full Body resolves to the whole body.
    func muscleIDs(split: String?, day: String?) -> [String] {
        guard let split else { return [] }
        if let day, let ids = splitDays[split]?.first(where: { $0.day == day })?.muscles {
            return ids
        }
        if split == Self.fullBodySplit {
            return Self.fullBodyMuscleIDs
        }
        return []
    }

    func exercises(split: String?, day: String?) -> [ExerciseTemplate] {
        muscleIDs(split: split, day: day).flatMap { exercises(split: split, muscle: $0) }
    }
}
