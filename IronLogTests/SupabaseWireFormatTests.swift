import XCTest
@testable import IronLog

/// The shapes that cross the wire to Supabase. These run against the service's
/// own coders, so a change to its key strategy fails here rather than silently
/// in production — the REST layer itself needs a network and an account, so the
/// encode/decode boundary is where sync is actually testable.
final class SupabaseWireFormatTests: XCTestCase {
    private let encoder = SupabaseService.makeEncoder()
    private let decoder = SupabaseService.makeDecoder()

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Column names

    /// Every key here is a real column. A mismatch is a 400 from PostgREST at
    /// runtime, which the app swallows into "sync failed" with no detail.
    func testSessionInsertUsesSnakeCaseColumnNames() throws {
        let body = RemoteSessionInsert(
            userID: "u1", muscleGroup: "chest", splitType: "Run", note: "hi",
            activityType: "run", distanceM: 5000, durationS: 1800,
            route: [RoutePoint(lat: 51.5, lon: -0.12)],
            elevationGainM: 45, terrain: "trail", calories: 401
        )
        let keys = Set(try json(body).keys)
        XCTAssertEqual(keys, [
            "user_id", "muscle_group", "split_type", "note",
            "activity_type", "distance_m", "duration_s", "route",
            "elevation_gain_m", "terrain", "calories"
        ])
    }

    /// A strength session omits the cardio keys rather than sending nulls, and
    /// omits `muscle_group` for any workout that spans more than one muscle.
    /// Both rely on those columns being nullable — they were NOT NULL until the
    /// routines migration, so free workouts and multi-muscle days could not
    /// back up at all.
    func testStrengthSessionOmitsCardioAndUnknownMuscle() throws {
        let body = RemoteSessionInsert(
            userID: "u1", muscleGroup: nil, splitType: "Free Workout", note: nil,
            activityType: nil, distanceM: nil, durationS: nil, route: nil
        )
        XCTAssertEqual(Set(try json(body).keys), ["user_id", "split_type"])
    }

    func testSetInsertCarriesOrderingAndExerciseFlags() throws {
        let body = RemoteSetInsert(
            sessionID: "s1", exerciseID: "e1", weightKg: 100, reps: 5,
            setIndex: 3, bodyweight: false, timed: false, usesMinutes: false, setType: nil
        )
        let keys = Set(try json(body).keys)
        XCTAssertEqual(keys, [
            "session_id", "exercise_id", "weight_kg", "reps",
            "set_index", "bodyweight", "timed", "uses_minutes"
        ])
    }

    func testRoutineInsertSendsExercisesAsANestedDocument() throws {
        let routine = SavedRoutine(
            name: "Anshul's Leg Day",
            exercises: [ExerciseTemplate(name: "Barbell Squat", sets: 3, reps: "5", tip: "", minutes: false)]
        )
        let body = RemoteRoutineInsert(
            id: routine.id.uuidString, userID: "u1", name: routine.name,
            exercises: routine.exercises, createdAt: "2026-08-07T00:00:00Z",
            updatedAt: "2026-08-07T00:00:00Z"
        )
        let object = try json(body)
        XCTAssertEqual(Set(object.keys), ["id", "user_id", "name", "exercises", "created_at", "updated_at"])

        // The jsonb column takes an array, not a string — a stringified payload
        // would store fine and come back undecodable.
        let exercises = try XCTUnwrap(object["exercises"] as? [[String: Any]])
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0]["name"] as? String, "Barbell Squat")
        XCTAssertEqual(exercises[0]["sets"] as? Int, 3)
    }

    // MARK: - Reading back

    func testRoutineRoundTripsThroughTheJSONBColumn() throws {
        let id = UUID()
        let payload = """
        [{"id":"\(id.uuidString)","name":"Anshul's Pull Day","created_at":"2026-08-07T10:00:00Z",
          "exercises":[{"name":"Barbell Row","sets":4,"reps":"8","tip":"","bodyweight":false,"timed":false,"minutes":false},
                       {"name":"Pull Ups","sets":3,"reps":"10","tip":"","bodyweight":true,"timed":false,"minutes":false}]}]
        """
        let rows = try decoder.decode([RemoteRoutine].self, from: Data(payload.utf8))
        let routine = try XCTUnwrap(rows.first?.localRoutine())

        XCTAssertEqual(routine.id, id, "the row keeps the client's id, so an upsert updates in place")
        XCTAssertEqual(routine.name, "Anshul's Pull Day")
        XCTAssertEqual(routine.exercises.map(\.name), ["Barbell Row", "Pull Ups"])
        XCTAssertEqual(routine.exercises[0].sets, 4)
        XCTAssertTrue(routine.exercises[1].bodyweight)
    }

    func testCardioSessionComesBackAsATrackedActivity() throws {
        let payload = """
        [{"id":"c1","created_at":"2026-08-07T10:00:00Z","muscle_group":null,"split_type":"Run","note":null,
          "activity_type":"run","distance_m":5012.5,"duration_s":1830,
          "route":[{"lat":51.5,"lon":-0.12},{"lat":51.51,"lon":-0.121}],
          "elevation_gain_m":38,"terrain":"trail","calories":395,"session_sets":[]}]
        """
        let rows = try decoder.decode([RemoteSession].self, from: Data(payload.utf8))
        let session = try XCTUnwrap(rows.first).localSession(userID: "u1")

        XCTAssertTrue(session.isCardio)
        XCTAssertEqual(session.activity?.kind, .run)
        XCTAssertEqual(session.activity?.distance, 5012.5)
        XCTAssertEqual(session.activity?.duration, 1830)
        XCTAssertEqual(session.activity?.route.count, 2)
        XCTAssertEqual(session.activity?.route.first?.lat, 51.5)
        XCTAssertEqual(session.activity?.elevationGain, 38)
        XCTAssertEqual(session.activity?.terrain, .trail)
        XCTAssertEqual(session.activity?.calories, 395)
        XCTAssertTrue(session.exercises.isEmpty)
    }

    /// Rows written before the calorie columns existed carry no elevation,
    /// terrain or calories. They must still decode, with the new fields nil.
    func testCardioSessionWithoutTheCalorieColumnsStillDecodes() throws {
        let payload = """
        [{"id":"c1","created_at":"2026-08-07T10:00:00Z","muscle_group":null,"split_type":"Walk","note":null,
          "activity_type":"walk","distance_m":3200,"duration_s":2400,
          "route":[],"session_sets":[]}]
        """
        let rows = try decoder.decode([RemoteSession].self, from: Data(payload.utf8))
        let activity = try XCTUnwrap(rows.first).localSession(userID: "u1").activity

        XCTAssertEqual(activity?.kind, .walk)
        XCTAssertNil(activity?.elevationGain)
        XCTAssertNil(activity?.terrain)
        XCTAssertNil(activity?.calories)
    }

    func testStrengthSessionHasNoActivity() throws {
        let payload = """
        [{"id":"s1","created_at":"2026-08-07T10:00:00Z","muscle_group":"chest","split_type":"PPL",
          "note":null,"activity_type":null,"session_sets":[]}]
        """
        let rows = try decoder.decode([RemoteSession].self, from: Data(payload.utf8))
        XCTAssertFalse(try XCTUnwrap(rows.first).localSession(userID: "u1").isCardio)
    }

    /// PostgREST returns embedded rows in no guaranteed order, and grouping
    /// straight into a dictionary lost both exercise order and set order.
    func testSetIndexRestoresExerciseAndSetOrder() throws {
        // Deliberately shuffled, and interleaved between the two exercises.
        let payload = """
        [{"id":"s1","created_at":"2026-08-07T10:00:00Z","muscle_group":null,"split_type":"PPL","session_sets":[
          {"weight_kg":30,"reps":12,"set_index":3,"bodyweight":false,"timed":false,"uses_minutes":false,"exercises":{"name":"Fly"}},
          {"weight_kg":100,"reps":5,"set_index":0,"bodyweight":false,"timed":false,"uses_minutes":false,"exercises":{"name":"Bench"}},
          {"weight_kg":32.5,"reps":10,"set_index":4,"bodyweight":false,"timed":false,"uses_minutes":false,"exercises":{"name":"Fly"}},
          {"weight_kg":110,"reps":3,"set_index":1,"bodyweight":false,"timed":false,"uses_minutes":false,"exercises":{"name":"Bench"}},
          {"weight_kg":105,"reps":4,"set_index":2,"bodyweight":false,"timed":false,"uses_minutes":false,"exercises":{"name":"Bench"}}
        ]}]
        """
        let rows = try decoder.decode([RemoteSession].self, from: Data(payload.utf8))
        let session = try XCTUnwrap(rows.first).localSession(userID: "u1")

        XCTAssertEqual(session.exercises.map(\.name), ["Bench", "Fly"])
        XCTAssertEqual(session.exercises[0].sets.map(\.reps), [5, 3, 4])
        XCTAssertEqual(session.exercises[1].sets.map(\.weight), [30, 32.5])
    }

    /// A 20-minute bike ride is stored as 1200 canonical seconds. Without the
    /// flags it came back as 1200 *reps* of an untimed exercise.
    func testTimedMinutesExerciseSurvivesTheRoundTrip() throws {
        let payload = """
        [{"id":"s1","created_at":"2026-08-07T10:00:00Z","muscle_group":"cardio","split_type":"PPL","session_sets":[
          {"weight_kg":null,"reps":1200,"set_index":0,"bodyweight":false,"timed":true,"uses_minutes":true,
           "exercises":{"name":"Stationary Bike"}}
        ]}]
        """
        let rows = try decoder.decode([RemoteSession].self, from: Data(payload.utf8))
        let exercise = try XCTUnwrap(try XCTUnwrap(rows.first).localSession(userID: "u1").exercises.first)

        XCTAssertTrue(exercise.timed)
        XCTAssertTrue(exercise.usesMinutes)
        XCTAssertEqual(exercise.sets[0].reps, 1200)
        XCTAssertNil(exercise.sets[0].weight)
    }

    /// `session_sets.reps` was `integer` until the half-rep migration, which
    /// meant a 7.5 came back from PostgREST as a 400 the app showed only as
    /// "Backup failed". Both directions have to carry the fraction.
    func testHalfRepsCrossTheWireInBothDirections() throws {
        let body = RemoteSetInsert(
            sessionID: "s1", exerciseID: "e1", weightKg: 100, reps: 7.5,
            setIndex: 0, bodyweight: false, timed: false, usesMinutes: false, setType: nil
        )
        XCTAssertEqual(try json(body)["reps"] as? Double, 7.5, "not truncated to 7 on the way out")

        let payload = """
        [{"id":"s1","created_at":"2026-08-07T10:00:00Z","muscle_group":"back","split_type":"PPL","session_sets":[
          {"weight_kg":100,"reps":7.5,"set_index":0,"bodyweight":false,"timed":false,"uses_minutes":false,
           "exercises":{"name":"Row"}}
        ]}]
        """
        let rows = try decoder.decode([RemoteSession].self, from: Data(payload.utf8))
        let session = try XCTUnwrap(rows.first).localSession(userID: "u1")
        XCTAssertEqual(session.exercises[0].sets[0].reps, 7.5)
    }

    /// The column is constrained to the enum's raw values, so a rename on the
    /// client that is not mirrored in the CHECK constraint is a 400.
    func testSetTypeCrossesTheWireAsItsRawValue() throws {
        let body = RemoteSetInsert(
            sessionID: "s1", exerciseID: "e1", weightKg: 60, reps: 10,
            setIndex: 0, bodyweight: false, timed: false, usesMinutes: false,
            setType: SetType.warmup.rawValue
        )
        XCTAssertEqual(try json(body)["set_type"] as? String, "warmup")

        let payload = """
        [{"id":"s1","created_at":"2026-08-07T10:00:00Z","muscle_group":"legs","split_type":"PPL","session_sets":[
          {"weight_kg":60,"reps":10,"set_index":0,"bodyweight":false,"timed":false,"uses_minutes":false,
           "set_type":"warmup","exercises":{"name":"Squat"}},
          {"weight_kg":100,"reps":5,"set_index":1,"bodyweight":false,"timed":false,"uses_minutes":false,
           "set_type":null,"exercises":{"name":"Squat"}}
        ]}]
        """
        let rows = try decoder.decode([RemoteSession].self, from: Data(payload.utf8))
        let sets = try XCTUnwrap(rows.first).localSession(userID: "u1").exercises[0].sets

        XCTAssertEqual(sets[0].type, .warmup)
        XCTAssertFalse(sets[0].isWorkingSet)
        XCTAssertNil(sets[1].type, "a null column is an ordinary set, not a decode failure")
        XCTAssertTrue(sets[1].isWorkingSet)
    }

    /// An ordinary set omits the key entirely rather than sending a null, which
    /// is what lets the column keep its default.
    func testAnOrdinarySetOmitsTheTypeKey() throws {
        let body = RemoteSetInsert(
            sessionID: "s1", exerciseID: "e1", weightKg: 100, reps: 5,
            setIndex: 0, bodyweight: false, timed: false, usesMinutes: false, setType: nil
        )
        XCTAssertFalse(try json(body).keys.contains("set_type"))
    }

    /// A loaded pull-up used to lose its bodyweight flag, because that was
    /// inferred from "every set has no weight".
    func testLoadedBodyweightExerciseKeepsItsFlag() throws {
        let payload = """
        [{"id":"s1","created_at":"2026-08-07T10:00:00Z","muscle_group":"back","split_type":"PPL","session_sets":[
          {"weight_kg":20,"reps":8,"set_index":0,"bodyweight":true,"timed":false,"uses_minutes":false,
           "exercises":{"name":"Pull Ups"}}
        ]}]
        """
        let rows = try decoder.decode([RemoteSession].self, from: Data(payload.utf8))
        let exercise = try XCTUnwrap(try XCTUnwrap(rows.first).localSession(userID: "u1").exercises.first)

        XCTAssertTrue(exercise.bodyweight)
        XCTAssertEqual(exercise.sets[0].weight, 20)
    }

    /// Rows written before the migration carry nulls for the new columns. They
    /// must keep decoding on the old inference rather than throwing or being
    /// reclassified.
    func testRowsWrittenBeforeTheMigrationStillDecode() throws {
        let payload = """
        [{"id":"s1","created_at":"2026-08-07T10:00:00Z","muscle_group":"back","split_type":"PPL","session_sets":[
          {"weight_kg":null,"reps":10,"exercises":{"name":"Push Ups"}},
          {"weight_kg":60,"reps":8,"exercises":{"name":"Row"}}
        ]}]
        """
        let rows = try decoder.decode([RemoteSession].self, from: Data(payload.utf8))
        let session = try XCTUnwrap(rows.first).localSession(userID: "u1")

        XCTAssertEqual(session.exercises.count, 2)
        XCTAssertFalse(session.isCardio)
        let pushUps = try XCTUnwrap(session.exercises.first { $0.name == "Push Ups" })
        XCTAssertTrue(pushUps.bodyweight, "no weight anywhere still reads as bodyweight")
        XCTAssertFalse(pushUps.timed)
        let row = try XCTUnwrap(session.exercises.first { $0.name == "Row" })
        XCTAssertFalse(row.bodyweight)
    }
}
