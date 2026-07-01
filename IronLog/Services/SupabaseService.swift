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
        let _: SignUpResponse = try await authRequest(path: "/auth/v1/signup", body: SignUpBody(email: email, password: password, data: ["full_name": name]))
    }

    func signOut() {
        auth = nil
        KeychainStore.delete(service: sessionService, account: sessionAccount)
    }

    func pullSessions() async throws -> [WorkoutSession] {
        guard let user = currentUser else { return [] }
        let select = "*,session_sets(weight_kg,reps,exercises(name))"
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

    func backup(session local: WorkoutSession, records: [PersonalRecord]) async throws -> String {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        if let cloudID = local.cloudID { return cloudID }

        let remoteSession = try await insertSession(local, userID: user.id)
        do {
            let exerciseIDs = try await ensureExercises(local.exercises.map(\.name))
            let rows = local.exercises.flatMap { exercise in
                exercise.sets.map { set in
                    RemoteSetInsert(
                        sessionID: remoteSession.id,
                        exerciseID: exerciseIDs[exercise.name] ?? "",
                        weightKg: (exercise.bodyweight || exercise.timed) ? nil : set.weight,
                        reps: set.reps
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

    private func insertSession(_ session: WorkoutSession, userID: String) async throws -> RemoteSessionInsertResult {
        let body = RemoteSessionInsert(userID: userID, muscleGroup: session.muscle, splitType: session.split, note: session.note)
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

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(body)
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
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

struct SignUpResponse: Codable {}

struct RemoteExercise: Codable {
    var id: String
    var name: String
}

struct RemoteExerciseInsert: Encodable {
    var name: String
}

struct RemoteSessionInsert: Encodable {
    var userID: String
    var muscleGroup: String?
    var splitType: String?
    var note: String?
}

struct RemoteSessionInsertResult: Codable {
    var id: String
}

struct RemoteSetInsert: Encodable {
    var sessionID: String
    var exerciseID: String
    var weightKg: Double?
    var reps: Int
}

struct RemotePRInsert: Encodable {
    var userID: String
    var exerciseID: String
    var weightKg: Double
    var reps: Int
    var achievedAt: String
}

struct RemotePR: Codable {
    var weightKg: Double?
    var reps: Int?
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
    var sessionSets: [RemoteSessionSet]?

    func localSession(userID: String) -> WorkoutSession {
        let grouped = Dictionary(grouping: sessionSets ?? []) { $0.exercises?.name ?? "Unknown" }
        let exercises = grouped.map { name, sets in
            LoggedExercise(
                name: name,
                bodyweight: sets.allSatisfy { ($0.weightKg ?? 0) == 0 },
                timed: false,
                sets: sets.compactMap { set in
                    guard let reps = set.reps else { return nil }
                    return LoggedSet(weight: set.weightKg, reps: reps)
                }
            )
        }.filter { !$0.sets.isEmpty }
        return WorkoutSession(
            cloudID: id,
            userID: userID,
            createdAt: createdAt ?? Date(),
            muscle: muscleGroup,
            split: splitType,
            note: note,
            exercises: exercises,
            syncState: .synced
        )
    }
}

struct RemoteSessionSet: Codable {
    var weightKg: Double?
    var reps: Int?
    var exercises: RemoteExerciseName?
}
