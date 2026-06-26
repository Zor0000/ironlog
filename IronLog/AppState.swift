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
    @Published var workoutNote = ""

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

    var hasActiveWorkout: Bool {
        !todayExercises.isEmpty || showAddExerciseForm || !workoutNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedWorkoutMuscleIDs: [String] {
        library.muscleIDs(split: selectedSplit, day: selectedDay, selectedMuscle: selectedMuscle)
    }

    var selectedWorkoutMuscleLabel: String {
        let labels = selectedWorkoutMuscleIDs.compactMap { library.muscle($0)?.label }
        if labels.isEmpty { return selectedSplit ?? "Workout" }
        if labels.count == 1 { return labels[0] }
        return labels.joined(separator: " + ")
    }

    var activeExerciseTemplates: [ExerciseTemplate] {
        library.exercises(split: selectedSplit, day: selectedDay, selectedMuscle: selectedMuscle)
    }

    var completedSetCount: Int {
        todayExercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.done).count
        }
    }

    var validCompletedSetCount: Int {
        todayExercises.reduce(0) { total, exercise in
            total + exercise.sets.filter { loggedSet(for: exercise, set: $0) != nil }.count
        }
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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITest_ResetStore") {
            await localStore.clear()
            supabase.signOut()
        }
        #endif

        let snapshot = await localStore.load()
        sessions = snapshot.sessions.sorted { $0.createdAt > $1.createdAt }
        personalRecords = Dictionary(uniqueKeysWithValues: snapshot.personalRecords.map { ($0.exerciseName, $0) })
        waterByDay = snapshot.waterByDay
        if let draft = snapshot.draft {
            todayExercises = draft.exercises
            selectedMuscle = draft.muscle
            selectedSplit = draft.split
            selectedDay = draft.day
            workoutStep = draft.step ?? (draft.exercises.isEmpty ? .split : .workout)
            showAddExerciseForm = draft.showAddExerciseForm ?? false
            addExerciseWeighted = draft.addExerciseWeighted ?? false
            workoutNote = draft.note ?? ""
            if !draft.exercises.isEmpty || draft.showAddExerciseForm == true || !(draft.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedTab = .log
            }
        }
        user = supabase.currentUser
        if user != nil {
            await refreshFromCloud()
            await syncPending()
        } else {
            user = localUser
            syncMessage = "Saved on this iPhone"
        }

        // Re-show the Lock Screen activity for a workout resumed from disk.
        if hasActiveWorkout {
            updateLiveActivity(clearedDraft: false)
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
    }

    func selectDay(_ day: String) {
        selectedDay = day
        selectedMuscle = nil
        workoutStep = .workout
    }

    func selectMuscle(_ muscle: String) {
        selectedMuscle = muscle
        workoutStep = .workout
    }

    func startWorkout() {
        guard !hasActiveWorkout else {
            selectedTab = .log
            showToast("Finish or discard the current workout first")
            return
        }
        let templates = activeExerciseTemplates
        guard !templates.isEmpty else {
            showToast("No exercises found for this workout")
            return
        }
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
        showToast("\(selectedWorkoutMuscleLabel) workout started")
    }

    func startFreeWorkout() {
        guard !hasActiveWorkout else {
            selectedTab = .log
            showToast("Finish or discard the current workout first")
            return
        }
        selectedSplit = "Free Workout"
        selectedDay = nil
        selectedMuscle = nil
        workoutStep = .split
        todayExercises = []
        showAddExerciseForm = true
        selectedTab = .log
        persistDraft()
        showToast("Free workout started")
    }

    func continueWorkout() {
        selectedTab = .log
        showToast("Workout still in progress")
    }

    func discardWorkout() {
        resetActiveWorkout()
        persistAll(clearDraft: true)
        selectedTab = .workouts
        showToast("Workout discarded")
    }

    func updateSet(exerciseID: ActiveExercise.ID, setID: WorkoutSet.ID, weight: String? = nil, reps: String? = nil) {
        guard let ei = todayExercises.firstIndex(where: { $0.id == exerciseID }),
              let si = todayExercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        if let weight {
            todayExercises[ei].sets[si].weight = sanitizeDecimal(weight)
        }
        if let reps {
            todayExercises[ei].sets[si].reps = reps.filter(\.isNumber)
        }
        persistDraft()
    }

    func toggleDone(exerciseID: ActiveExercise.ID, setID: WorkoutSet.ID) {
        guard let ei = todayExercises.firstIndex(where: { $0.id == exerciseID }),
              let si = todayExercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        let exercise = todayExercises[ei]
        let set = todayExercises[ei].sets[si]
        if set.done {
            todayExercises[ei].sets[si].done = false
            persistDraft()
            return
        }
        var candidate = set
        candidate.done = true
        guard loggedSet(for: exercise, set: candidate) != nil else {
            showToast(validationMessage(for: exercise))
            return
        }
        todayExercises[ei].sets[si].done = true
        restartTimer()
        if isNewPR(exercise: exercise, set: set) {
            showToast("New PR on \(exercise.name)")
        }
        persistDraft()
    }

    func addSet(to exerciseID: ActiveExercise.ID) {
        guard let index = todayExercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        todayExercises[index].sets.append(WorkoutSet())
        persistDraft()
    }

    func removeSet(exerciseID: ActiveExercise.ID, setID: WorkoutSet.ID) {
        guard let ei = todayExercises.firstIndex(where: { $0.id == exerciseID }),
              let si = todayExercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        guard todayExercises[ei].sets.count > 1 else {
            showToast("Keep at least one set")
            return
        }
        todayExercises[ei].sets.remove(at: si)
        persistDraft()
    }

    func toggleExercise(_ exerciseID: ActiveExercise.ID) {
        guard let index = todayExercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        todayExercises[index].expanded.toggle()
        persistDraft()
    }

    func removeExercise(_ exerciseID: ActiveExercise.ID) {
        guard let exercise = todayExercises.first(where: { $0.id == exerciseID }) else { return }
        todayExercises.removeAll { $0.id == exerciseID }
        if todayExercises.isEmpty {
            showAddExerciseForm = true
        }
        persistDraft()
        showToast("\(exercise.name) removed")
    }

    func beginAddingExercise(weighted: Bool = false) {
        showAddExerciseForm = true
        addExerciseWeighted = weighted
        persistDraft()
    }

    func cancelAddingExercise() {
        showAddExerciseForm = false
        addExerciseWeighted = false
        persistDraft()
    }

    func setAddExerciseWeighted(_ weighted: Bool) {
        addExerciseWeighted = weighted
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

    func addExercise(template: ExerciseTemplate) {
        todayExercises.append(ActiveExercise(
            name: template.name,
            bodyweight: template.bodyweight,
            timed: template.timed,
            custom: false,
            sets: (0..<max(template.sets, 1)).map { _ in WorkoutSet() }
        ))
        showAddExerciseForm = false
        addExerciseWeighted = false
        persistDraft()
        showToast("\(template.name) added")
    }

    func updateWorkoutNote(_ note: String) {
        workoutNote = note
        persistDraft()
    }

    func finishWorkout(note: String) async {
        let logged = todayExercises.compactMap { exercise -> LoggedExercise? in
            let sets = exercise.sets.compactMap { set -> LoggedSet? in
                loggedSet(for: exercise, set: set)
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
        resetActiveWorkout()
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
        guard !timerRunning else { return }
        timerRunning = true
        runTimerLoop()
    }

    /// Restarts the rest timer from the full preset. Called when a set is
    /// completed so each set's rest period counts down fresh rather than
    /// resuming the previous (or paused) value.
    func restartTimer() {
        timerSecs = timerMax
        timerRunning = true
        runTimerLoop()
    }

    private func runTimerLoop() {
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

    func syncNow() async {
        guard supabase.isAuthenticated else {
            showAuth()
            return
        }
        syncMessage = "Syncing..."
        await refreshFromCloud()
        await syncPending()
        if syncMessage == "Syncing..." {
            syncMessage = "Synced with Supabase"
        }
        showToast(syncMessage)
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

    private func loggedSet(for exercise: ActiveExercise, set: WorkoutSet) -> LoggedSet? {
        guard set.done, let reps = Int(set.reps), reps > 0 else { return nil }
        if exercise.bodyweight || exercise.timed {
            return LoggedSet(weight: nil, reps: reps)
        }
        guard let weight = Double(set.weight), weight >= 0 else { return nil }
        return LoggedSet(weight: weight, reps: reps)
    }

    private func validationMessage(for exercise: ActiveExercise) -> String {
        if exercise.timed {
            return "Enter seconds before marking the set done"
        }
        if exercise.bodyweight {
            return "Enter reps before marking the set done"
        }
        return "Enter weight and reps before marking the set done"
    }

    private func markFailed(_ id: WorkoutSession.ID, error: Error) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].syncState = .failed
        }
        syncMessage = "Saved locally. Backup failed."
        persistAll()
    }

    private func persistDraft() {
        persistAll(draft: currentDraft)
    }

    private func persistAll(clearDraft: Bool = false, draft: WorkoutDraft? = nil) {
        let snapshot = AppSnapshot(
            sessions: sessions,
            personalRecords: Array(personalRecords.values),
            waterByDay: waterByDay,
            draft: clearDraft ? nil : (draft ?? currentDraft)
        )
        Task {
            await localStore.save(snapshot)
        }
        updateLiveActivity(clearedDraft: clearDraft)
    }

    /// Internal entry point for the Live Activity bridge, which lives in another
    /// file and therefore can't reach the private persistence helpers.
    func persistAfterReconcile() {
        persistDraft()
    }

    private var currentDraft: WorkoutDraft? {
        guard hasActiveWorkout else { return nil }
        return WorkoutDraft(
            exercises: todayExercises,
            muscle: selectedMuscle,
            split: selectedSplit,
            day: selectedDay,
            step: workoutStep,
            showAddExerciseForm: showAddExerciseForm,
            addExerciseWeighted: addExerciseWeighted,
            note: workoutNote
        )
    }

    private func resetActiveWorkout() {
        todayExercises = []
        showAddExerciseForm = false
        addExerciseWeighted = false
        workoutNote = ""
        selectedMuscle = nil
        selectedDay = nil
        selectedSplit = nil
        workoutStep = .split
        resetTimer()
    }

    private func sanitizeDecimal(_ value: String) -> String {
        var output = ""
        var didUseDecimal = false
        for character in value {
            if character.isNumber {
                output.append(character)
            } else if character == ".", !didUseDecimal {
                output.append(character)
                didUseDecimal = true
            }
        }
        return output
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
