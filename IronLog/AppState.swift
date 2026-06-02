import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var library = ExerciseLibrary.bundled
    @Published var user: UserProfile?
    @Published var selectedTab: WorkoutTab = .workouts
    @Published var authMessage: String?
    @Published var toast: String?
    @Published var isBusy = false

    @Published var selectedSplit: String?
    @Published var selectedDay: String?
    @Published var selectedMuscle: String?
    @Published var workoutStep: WorkoutStep = .split
    @Published var todayExercises: [ActiveExercise] = []
    @Published var showAddExerciseForm = false
    @Published var addExerciseWeighted = false

    @Published var sessions: [WorkoutSession] = []
    @Published var personalRecords: [String: PersonalRecord] = [:]
    @Published var waterByDay: [String: Int] = [:]
    @Published var syncMessage: String = "Local first"
    @Published var showingAuth = false

    @Published var timerSecs = 90
    @Published var timerMax = 90
    @Published var timerRunning = false

    private let localStore = LocalStore()
    private let supabase = SupabaseService()
    private var timerTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private let localUser = UserProfile(id: "local", email: "local@ironlog", fullName: "Local Athlete", isLocal: true)

    var waterToday: Int {
        waterByDay[Date().dayKey] ?? 0
    }

    var stats: (sets: Int, volume: Double, streak: Int) {
        var sets = 0
        var volume = 0.0
        sessions.forEach { session in
            session.exercises.forEach { exercise in
                sets += exercise.sets.count
                exercise.sets.forEach { set in
                    if let weight = set.weight, weight > 0 {
                        volume += weight * Double(set.reps)
                    }
                }
            }
        }
        let days = Set(sessions.map { $0.createdAt.dayKey })
        var streak = 0
        var cursor = Date()
        while days.contains(cursor.dayKey) {
            streak += 1
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return (sets, volume, streak)
    }

    func boot() async {
        let snapshot = await localStore.load()
        sessions = snapshot.sessions.sorted { $0.createdAt > $1.createdAt }
        personalRecords = Dictionary(uniqueKeysWithValues: snapshot.personalRecords.map { ($0.exerciseName, $0) })
        waterByDay = snapshot.waterByDay
        if let draft = snapshot.draft {
            todayExercises = draft.exercises
            selectedMuscle = draft.muscle
            selectedSplit = draft.split
        }
        user = supabase.currentUser
        if user != nil {
            await refreshFromCloud()
            await syncPending()
        } else {
            user = localUser
            syncMessage = "Saved on this iPhone"
        }
    }

    func signIn(email: String, password: String) async {
        await runBusy {
            user = try await supabase.signIn(email: email, password: password)
            showingAuth = false
            authMessage = nil
            await refreshFromCloud()
            await syncPending()
        }
    }

    func signUp(email: String, password: String, name: String) async -> Bool {
        await runBusy {
            try await supabase.signUp(email: email, password: password, name: name)
            authMessage = "Account created. Check your email to confirm, then sign in."
        }
    }

    func signOut() {
        supabase.signOut()
        user = localUser
        showingAuth = false
        authMessage = nil
        syncMessage = "Saved on this iPhone"
        selectedTab = .workouts
    }

    func continueLocally() {
        user = localUser
        showingAuth = false
        authMessage = nil
        syncMessage = "Saved on this iPhone"
    }

    func showAuth() {
        showingAuth = true
        authMessage = nil
    }

    func selectSplit(_ split: String) {
        selectedSplit = split
        selectedDay = nil
        selectedMuscle = nil
        workoutStep = library.splitDays[split] == nil ? .muscle : .day
        persistDraft()
    }

    func selectDay(_ day: String) {
        selectedDay = day
        selectedMuscle = nil
        workoutStep = .muscle
    }

    func selectMuscle(_ muscle: String) {
        selectedMuscle = muscle
        workoutStep = .workout
    }

    func startWorkout() {
        let templates = library.exercises(split: selectedSplit, muscle: selectedMuscle)
        todayExercises = templates.map { template in
            ActiveExercise(
                name: template.name,
                bodyweight: template.bodyweight,
                timed: template.timed,
                sets: (0..<template.sets).map { _ in WorkoutSet() }
            )
        }
        selectedTab = .log
        persistDraft()
        showToast("Workout started")
    }

    func startFreeWorkout() {
        selectedSplit = "Free Workout"
        selectedMuscle = nil
        todayExercises = []
        showAddExerciseForm = true
        selectedTab = .log
        showToast("Free workout started")
    }

    func updateSet(exerciseID: ActiveExercise.ID, setID: WorkoutSet.ID, weight: String? = nil, reps: String? = nil) {
        guard let ei = todayExercises.firstIndex(where: { $0.id == exerciseID }),
              let si = todayExercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        if let weight {
            todayExercises[ei].sets[si].weight = weight.filter { "0123456789.".contains($0) }
        }
        if let reps {
            todayExercises[ei].sets[si].reps = reps.filter(\.isNumber)
        }
        persistDraft()
    }

    func toggleDone(exerciseID: ActiveExercise.ID, setID: WorkoutSet.ID) {
        guard let ei = todayExercises.firstIndex(where: { $0.id == exerciseID }),
              let si = todayExercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        todayExercises[ei].sets[si].done.toggle()
        let exercise = todayExercises[ei]
        let set = todayExercises[ei].sets[si]
        if set.done {
            startTimer()
            if isNewPR(exercise: exercise, set: set) {
                showToast("New PR on \(exercise.name)")
            }
        }
        persistDraft()
    }

    func addSet(to exerciseID: ActiveExercise.ID) {
        guard let index = todayExercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        todayExercises[index].sets.append(WorkoutSet())
        persistDraft()
    }

    func toggleExercise(_ exerciseID: ActiveExercise.ID) {
        guard let index = todayExercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        todayExercises[index].expanded.toggle()
        persistDraft()
    }

    func addExercise(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showToast("Enter an exercise name first")
            return
        }
        todayExercises.append(ActiveExercise(
            name: trimmed,
            bodyweight: !addExerciseWeighted,
            timed: false,
            custom: true,
            sets: [WorkoutSet()]
        ))
        showAddExerciseForm = false
        addExerciseWeighted = false
        persistDraft()
    }

    func finishWorkout(note: String) async {
        let logged = todayExercises.compactMap { exercise -> LoggedExercise? in
            let sets = exercise.sets.compactMap { set -> LoggedSet? in
                guard set.done, let reps = Int(set.reps), reps > 0 else { return nil }
                let weight = (exercise.bodyweight || exercise.timed) ? nil : Double(set.weight)
                return LoggedSet(weight: weight, reps: reps)
            }
            guard !sets.isEmpty else { return nil }
            return LoggedExercise(name: exercise.name, bodyweight: exercise.bodyweight, timed: exercise.timed, sets: sets)
        }
        guard !logged.isEmpty else {
            showToast("Log at least one set first")
            return
        }

        var session = WorkoutSession(
            userID: user?.id,
            createdAt: Date(),
            muscle: selectedMuscle,
            split: selectedSplit,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
            exercises: logged,
            syncState: supabase.isAuthenticated ? .pending : .localOnly
        )
        applyRecords(from: session)
        sessions.insert(session, at: 0)
        todayExercises = []
        showAddExerciseForm = false
        persistAll(clearDraft: true)
        selectedTab = .history
        showToast("Workout saved")

        if supabase.isAuthenticated {
            do {
                let cloudID = try await supabase.backup(session: session, records: Array(personalRecords.values))
                session.cloudID = cloudID
                session.userID = supabase.currentUser?.id ?? session.userID
                session.syncState = .synced
                if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[index] = session
                    persistAll()
                }
                syncMessage = "Backed up to Supabase"
            } catch {
                markFailed(session.id, error: error)
            }
        }
    }

    func deleteSession(_ id: WorkoutSession.ID) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        sessions.removeAll { $0.id == id }
        recalculateRecords()
        persistAll()
        if let cloudID = session.cloudID {
            try? await supabase.deleteCloudSession(cloudID)
        }
    }

    func setWater(index: Int) {
        let next = index < waterToday ? index : index + 1
        waterByDay[Date().dayKey] = next
        persistAll()
    }

    func setTimerPreset(_ seconds: Int) {
        timerMax = seconds
        resetTimer()
    }

    func startTimer() {
        if timerRunning { return }
        timerRunning = true
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    guard let self, self.timerRunning else { return }
                    if self.timerSecs <= 0 {
                        self.resetTimer()
                        self.showToast("Rest over. Next set.")
                    } else {
                        self.timerSecs -= 1
                    }
                }
            }
        }
    }

    func toggleTimer() {
        timerRunning ? pauseTimer() : startTimer()
    }

    func pauseTimer() {
        timerTask?.cancel()
        timerRunning = false
    }

    func resetTimer() {
        timerTask?.cancel()
        timerRunning = false
        timerSecs = timerMax
    }

    func syncPending() async {
        guard supabase.isAuthenticated else { return }
        let syncedUserID = supabase.currentUser?.id
        for session in sessions where session.syncState != .synced {
            do {
                let cloudID = try await supabase.backup(session: session, records: Array(personalRecords.values))
                if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[index].cloudID = cloudID
                    sessions[index].userID = syncedUserID ?? sessions[index].userID
                    sessions[index].syncState = .synced
                }
            } catch {
                markFailed(session.id, error: error)
            }
        }
        persistAll()
    }

    private func refreshFromCloud() async {
        do {
            let cloudSessions = try await supabase.pullSessions()
            let cloudRecords = try await supabase.pullPRs()
            mergeCloudSessions(cloudSessions)
            for record in cloudRecords {
                personalRecords[record.exerciseName] = better(record, than: personalRecords[record.exerciseName])
            }
            persistAll()
            syncMessage = "Synced with Supabase"
        } catch {
            syncMessage = "Local first. Cloud unavailable."
        }
    }

    @discardableResult
    private func runBusy(_ work: () async throws -> Void) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            return true
        } catch {
            authMessage = error.localizedDescription
            return false
        }
    }

    private func mergeCloudSessions(_ cloudSessions: [WorkoutSession]) {
        for cloud in cloudSessions {
            if sessions.contains(where: { $0.cloudID == cloud.cloudID }) { continue }
            sessions.append(cloud)
        }
        sessions.sort { $0.createdAt > $1.createdAt }
    }

    private func applyRecords(from session: WorkoutSession) {
        for exercise in session.exercises {
            for set in exercise.sets {
                let weight = set.weight ?? 0
                let record = PersonalRecord(exerciseName: exercise.name, weight: weight, reps: set.reps, achievedAt: session.createdAt)
                personalRecords[exercise.name] = better(record, than: personalRecords[exercise.name])
            }
        }
    }

    private func recalculateRecords() {
        personalRecords = [:]
        sessions.forEach(applyRecords)
    }

    private func better(_ candidate: PersonalRecord, than current: PersonalRecord?) -> PersonalRecord {
        guard let current else { return candidate }
        if candidate.weight > current.weight { return candidate }
        if candidate.weight == current.weight && candidate.reps > current.reps { return candidate }
        return current
    }

    private func isNewPR(exercise: ActiveExercise, set: WorkoutSet) -> Bool {
        guard let reps = Int(set.reps) else { return false }
        let weight = (exercise.bodyweight || exercise.timed) ? 0 : (Double(set.weight) ?? 0)
        guard let pr = personalRecords[exercise.name] else { return reps > 0 }
        return weight > pr.weight || (weight == pr.weight && reps > pr.reps)
    }

    private func markFailed(_ id: WorkoutSession.ID, error: Error) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].syncState = .failed
        }
        syncMessage = "Saved locally. Backup failed."
        persistAll()
    }

    private func persistDraft() {
        let draft = todayExercises.isEmpty ? nil : WorkoutDraft(exercises: todayExercises, muscle: selectedMuscle, split: selectedSplit)
        persistAll(draft: draft)
    }

    private func persistAll(clearDraft: Bool = false, draft: WorkoutDraft? = nil) {
        let currentDraft = todayExercises.isEmpty ? nil : WorkoutDraft(exercises: todayExercises, muscle: selectedMuscle, split: selectedSplit)
        let snapshot = AppSnapshot(
            sessions: sessions,
            personalRecords: Array(personalRecords.values),
            waterByDay: waterByDay,
            draft: clearDraft ? nil : (draft ?? currentDraft)
        )
        Task {
            await localStore.save(snapshot)
        }
    }

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                self?.toast = nil
            }
        }
    }
}
