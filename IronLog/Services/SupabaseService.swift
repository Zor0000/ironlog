import Foundation

final class SupabaseService {
    private let projectURL = URL(string: "https://dvqevdydldxjqjrpkkjc.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR2cWV2ZHlkbGR4anFqcnBra2pjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI0NzE3NDQsImV4cCI6MjA4ODA0Nzc0NH0.HrLewQwabuPNeD-8BZu4Muxju_4IDcJ3FuNhfwWm3t0"
    private let sessionService = "IronLogSupabaseSession"
    private let sessionAccount = "current"
    private static let iso8601 = ISO8601DateFormatter()

    private var auth: AuthSession? {
        didSet { persistAuth() }
    }

    init() {
        if let data = KeychainStore.load(service: sessionService, account: sessionAccount) {
            auth = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
    }

    var currentUser: UserProfile? {
        auth.map { UserProfile(id: $0.user.id, email: $0.user.email, fullName: $0.user.userMetadata?.fullName) }
    }

    var isAuthenticated: Bool {
        auth?.accessToken.isEmpty == false
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        let body = ["email": email, "password": password]
        let session: AuthSession = try await authRequest(path: "/auth/v1/token?grant_type=password", body: body)
        auth = session
        guard let currentUser else { throw SupabaseError.emptyResponse }
        return currentUser
    }

    func signUp(email: String, password: String, name: String) async throws {
        struct SignUpBody: Encodable {
            var email: String
            var password: String
            var data: [String: String]
        }
        let _: EmptyResponse = try await authRequest(path: "/auth/v1/signup", body: SignUpBody(email: email, password: password, data: ["full_name": name]))
    }

    func signOut() {
        auth = nil
        KeychainStore.delete(service: sessionService, account: sessionAccount)
    }

    func pullSessions() async throws -> [WorkoutSession] {
        guard let user = currentUser else { return [] }
        let select = "*,session_sets(weight_kg,reps,set_index,bodyweight,timed,uses_minutes,set_type,exercises(name))"
        let rows: [RemoteSession] = try await restGet(
            path: "/rest/v1/sessions",
            query: [
                URLQueryItem(name: "select", value: select),
                URLQueryItem(name: "user_id", value: "eq.\(user.id)"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ]
        )
        return rows.map { $0.localSession(userID: user.id) }
    }

    func pullPRs() async throws -> [PersonalRecord] {
        guard let user = currentUser else { return [] }
        let rows: [RemotePR] = try await restGet(
            path: "/rest/v1/personal_records",
            query: [
                URLQueryItem(name: "select", value: "weight_kg,reps,achieved_at,exercises(name)"),
                URLQueryItem(name: "user_id", value: "eq.\(user.id)")
            ]
        )
        return rows.compactMap { row in
            guard let name = row.exercises?.name else { return nil }
            return PersonalRecord(exerciseName: name, weight: row.weightKg ?? 0, reps: row.reps ?? 0, achievedAt: row.achievedAt ?? Date())
        }
    }

    func pullRoutines() async throws -> [SavedRoutine] {
        guard let user = currentUser else { return [] }
        let rows: [RemoteRoutine] = try await restGet(
            path: "/rest/v1/routines",
            query: [
                URLQueryItem(name: "select", value: "id,name,exercises,created_at"),
                URLQueryItem(name: "user_id", value: "eq.\(user.id)"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ]
        )
        return rows.compactMap { $0.localRoutine() }
    }

    /// Upserts on the routine's own id, so the row and the local record are the
    /// same object on every device — no server-minted id to map back, and
    /// re-saving a routine updates in place instead of accumulating copies.
    func backup(routine: SavedRoutine) async throws {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        let body = RemoteRoutineInsert(
            id: routine.id.uuidString,
            userID: user.id,
            name: routine.name,
            exercises: routine.exercises,
            createdAt: Self.iso8601.string(from: routine.createdAt),
            updatedAt: Self.iso8601.string(from: Date())
        )
        let _: [EmptyResponse] = try await restPost(
            path: "/rest/v1/routines",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: [body],
            prefer: "resolution=merge-duplicates,return=minimal",
            emptyValue: []
        )
    }

    func deleteCloudRoutine(_ id: UUID) async throws {
        try await restDelete(
            path: "/rest/v1/routines",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]
        )
    }

    func backup(session local: WorkoutSession, records: [PersonalRecord]) async throws -> String {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        if let cloudID = local.cloudID { return cloudID }

        let remoteSession = try await insertSession(local, userID: user.id)
        do {
            let exerciseIDs = try await ensureExercises(local.exercises.map(\.name))
            // `setIndex` is the position in this flat list, so it records both
            // exercise order and set order in one column — a pull sorts by it and
            // groups by first appearance to rebuild the session as it was logged.
            var setIndex = 0
            let rows = local.exercises.flatMap { exercise in
                exercise.sets.map { set -> RemoteSetInsert in
                    defer { setIndex += 1 }
                    return RemoteSetInsert(
                        sessionID: remoteSession.id,
                        exerciseID: exerciseIDs[exercise.name] ?? "",
                        // set.weight is already nil for timed/unloaded sets — see
                        // AppState.loggedSet, the one place that decision is made.
                        weightKg: set.weight,
                        reps: set.reps,
                        setIndex: setIndex,
                        bodyweight: exercise.bodyweight,
                        timed: exercise.timed,
                        usesMinutes: exercise.usesMinutes,
                        setType: encodeSetMetadata(type: set.type, remark: set.remark)
                    )
                }
            }.filter { !$0.exerciseID.isEmpty }
            if !rows.isEmpty {
                let _: [EmptyResponse] = try await restPost(path: "/rest/v1/session_sets", query: [], body: rows, prefer: "return=minimal", emptyValue: [])
            }
            try await backup(records: records, exerciseIDs: exerciseIDs, userID: user.id)
            return remoteSession.id
        } catch {
            try? await deleteCloudSession(remoteSession.id)
            throw error
        }
    }

    func deleteCloudSession(_ cloudID: String) async throws {
        try await restDelete(path: "/rest/v1/session_sets", query: [URLQueryItem(name: "session_id", value: "eq.\(cloudID)")])
        try await restDelete(path: "/rest/v1/sessions", query: [URLQueryItem(name: "id", value: "eq.\(cloudID)")])
    }

    /// Deletes every workout row the user owns while keeping the Auth identity.
    /// `session_sets` has no user_id column, so those go first via the
    /// session ids; RLS scopes everything to the signed-in user anyway.
    func deleteWorkoutData() async throws {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        let userFilter = URLQueryItem(name: "user_id", value: "eq.\(user.id)")
        let sessions: [RemoteSessionInsertResult] = try await restGet(
            path: "/rest/v1/sessions",
            query: [URLQueryItem(name: "select", value: "id"), userFilter]
        )
        if !sessions.isEmpty {
            let ids = sessions.map(\.id).joined(separator: ",")
            try await restDelete(path: "/rest/v1/session_sets", query: [URLQueryItem(name: "session_id", value: "in.(\(ids))")])
        }
        try await restDelete(path: "/rest/v1/sessions", query: [userFilter])
        try await restDelete(path: "/rest/v1/personal_records", query: [userFilter])
        try await restDelete(path: "/rest/v1/routines", query: [userFilter])
    }

    /// The service-role key stays inside this authenticated Edge Function. The
    /// app sends only its user JWT and never receives administrative credentials.
    func deleteAccount() async throws {
        guard isAuthenticated else { throw SupabaseError.notAuthenticated }
        var request = URLRequest(url: apiURL("/functions/v1/delete-account"))
        request.httpMethod = "POST"
        addRestHeaders(to: &request)
        request.httpBody = Data("{}".utf8)
        let _: [EmptyResponse] = try await decodeWithAuthRetry(request, emptyValue: [])
        auth = nil
        KeychainStore.delete(service: sessionService, account: sessionAccount)
    }

    private func insertSession(_ session: WorkoutSession, userID: String) async throws -> RemoteSessionInsertResult {
        let body = RemoteSessionInsert(
            userID: userID,
            muscleGroup: session.muscle,
            splitType: session.split,
            note: session.note,
            activityType: session.activity?.kind.rawValue,
            distanceM: session.activity?.distance,
            durationS: session.activity?.duration,
            route: session.activity?.route,
            elevationGainM: session.activity?.elevationGain,
            terrain: session.activity?.terrain?.rawValue,
            calories: session.activity?.calories
        )
        let rows: [RemoteSessionInsertResult] = try await restPost(path: "/rest/v1/sessions", query: [], body: body, prefer: "return=representation")
        guard let row = rows.first else { throw SupabaseError.emptyResponse }
        return row
    }

    private func ensureExercises(_ names: [String]) async throws -> [String: String] {
        var result: [String: String] = [:]
        for name in Set(names) {
            let rows: [RemoteExercise] = try await restPost(
                path: "/rest/v1/exercises",
                query: [URLQueryItem(name: "on_conflict", value: "name")],
                body: RemoteExerciseInsert(name: name),
                prefer: "resolution=merge-duplicates,return=representation"
            )
            if let row = rows.first {
                result[name] = row.id
            }
        }
        return result
    }

    private func backup(records: [PersonalRecord], exerciseIDs: [String: String], userID: String) async throws {
        for record in records {
            guard let exerciseID = exerciseIDs[record.exerciseName] else { continue }
            let body = RemotePRInsert(
                userID: userID,
                exerciseID: exerciseID,
                weightKg: record.weight,
                reps: record.reps,
                achievedAt: Self.iso8601.string(from: record.achievedAt)
            )
            let _: [EmptyResponse] = try await restPost(
                path: "/rest/v1/personal_records",
                query: [URLQueryItem(name: "on_conflict", value: "user_id,exercise_id")],
                body: body,
                prefer: "resolution=merge-duplicates,return=minimal",
                emptyValue: []
            )
        }
    }

    private func persistAuth() {
        guard let auth, let data = try? JSONEncoder().encode(auth) else { return }
        KeychainStore.save(data, service: sessionService, account: sessionAccount)
    }

    private func authRequest<Response: Decodable, Body: Encodable>(path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: apiURL(path))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(body)
        return try await decode(request)
    }

    private func restGet<Response: Decodable>(path: String, query: [URLQueryItem]) async throws -> Response {
        var components = URLComponents(url: apiURL(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        addRestHeaders(to: &request)
        return try await decodeWithAuthRetry(request)
    }

    private func restPost<Response: Decodable, Body: Encodable>(path: String, query: [URLQueryItem], body: Body, prefer: String, emptyValue: Response? = nil) async throws -> Response {
        var components = URLComponents(url: apiURL(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        addRestHeaders(to: &request)
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        request.httpBody = try encode(body)
        return try await decodeWithAuthRetry(request, emptyValue: emptyValue)
    }

    private func restDelete(path: String, query: [URLQueryItem]) async throws {
        var components = URLComponents(url: apiURL(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        addRestHeaders(to: &request)
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let _: [EmptyResponse] = try await decodeWithAuthRetry(request, emptyValue: [])
    }

    private func addRestHeaders(to request: inout URLRequest) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth?.accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func apiURL(_ path: String) -> URL {
        URL(string: projectURL.absoluteString + path)!
    }

    /// The wire coders, exposed so tests exercise the very same configuration
    /// the requests use — a test that built its own would still pass after the
    /// service's strategy changed underneath it.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        try Self.makeEncoder().encode(body)
    }

    private func decode<Response: Decodable>(_ request: URLRequest, emptyValue: Response? = nil) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            if http.statusCode == 401 { throw SupabaseError.unauthorized(message) }
            throw SupabaseError.requestFailed(message)
        }
        if data.isEmpty, let emptyValue { return emptyValue }
        return try Self.makeDecoder().decode(Response.self, from: data)
    }

    private func decodeWithAuthRetry<Response: Decodable>(_ request: URLRequest, emptyValue: Response? = nil) async throws -> Response {
        do {
            return try await decode(request, emptyValue: emptyValue)
        } catch SupabaseError.unauthorized {
            guard try await refreshSession() else { throw SupabaseError.notAuthenticated }
            var retry = request
            addRestHeaders(to: &retry)
            return try await decode(retry, emptyValue: emptyValue)
        }
    }

    private func refreshSession() async throws -> Bool {
        guard let refreshToken = auth?.refreshToken, !refreshToken.isEmpty else { return false }
        let session: AuthSession = try await authRequest(
            path: "/auth/v1/token?grant_type=refresh_token",
            body: ["refresh_token": refreshToken]
        )
        auth = session
        return true
    }
}

enum SupabaseError: LocalizedError {
    case notAuthenticated, invalidResponse, emptyResponse, unauthorized(String), requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Sign in to sync with Supabase."
        case .invalidResponse: "Supabase returned an invalid response."
        case .emptyResponse: "Supabase returned no data."
        case .unauthorized(let message): message
        case .requestFailed(let message): message
        }
    }
}

struct EmptyResponse: Codable {}

struct AuthSession: Codable {
    var accessToken: String
    var refreshToken: String?
    var user: AuthUser
}

struct AuthUser: Codable {
    var id: String
    var email: String
    var userMetadata: UserMetadata?
}

/// Only the field IronLog reads out of Supabase's `user_metadata`. Decoding a
/// dedicated struct (rather than `[String: String]`) keeps sign-in resilient
/// when Supabase includes non-string values such as `email_verified` in the
/// metadata — a raw `[String: String]` decode would throw on those and surface
/// as a spurious sign-in failure.
struct UserMetadata: Codable {
    var fullName: String?
}

struct RemoteExercise: Codable {
    var id: String
    var name: String
}

/// A routine round-trips as a document — the exercise list is stored in one
/// `jsonb` column because it is only ever read and written whole. Nothing
/// queries inside it, so a join table would add a second table, an ordering
/// column and an N+1 insert for no gain.
struct RemoteRoutine: Codable {
    var id: String
    var name: String
    var exercises: [ExerciseTemplate]
    var createdAt: Date?

    func localRoutine() -> SavedRoutine? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return SavedRoutine(id: uuid, name: name, createdAt: createdAt ?? Date(), exercises: exercises)
    }
}

struct RemoteRoutineInsert: Encodable {
    var id: String
    var userID: String
    var name: String
    var exercises: [ExerciseTemplate]
    var createdAt: String
    var updatedAt: String
}

struct RemoteExerciseInsert: Encodable {
    var name: String
}

struct RemoteSessionInsert: Encodable {
    var userID: String
    var muscleGroup: String?
    var splitType: String?
    var note: String?
    /// Nil for a strength session; a `CardioKind` raw value for a logged one.
    var activityType: String?
    var distanceM: Double?
    var durationS: Int?
    var route: [RoutePoint]?
    /// Metres of ascent, or nil for a strength session / unknown elevation.
    var elevationGainM: Int?
    /// `CardioTerrain.rawValue`, or nil when the user did not tag one.
    var terrain: String?
    /// Kilocalories, estimated or overridden. Nil without a body weight.
    var calories: Int?
}

struct RemoteSessionInsertResult: Codable {
    var id: String
}

struct RemoteSetInsert: Encodable {
    var sessionID: String
    var exerciseID: String
    var weightKg: Double?
    /// Fractional — the column is `numeric`, not `integer`, so a 7.5 survives.
    var reps: Double
    var setIndex: Int
    /// Exercise-level facts, denormalised onto the set row. Without them a pull
    /// cannot tell a 20-minute bike ride from 1200 reps, nor a loaded pull-up
    /// from a weighted press.
    var bodyweight: Bool
    var timed: Bool
    var usesMinutes: Bool
    /// Backward-compatible set metadata. Old rows contain `SetType.rawValue`;
    /// rows with a custom remark use the versioned representation below.
    var setType: String?
}

private let setMetadataPrefix = "ironlog:v1:"

struct StoredSetMetadata: Codable, Equatable {
    var type: SetType?
    var remark: String?
}

/// Keep custom remarks in the existing text column so current Supabase
/// projects do not need a schema migration. Plain set-type values written by
/// older app versions still decode unchanged.
func encodeSetMetadata(type: SetType?, remark: String?) -> String? {
    let cleanRemark = normalizedRemark(remark)
    guard cleanRemark != nil else { return type?.rawValue }
    let metadata = StoredSetMetadata(type: type, remark: cleanRemark)
    guard let data = try? JSONEncoder().encode(metadata) else { return type?.rawValue }
    return setMetadataPrefix + data.base64EncodedString()
}

func decodeSetMetadata(_ value: String?) -> StoredSetMetadata {
    guard let value else { return StoredSetMetadata(type: nil, remark: nil) }
    guard value.hasPrefix(setMetadataPrefix) else {
        return StoredSetMetadata(type: SetType(rawValue: value), remark: nil)
    }
    let encoded = String(value.dropFirst(setMetadataPrefix.count))
    guard let data = Data(base64Encoded: encoded),
          var metadata = try? JSONDecoder().decode(StoredSetMetadata.self, from: data) else {
        return StoredSetMetadata(type: nil, remark: nil)
    }
    metadata.remark = normalizedRemark(metadata.remark)
    return metadata
}

struct RemotePRInsert: Encodable {
    var userID: String
    var exerciseID: String
    var weightKg: Double
    var reps: Double
    var achievedAt: String
}

struct RemotePR: Codable {
    var weightKg: Double?
    var reps: Double?
    var achievedAt: Date?
    var exercises: RemoteExerciseName?
}

struct RemoteExerciseName: Codable {
    var name: String
}

struct RemoteSession: Codable {
    var id: String
    var userId: String?
    var createdAt: Date?
    var muscleGroup: String?
    var splitType: String?
    var note: String?
    var activityType: String?
    var distanceM: Double?
    var durationS: Int?
    var route: [RoutePoint]?
    var elevationGainM: Int?
    var terrain: String?
    var calories: Int?
    var sessionSets: [RemoteSessionSet]?

    func localSession(userID: String) -> WorkoutSession {
        WorkoutSession(
            cloudID: id,
            userID: userID,
            createdAt: createdAt ?? Date(),
            muscle: muscleGroup,
            split: splitType,
            note: note,
            exercises: loggedExercises,
            syncState: .synced,
            activity: activity
        )
    }

    /// A logged run or walk, or nil for an ordinary strength session.
    private var activity: CardioActivity? {
        guard let kind = activityType.flatMap(CardioKind.init(rawValue:)) else { return nil }
        return CardioActivity(
            kind: kind,
            duration: durationS ?? 0,
            distance: distanceM ?? 0,
            route: route ?? [],
            elevationGain: elevationGainM,
            terrain: terrain.flatMap(CardioTerrain.init(rawValue:)),
            calories: calories
        )
    }

    /// Rebuilds the session in the order it was logged. `set_index` is a single
    /// running counter across the whole session, so sorting by it and grouping
    /// by first appearance restores exercise order and set order together —
    /// grouping straight into a dictionary loses both.
    private var loggedExercises: [LoggedExercise] {
        let ordered = (sessionSets ?? []).sorted { ($0.setIndex ?? 0) < ($1.setIndex ?? 0) }
        var order: [String] = []
        var grouped: [String: [RemoteSessionSet]] = [:]
        for set in ordered {
            let name = set.exercises?.name ?? "Unknown"
            if grouped[name] == nil { order.append(name) }
            grouped[name, default: []].append(set)
        }
        return order.compactMap { name in
            let sets = grouped[name] ?? []
            let logged = sets.compactMap { set -> LoggedSet? in
                guard let reps = set.reps else { return nil }
                let metadata = decodeSetMetadata(set.setType)
                return LoggedSet(weight: set.weightKg, reps: reps,
                                 type: metadata.type, remark: metadata.remark)
            }
            guard !logged.isEmpty else { return nil }
            return LoggedExercise(
                name: name,
                // Rows written before these columns existed carry nil, so fall
                // back to the old "no weight anywhere means bodyweight" guess
                // rather than silently reclassifying old history.
                bodyweight: sets.first?.bodyweight ?? sets.allSatisfy { ($0.weightKg ?? 0) == 0 },
                timed: sets.first?.timed ?? false,
                minutes: sets.first?.usesMinutes,
                sets: logged
            )
        }
    }
}

struct RemoteSessionSet: Codable {
    var weightKg: Double?
    var reps: Double?
    var setIndex: Int?
    var bodyweight: Bool?
    var timed: Bool?
    var usesMinutes: Bool?
    var setType: String?
    var exercises: RemoteExerciseName?
}
