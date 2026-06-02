import Foundation

struct ExerciseLibrary: Codable {
    var splits: [String]
    var muscles: [Muscle]
    var splitDays: [String: [SplitDay]]
    var workouts: [String: [String: [ExerciseTemplate]]]

    enum CodingKeys: String, CodingKey {
        case splits = "SPLITS"
        case muscles = "MUSCLES"
        case splitDays = "SPLIT_DAYS"
        case workouts = "WORKOUTS"
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
}
