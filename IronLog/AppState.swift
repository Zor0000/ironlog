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
    @Published var showingOnboarding = false
    @Published var unitPreference: WeightUnit = .kg

    @Published var timerSecs = 90
    @Published var timerMax = 90
    @Published var timerRunning = false

    private let localStore = LocalStore()
    private let supabase = SupabaseService()
    /// Internal (not private) so tests can swap in a spy.
    var notifier = RestTimerNotifier()
    private var hasOnboarded = false
    /// Wall-clock end of the running rest timer, so the countdown stays
    /// correct across backgrounding (the tick task is suspended while inactive).
    private var timerEndsAt: Date?
    private var timerTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    /// Serializes disk writes. `persistAll` can fire many times in quick
    /// succession (e.g. on every keystroke in a set field); chaining each save
    /// onto the previous one guarantees the most recent snapshot is the last
    /// one written, rather than racing independent tasks onto the actor.
    private var saveTask: Task<Void, Never>?
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

    /// The most recent saved session that contains `exerciseName` (exact match),
    /// returned as its `LoggedExercise`. Callers map by set index and fall back
    /// to the last set. `sessions` is kept newest-first, so the first hit wins.
    /// Returns nil when the exercise has no history.
    func lastPerformance(exerciseName: String) -> LoggedExercise? {
        for session in sessions {
            if let exercise = session.exercises.first(where: { $0.name == exerciseName }),
               !exercise.sets.isEmpty {
                return exercise
            }
        }
        return nil
    }

    func boot() async {
        var suppressOnboarding = false
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITest_ResetStore") {
            await localStore.clear()
            supabase.signOut()
            suppressOnboarding = true // existing UI tests expect a clean slate, not intro cards
        }
        #endif

        let snapshot = await localStore.load()
        sessions = snapshot.sessions.sorted { $0.createdAt > $1.createdAt }
        personalRecords = Dictionary(uniqueKeysWithValues: snapshot.personalRecords.map { ($0.exerciseName, $0) })
        waterByDay = snapshot.waterByDay
        unitPreference = snapshot.unitPreference ?? .kg
        currentWeightUnit = unitPreference
        timerMax = snapshot.timerPreset ?? 90
        timerSecs = timerMax
        hasOnboarded = snapshot.hasOnboarded ?? false
        showingOnboarding = !hasOnboarded && !suppressOnboarding
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

        // Re-show the Lock Screen activity for a workout resumed from disk. Fold
        // in any sets the user logged from the Lock Screen while the app was
        // terminated *first*: the engine's snapshot is newer than the on-disk
        // draft in that case, and rebuilding the activity from the draft would
        // otherwise discard those edits. The scene-phase reconcile can't cover
        // this on a cold launch because it races draft loading here.
        if hasActiveWorkout {
            reconcileFromLiveActivity()
            updateLiveActivity(clearedDraft: false)
        }

        #if DEBUG
        applyDemoSeedIfRequested()
        #endif
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

    /// App Store account deletion: remove the user's cloud rows, wipe local
    /// state, sign out and land on the auth/local choice screen. Returns false
    /// when the cloud delete fails — local data is left untouched in that case.
    @discardableResult
    func deleteAccount() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        if supabase.isAuthenticated {
            do {
                try await supabase.deleteAccount()
            } catch {
                showToast("Couldn't delete cloud data. Check your connection and try again.")
                return false
            }
        }
        sessions = []
        personalRecords = [:]
        waterByDay = [:]
        resetActiveWorkout()
        hasOnboarded = false
        updateLiveActivity(clearedDraft: true)
        // Chain the wipe onto the save queue so an in-flight persistAll can't
        // re-write the snapshot after it is cleared.
        let previous = saveTask
        saveTask = Task { [localStore] in
            await previous?.value
            await localStore.clear()
        }
        await saveTask?.value
        supabase.signOut()
        user = nil
        showingAuth = true
        authMessage = nil
        syncMessage = "Local first"
        selectedTab = .workouts
        return true
    }

    func finishOnboarding(createAccount: Bool) {
        hasOnboarded = true
        showingOnboarding = false
        createAccount ? showAuth() : continueLocally()
        persistAll()
    }

    /// Switch the display unit. Weight stays canonical KG in storage; only the
    /// strings the user is currently typing live in the display unit, so
    /// convert them in place — "60" kg must become "132.5" lb, not stay "60".
    func setUnitPreference(_ unit: WeightUnit) {
        guard unit != unitPreference else { return }
        let oldUnit = unitPreference
        unitPreference = unit
        currentWeightUnit = unit
        for ei in todayExercises.indices {
            for si in todayExercises[ei].sets.indices {
                guard let value = Double(todayExercises[ei].sets[si].weight), value > 0 else { continue }
                let kg = displayWeightToKg(value, in: oldUnit)
                todayExercises[ei].sets[si].weight = clean(displayWeight(kg, in: unit))
            }
        }
        // The Live Activity's unit label is fixed in its attributes; end it and
        // let persistAll's sync re-create it with the new label.
        LiveWorkoutEngine.shared.end()
        persistAll()
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
                sets: (0..<max(template.sets, 1)).map { _ in WorkoutSet() }
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
        // A set stays editable after it is marked done. If an edit drops it below
        // the validation bar (e.g. the weight is cleared), clear the done flag so
        // the checkmark, the "valid sets" count and the saved session never
        // disagree — otherwise a set could look logged yet vanish on save.
        if todayExercises[ei].sets[si].done,
           loggedSet(for: todayExercises[ei], set: todayExercises[ei].sets[si]) == nil {
            todayExercises[ei].sets[si].done = false
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

    /// Save an edited past session. Sets pass through the same `loggedSet`
    /// validation as a live workout, PRs are recomputed (an edit can raise or
    /// lower one), and the session re-enters the existing pending-sync queue.
    func updateSession(id: WorkoutSession.ID, exercises: [ActiveExercise], note: String) async {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let logged = exercises.compactMap { exercise -> LoggedExercise? in
            let sets = exercise.sets.compactMap { loggedSet(for: exercise, set: $0) }
            guard !sets.isEmpty else { return nil }
            return LoggedExercise(name: exercise.name, bodyweight: exercise.bodyweight, timed: exercise.timed, sets: sets)
        }
        guard !logged.isEmpty else {
            showToast("Keep at least one valid set")
            return
        }
        var session = sessions[index]
        let oldCloudID = session.cloudID
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        session.exercises = logged
        session.note = trimmedNote.isEmpty ? nil : trimmedNote
        session.cloudID = nil
        session.syncState = supabase.isAuthenticated ? .pending : .localOnly
        sessions[index] = session
        recalculateRecords()
        persistAll()
        showToast("Session updated")
        // Replace-in-cloud = delete the old row, let the pending queue re-insert.
        // ponytail: if the delete fails offline the stale copy can resurface on
        // the next pull (same ceiling as deleteSession); a tombstone queue fixes both.
        if let oldCloudID {
            try? await supabase.deleteCloudSession(oldCloudID)
        }
        await syncPending()
    }

    func setWater(index: Int) {
        let next = index < waterToday ? index : index + 1
        waterByDay[Date().dayKey] = next
        persistAll()
    }

    func setTimerPreset(_ seconds: Int) {
        timerMax = seconds
        resetTimer()
        persistAll()
    }

    func startTimer() {
        guard !timerRunning else { return }
        resumeTimer(until: Date().addingTimeInterval(TimeInterval(timerSecs)))
    }

    /// Restarts the rest timer from the full preset. Called when a set is
    /// completed so each set's rest period counts down fresh rather than
    /// resuming the previous (or paused) value.
    func restartTimer() {
        timerSecs = timerMax
        resumeTimer(until: Date().addingTimeInterval(TimeInterval(timerMax)))
    }

    /// Run the countdown to an absolute wall-clock end. Also the entry point
    /// for the Live Activity reconcile, which carries its own end date.
    func resumeTimer(until endsAt: Date) {
        timerEndsAt = endsAt
        timerSecs = max(0, Int(endsAt.timeIntervalSinceNow.rounded()))
        timerRunning = true
        // Background safety net: the tick task freezes when the app is
        // suspended, so a local notification announces "rest over" instead.
        // Same identifier every time — rescheduling replaces, never stacks.
        notifier.schedule(at: endsAt)
        runTimerLoop()
    }

    private func runTimerLoop() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    guard let self, self.timerRunning, let endsAt = self.timerEndsAt else { return }
                    // Recompute from the wall clock (not -= 1) so the display
                    // snaps back to the truth after backgrounding.
                    let remaining = Int(endsAt.timeIntervalSinceNow.rounded())
                    if remaining <= 0 {
                        self.resetTimer()
                        self.showToast("Rest over. Next set.")
                    } else {
                        self.timerSecs = remaining
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
        timerEndsAt = nil
        notifier.cancel()
    }

    func resetTimer() {
        timerTask?.cancel()
        timerRunning = false
        timerEndsAt = nil
        timerSecs = timerMax
        notifier.cancel()
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
        let weight = (exercise.bodyweight || exercise.timed) ? 0 : displayWeightToKg(Double(set.weight) ?? 0)
        guard let pr = personalRecords[exercise.name] else { return reps > 0 }
        return weight > pr.weight || (weight == pr.weight && reps > pr.reps)
    }

    /// Input→storage boundary: typed weight strings are in the display unit;
    /// convert to canonical KG here, the one place drafts become LoggedSets.
    private func loggedSet(for exercise: ActiveExercise, set: WorkoutSet) -> LoggedSet? {
        guard set.done, let reps = Int(set.reps), reps > 0 else { return nil }
        if exercise.bodyweight || exercise.timed {
            return LoggedSet(weight: nil, reps: reps)
        }
        guard let weight = Double(set.weight), weight >= 0 else { return nil }
        return LoggedSet(weight: displayWeightToKg(weight), reps: reps)
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

    /// Internal (not private) so the Live Activity bridge in another file can
    /// persist after folding in Lock-Screen edits.
    func persistDraft() {
        persistAll(draft: currentDraft)
    }

    private func persistAll(clearDraft: Bool = false, draft: WorkoutDraft? = nil) {
        let snapshot = AppSnapshot(
            sessions: sessions,
            personalRecords: Array(personalRecords.values),
            waterByDay: waterByDay,
            draft: clearDraft ? nil : (draft ?? currentDraft),
            unitPreference: unitPreference,
            hasOnboarded: hasOnboarded,
            timerPreset: timerMax
        )
        let previous = saveTask
        saveTask = Task { [localStore] in
            await previous?.value
            await localStore.save(snapshot)
        }
        updateLiveActivity(clearedDraft: clearDraft)
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

#if DEBUG
// ─────────────────────────────────────────────────────────────
//  DEMO SEED  (App Store / marketing screenshots only)
//  Populates the in-memory store with realistic data so the four tabs and the
//  Lock-Screen Live Activity look "lived in" for capture. Gated behind launch
//  arguments AND `#if DEBUG`, so it is impossible to reach in a release build,
//  and it never writes to disk (no `persistAll`), so it can't clobber real data.
//
//  Enable via simctl, e.g.:
//    xcrun simctl launch booted com.parthjadhav.ironlog -seedDemo YES -seedTab stats
//    xcrun simctl launch booted com.parthjadhav.ironlog -seedDemo YES -seedActive YES -seedTab log
// ─────────────────────────────────────────────────────────────
extension AppState {
    func applyDemoSeedIfRequested() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "seedDemo") else { return }

        // Clear any stale draft the local store may have restored, so every
        // non-active screen (Workouts / History / Stats) starts clean.
        resetActiveWorkout()
        showingOnboarding = false

        // A cloud-signed-in athlete reads better than "Local Athlete" for marketing.
        user = UserProfile(id: "demo", email: "alex@ironlog.app", fullName: "Alex Carter")
        syncMessage = "Synced with Supabase"

        let calendar = Calendar.current
        func day(_ offset: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return calendar.date(bySettingHour: 18, minute: 20, second: 0, of: base) ?? base
        }
        func exercise(_ name: String, _ sets: [(Double?, Int)], bodyweight: Bool = false) -> LoggedExercise {
            LoggedExercise(name: name, bodyweight: bodyweight, timed: false,
                           sets: sets.map { LoggedSet(weight: $0.0, reps: $0.1) })
        }
        func session(_ offset: Int, muscle: String, split: String, note: String? = nil,
                     _ exercises: [LoggedExercise]) -> WorkoutSession {
            WorkoutSession(createdAt: day(offset), muscle: muscle, split: split,
                           note: note, exercises: exercises, syncState: .synced)
        }

        sessions = [
            session(0, muscle: "chest", split: "PPL", note: "Felt strong on bench today.", [
                exercise("Barbell Bench Press", [(82.5, 8), (85, 6), (85, 5), (80, 7)]),
                exercise("Incline Dumbbell Press", [(30, 10), (32, 9), (32, 8)]),
                exercise("Seated DB Shoulder Press", [(24, 11), (24, 10), (24, 9)]),
                exercise("Tricep Pushdown (Cable)", [(35, 14), (35, 12), (32.5, 12)]),
            ]),
            session(1, muscle: "back", split: "PPL", [
                exercise("Deadlift", [(140, 5), (150, 3), (150, 3)]),
                exercise("Barbell Row", [(70, 8), (72.5, 8), (72.5, 7)]),
                exercise("Single-Arm Dumbbell Row", [(34, 10), (34, 10), (34, 9)]),
                exercise("Barbell Curl", [(35, 10), (37.5, 8), (37.5, 8)]),
            ]),
            session(2, muscle: "legs", split: "PPL", note: "New squat PR!", [
                exercise("Barbell Back Squat", [(110, 8), (120, 6), (125, 5)]),
                exercise("Romanian Deadlift", [(90, 10), (95, 10), (95, 9)]),
                exercise("Leg Press (Machine)", [(200, 14), (220, 12), (220, 12)]),
            ]),
            session(3, muscle: "chest", split: "PPL", [
                exercise("Barbell Bench Press", [(80, 8), (82.5, 7), (82.5, 6)]),
                exercise("Dumbbell Bench Press", [(30, 10), (30, 10), (30, 9)]),
                exercise("Barbell Overhead Press", [(50, 8), (52.5, 6), (52.5, 6)]),
            ]),
            session(4, muscle: "back", split: "PPL", [
                exercise("Pendlay Row", [(75, 6), (77.5, 6), (77.5, 5)]),
                exercise("T-Bar Row", [(60, 10), (60, 10), (60, 9)]),
                exercise("Hammer Curl", [(16, 12), (18, 10), (18, 10)]),
            ]),
            session(6, muscle: "legs", split: "Upper/Lower", [
                exercise("Front Squat", [(80, 8), (85, 6), (85, 6)]),
                exercise("Goblet Squat", [(40, 12), (40, 12), (40, 11)]),
                exercise("Leg Press (Machine)", [(200, 15), (210, 12), (210, 12)]),
            ]),
            session(8, muscle: "shoulders", split: "Bro Split", note: "Delts on fire.", [
                exercise("Barbell Overhead Press", [(50, 8), (50, 7), (47.5, 8)]),
                exercise("Dumbbell Lateral Raise", [(12, 18), (12, 16), (10, 18)]),
                exercise("Arnold Press", [(20, 12), (20, 11), (20, 10)]),
            ]),
        ].sorted { $0.createdAt > $1.createdAt }

        recalculateRecords()
        waterByDay[Date().dayKey] = 5

        // Optional: a live, half-logged Push session for the Log tab + Live Activity.
        if defaults.bool(forKey: "seedActive") {
            selectedSplit = "PPL"
            selectedDay = "Push"
            selectedMuscle = nil
            workoutStep = .workout
            todayExercises = [
                ActiveExercise(name: "Barbell Bench Press", bodyweight: false, timed: false, sets: [
                    WorkoutSet(weight: "82.5", reps: "8", done: true),
                    WorkoutSet(weight: "85", reps: "6", done: true),
                    WorkoutSet(weight: "85", reps: "5", done: false),
                ]),
                ActiveExercise(name: "Seated DB Shoulder Press", bodyweight: false, timed: false, sets: [
                    WorkoutSet(weight: "24", reps: "11", done: true),
                    WorkoutSet(weight: "24", reps: "10", done: false),
                    WorkoutSet(weight: "24", reps: "", done: false),
                ]),
                ActiveExercise(name: "Tricep Pushdown (Cable)", bodyweight: false, timed: false, sets: [
                    WorkoutSet(weight: "35", reps: "", done: false),
                    WorkoutSet(weight: "", reps: "", done: false),
                    WorkoutSet(weight: "", reps: "", done: false),
                ]),
            ]
            timerMax = 90
            timerSecs = 68
            timerRunning = true
            updateLiveActivity(clearedDraft: false)
        }

        switch defaults.string(forKey: "seedTab") {
        case "workouts": selectedTab = .workouts
        case "log": selectedTab = .log
        case "history": selectedTab = .history
        case "stats": selectedTab = .stats
        default: break
        }
    }
}
#endif
