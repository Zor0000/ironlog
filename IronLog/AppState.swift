import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var library = ExerciseLibrary.bundled
    @Published var user: UserProfile?
    @Published var selectedTab: WorkoutTab = .workouts
    /// Intentionally session-only: Progress remembers the user's last view
    /// while the app is open without turning a simple UI choice into user data.
    @Published var progressSection: ProgressSection = .stats
    @Published var nutritionPassport: NutritionPassport?
    @Published var authMessage: String?
    @Published var isPasswordRecovery = false
    @Published var toast: String?
    @Published var isBusy = false

    @Published var selectedSplit: String?
    @Published var selectedDay: String?
    @Published var workoutStep: WorkoutStep = .split {
        didSet { steppingBack = workoutStep.order < oldValue.order }
    }
    /// Which way the wizard last moved, so the screen transition can push
    /// forward or pop back. Derived here rather than at each call site — the
    /// back buttons assign `workoutStep` directly, and a restored draft jumps
    /// straight to its step — so every path animates the right way round.
    @Published private(set) var steppingBack = false
    @Published var todayExercises: [ActiveExercise] = []
    @Published var showAddExerciseForm = false
    @Published var addExerciseWeighted = false
    @Published var workoutNote = ""

    /// Workouts the user saved to run again, oldest first.
    @Published var routines: [SavedRoutine] = []

    @Published var sessions: [WorkoutSession] = []
    @Published var personalRecords: [String: PersonalRecord] = [:]
    @Published var waterByDay: [String: Int] = [:]
    @Published var syncMessage: String = "Local first"
    @Published var storageError: String?
    @Published var isBooting = true
    @Published var showingAuth = false
    @Published var showingOnboarding = false
    @Published var unitPreference: WeightUnit = .kg
    /// Canonical KG; drives every run/walk calorie estimate. Nil until set.
    @Published var bodyWeight: Double?

    @Published var timerSecs = 90
    @Published var timerMax = 90
    @Published var timerRunning = false

    private let localStore: LocalStore
    private let supabase: SupabaseService
    private let allowDebugSeeds: Bool
    /// Internal (not private) so tests can swap in a spy.
    var notifier = RestTimerNotifier()
    private var hasOnboarded = false
    /// Wall-clock end of the running rest timer, so the countdown stays
    /// correct across backgrounding (the tick task is suspended while inactive).
    private var timerEndsAt: Date?
    private var timerTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var syncRetryTask: Task<Void, Never>?
    private var syncRetryAttempt = 0
    private var isSyncing = false
    private var routineSyncTask: Task<Void, Never>?
    private var routineSyncGeneration = 0
    private var isDeletingAllData = false
    private var isFlushingWorkoutWipe = false
    private var deletedCloudSessionIDs: Set<String> = []
    private var pendingCloudSessionDeletions: Set<String> = []
    private var deletedRoutineIDs: Set<UUID> = []
    private var pendingRoutineDeletions: Set<UUID> = []
    private var pendingPRSync = false
    private var pendingWorkoutWipe = false
    /// Nil selects the guest/local snapshot; a Supabase user id selects that
    /// account's isolated on-device snapshot.
    private var activeStoreOwnerID: String?
    /// Serializes disk writes. `persistAll` can fire many times in quick
    /// succession (e.g. on every keystroke in a set field); chaining each save
    /// onto the previous one guarantees the most recent snapshot is the last
    /// one written, rather than racing independent tasks onto the actor.
    private var saveTask: Task<Void, Never>?
    private var failedSave: (snapshot: AppSnapshot, ownerID: String?, replacingBackup: Bool)?
    @Published private(set) var isRetryingStorage = false
    private let localUser = UserProfile(id: "local", email: "local@ironlog", fullName: "Local Athlete", isLocal: true)

    init(localStore: LocalStore = LocalStore(), supabase: SupabaseService = SupabaseService(),
         allowDebugSeeds: Bool = true) {
        self.localStore = localStore
        self.supabase = supabase
        self.allowDebugSeeds = allowDebugSeeds
    }

    var waterToday: Int {
        waterByDay[Date().dayKey] ?? 0
    }

    var hasActiveWorkout: Bool {
        !todayExercises.isEmpty || showAddExerciseForm || !workoutNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedWorkoutMuscleIDs: [String] {
        library.muscleIDs(split: selectedSplit, day: selectedDay)
    }

    /// The single muscle a session targets (single-muscle days), else nil for
    /// whole-body / multi-muscle days. Feeds the history chip and the
    /// add-exercise catalog filter.
    var singleTargetMuscle: String? {
        let ids = selectedWorkoutMuscleIDs
        return ids.count == 1 ? ids.first : nil
    }

    var selectedWorkoutMuscleLabel: String {
        if selectedDay == nil, selectedSplit == ExerciseLibrary.fullBodySplit {
            return ExerciseLibrary.fullBodySplit
        }
        let labels = selectedWorkoutMuscleIDs.compactMap { library.muscle($0)?.label }
        if labels.isEmpty { return selectedSplit ?? "Workout" }
        if labels.count == 1 { return labels[0] }
        return labels.joined(separator: " + ")
    }

    var activeExerciseTemplates: [ExerciseTemplate] {
        library.exercises(split: selectedSplit, day: selectedDay)
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
                    guard set.isWorkingSet else { return }
                    if let weight = set.weight, weight > 0 {
                        volume += weight * set.reps
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
        defer { isBooting = false }
        await supabase.restoreSessionIfNeeded()
        var suppressOnboarding = false
        #if DEBUG
        if allowDebugSeeds && ProcessInfo.processInfo.arguments.contains("UITest_ResetStore") {
            try? await localStore.clear(ownerID: nil)
            await supabase.signOut()
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: "seedDemo")
            defaults.removeObject(forKey: "seedActive")
            defaults.removeObject(forKey: "seedTab")
            suppressOnboarding = true // existing UI tests expect a clean slate, not intro cards
        }
        #endif

        let restoredUser = supabase.currentUser
        activeStoreOwnerID = restoredUser?.id
        if let ownerID = activeStoreOwnerID {
            do { try await localStore.migrateLegacyStoreIfNeeded(to: ownerID) }
            catch { storageError = error.localizedDescription; user = restoredUser ?? localUser; return }
        }
        do { applySnapshot(try await localStore.load(ownerID: activeStoreOwnerID), suppressOnboarding: suppressOnboarding) }
        catch { storageError = error.localizedDescription; user = restoredUser ?? localUser; return }
        if await localStore.didRecoverFromBackup {
            syncMessage = "Recovered the previous local save. Check your recent changes."
            showToast(syncMessage)
        }

        user = restoredUser
        if restoredUser == nil {
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
        if allowDebugSeeds {
            applyDemoSeedIfRequested()
            applyIronFuelUITestSeedIfRequested()
            if ProcessInfo.processInfo.arguments.contains("UITest_ShowAuth") {
                showAuth()
            }
        }
        #endif
        // The local snapshot and any launch-only seed are now applied. Allow
        // interaction before network sync, which may take time while offline.
        isBooting = false
        if restoredUser != nil { await refreshAndSync() }
    }

    func signIn(email: String, password: String) async {
        await runBusy {
            let profile = try await supabase.signIn(email: email, password: password)
            await finishAuthentication(profile)
        }
    }

    func signUp(email: String, password: String, name: String) async -> Bool {
        var needsConfirmation = false
        let succeeded = await runBusy {
            if let profile = try await supabase.signUp(email: email, password: password, name: name) {
                await finishAuthentication(profile)
            } else {
                needsConfirmation = true
                authMessage = "Account created. Check your email to confirm, then sign in."
            }
        }
        return succeeded && needsConfirmation
    }

    func signInWithGoogle() async {
        await runBusy {
            let profile = try await supabase.signInWithGoogle()
            await finishAuthentication(profile)
        }
    }

    @discardableResult
    func requestPasswordReset(email: String) async -> Bool {
        let succeeded = await runBusy {
            try await supabase.requestPasswordReset(email: email)
        }
        if succeeded {
            authMessage = "If an account exists for that email, a reset link is on its way."
        }
        return succeeded
    }

    func handleAuthURL(_ url: URL) async {
        guard url.scheme?.lowercased() == "ironlog" else { return }
        await runBusy {
            let profile = try await supabase.handleAuthCallback(url)
            if url.path.lowercased().contains("reset-password") {
                user = profile
                showingAuth = true
                isPasswordRecovery = true
                authMessage = nil
            } else {
                await finishAuthentication(profile)
            }
        }
    }

    @discardableResult
    func completePasswordReset(_ password: String) async -> Bool {
        await runBusy {
            let profile = try await supabase.updatePassword(password)
            isPasswordRecovery = false
            await finishAuthentication(profile)
            showToast("Password updated")
        }
    }

    private func finishAuthentication(_ profile: UserProfile) async {
        guard await activateStore(for: profile) else { return }
        user = profile
        showingAuth = false
        isPasswordRecovery = false
        authMessage = nil
        await refreshAndSync(reportMigrationProgress: true)
    }

    func signOut() async {
        cancelSyncRetry(resetAttempt: true)
        await saveTask?.value
        await supabase.signOut()
        activeStoreOwnerID = nil
        do { applySnapshot(try await localStore.load(ownerID: nil), suppressOnboarding: true) }
        catch { storageError = error.localizedDescription; return }
        hasOnboarded = true
        user = localUser
        showingAuth = false
        authMessage = nil
        syncMessage = "Saved on this iPhone"
        selectedTab = .workouts
        persistAll()
        await saveTask?.value
    }

    func continueLocally() {
        user = localUser
        showingAuth = false
        isPasswordRecovery = false
        authMessage = nil
        syncMessage = "Saved on this iPhone"
    }

    func showAuth() {
        showingAuth = true
        isPasswordRecovery = false
        authMessage = nil
    }

    /// Remove workout records while keeping the current sign-in profile.
    @discardableResult
    func deleteWorkoutData() async -> Bool {
        await deleteUserData(removingAccount: false)
    }

    /// Delete the authenticated identity and all associated workout data.
    @discardableResult
    func deleteAccount() async -> Bool {
        await deleteUserData(removingAccount: true)
    }

    private func deleteUserData(removingAccount: Bool) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        guard storageError == nil, !isDeletingAllData else { return false }
        isDeletingAllData = true
        defer { isDeletingAllData = false }
        while isSyncing { try? await Task.sleep(for: .milliseconds(100)) }
        await routineSyncTask?.value
        if removingAccount {
            guard supabase.isAuthenticated else {
                showToast("Sign in again before deleting your account")
                return false
            }
            do {
                try await supabase.deleteAccount()
            } catch SupabaseError.sessionExpired {
                await handleExpiredSession()
                return false
            } catch {
                showToast("Couldn't delete your account. Check your connection and try again.")
                return false
            }
        }
        clearWorkoutState()
        pendingWorkoutWipe = !removingAccount && activeStoreOwnerID != nil
        persistAll(clearDraft: true, replacingBackup: true)
        await saveTask?.value
        guard storageError == nil else { return false }
        selectedTab = .workouts
        if removingAccount {
            await supabase.signOut()
            do { try await localStore.clear(ownerID: activeStoreOwnerID) }
            catch { storageError = error.localizedDescription; return false }
            activeStoreOwnerID = nil
            do { applySnapshot(try await localStore.load(ownerID: nil), suppressOnboarding: true) }
            catch { storageError = error.localizedDescription; return false }
            hasOnboarded = true
            user = localUser
            showingAuth = false
            authMessage = nil
            syncMessage = "Saved on this iPhone"
            showToast("Account deleted")
        } else {
            if pendingWorkoutWipe { _ = await flushPendingWorkoutWipe() }
            syncMessage = pendingWorkoutWipe ? "Deleted locally. Cloud deletion pending." : "Workout data deleted"
            showToast(syncMessage)
        }
        return true
    }

    private func clearWorkoutState() {
        sessions = []
        personalRecords = [:]
        deletedCloudSessionIDs = []
        pendingCloudSessionDeletions = []
        deletedRoutineIDs = []
        pendingRoutineDeletions = []
        pendingPRSync = false
        waterByDay = [:]
        routines = []
        bodyWeight = nil
        currentBodyWeight = 0
        resetActiveWorkout()
        updateLiveActivity(clearedDraft: true)
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
                guard let value = decimalEntry(todayExercises[ei].sets[si].weight), value > 0 else { continue }
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
        // Day-based splits pick a day next; day-less Full Body drops straight into
        // its whole-body session.
        workoutStep = library.splitDays[split] != nil ? .day : .workout
    }

    func selectDay(_ day: String) {
        selectedDay = day
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
        todayExercises = Self.activeExercises(from: templates)
        selectedTab = .log
        persistDraft()
        showToast("\(selectedWorkoutMuscleLabel) workout started")
    }

    /// Blank sets laid out from a set of templates — the one way a workout is
    /// stocked, whether the templates came from a bundled split or a routine the
    /// user saved.
    private static func activeExercises(from templates: [ExerciseTemplate]) -> [ActiveExercise] {
        templates.map { template in
            ActiveExercise(
                name: template.name,
                bodyweight: template.bodyweight,
                timed: template.timed,
                minutes: template.minutes,
                // Starts collapsed so the list isn't overwhelming — user opens each exercise as they reach it.
                expanded: false,
                sets: (0..<max(template.sets, 1)).map { _ in WorkoutSet() }
            )
        }
    }

    func startFreeWorkout() {
        guard !hasActiveWorkout else {
            selectedTab = .log
            showToast("Finish or discard the current workout first")
            return
        }
        selectedSplit = "Free Workout"
        selectedDay = nil
        workoutStep = .split
        todayExercises = []
        showAddExerciseForm = true
        selectedTab = .log
        persistDraft()
        showToast("Free workout started")
    }

    // MARK: - Saved routines

    /// The routine the active workout was started from, if any. `selectedSplit`
    /// carries the routine's name, so a match means "this is your staple, edited".
    var matchingRoutineName: String? {
        guard let split = selectedSplit else { return nil }
        return routines.first { $0.name == split }?.name
    }

    /// Keep whatever is in the log as a named routine to run again.
    ///
    /// Saving under a name already in use replaces that routine rather than
    /// adding a second one: the staple workout this is built for is something
    /// you tweak over months, and "Leg Day" three times over helps nobody.
    func saveRoutine(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showToast("Name the routine first")
            return
        }
        guard !todayExercises.isEmpty else {
            showToast("Add an exercise before saving a routine")
            return
        }

        let templates = todayExercises.map { exercise in
            ExerciseTemplate(
                name: exercise.name,
                sets: max(exercise.sets.count, 1),
                // The target to aim for next time, taken from what was actually
                // entered. Blank until a set is filled in, which is fine — it is
                // shown as guidance, never used to prefill.
                reps: exercise.sets.first(where: { !$0.reps.isEmpty })?.reps ?? "",
                tip: "",
                bodyweight: exercise.bodyweight,
                timed: exercise.timed,
                minutes: exercise.usesMinutes
            )
        }

        if let existing = routines.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            routines[existing].exercises = templates
            showToast("\(routines[existing].name) updated")
        } else {
            routines.append(SavedRoutine(name: trimmed, exercises: templates))
            showToast("\(trimmed) saved")
        }
        persistAll()
        syncRoutines()
    }

    func startRoutine(_ routine: SavedRoutine) {
        guard !hasActiveWorkout else {
            selectedTab = .log
            showToast("Finish or discard the current workout first")
            return
        }
        guard !routine.exercises.isEmpty else {
            showToast("That routine has no exercises")
            return
        }
        // The routine's name stands in for the split, so it labels the session in
        // History and titles the Live Activity. `muscleIDs` finds nothing for it,
        // which is correct — a routine spans whatever the user put in it.
        selectedSplit = routine.name
        selectedDay = nil
        workoutStep = .split
        todayExercises = Self.activeExercises(from: routine.exercises)
        selectedTab = .log
        persistDraft()
        showToast("\(routine.name) started")
    }

    func deleteRoutine(_ id: SavedRoutine.ID) async {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        let name = routines.remove(at: index).name
        if activeStoreOwnerID != nil {
            deletedRoutineIDs.insert(id)
            pendingRoutineDeletions.insert(id)
        }
        persistAll(replacingBackup: true)
        await saveTask?.value
        guard storageError == nil else { return }
        showToast(activeStoreOwnerID == nil ? "\(name) deleted on this iPhone" : "\(name) deleted; cloud sync pending")
        if supabase.isAuthenticated { await flushPendingDeletes() }
    }

    /// Re-sending live routines is idempotent; tombstones are filtered first.
    private func syncRoutines() {
        guard supabase.isAuthenticated, !isDeletingAllData, !pendingWorkoutWipe else { return }
        let snapshot = routines.filter { !deletedRoutineIDs.contains($0.id) }
        let ownerID = activeStoreOwnerID
        let previous = routineSyncTask
        routineSyncGeneration += 1
        let generation = routineSyncGeneration
        routineSyncTask = Task {
            defer { if routineSyncGeneration == generation { routineSyncTask = nil } }
            await previous?.value
            for routine in snapshot {
                guard activeStoreOwnerID == ownerID, !deletedRoutineIDs.contains(routine.id), !isDeletingAllData else { return }
                do {
                    try await supabase.backup(routine: routine)
                    guard activeStoreOwnerID == ownerID else { return }
                    if deletedRoutineIDs.contains(routine.id) {
                        pendingRoutineDeletions.insert(routine.id)
                        persistAll()
                        await flushPendingDeletes()
                    }
                } catch SupabaseError.sessionExpired {
                    await handleExpiredSession()
                    return
                } catch {
                    syncMessage = "Saved locally. Routine backup failed."
                    scheduleSyncRetry()
                    return
                }
            }
        }
    }

    /// Union the cloud's routines with the local ones by id, then collapse any
    /// name collision the merge introduced — two devices can each invent a
    /// "Leg Day" with different ids, and the app promises one routine per name.
    /// Most recently created wins, matching the local save-replaces rule.
    private func mergeCloudRoutines(_ cloud: [SavedRoutine]) {
        var byID = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0) })
        for routine in cloud where byID[routine.id] == nil && !deletedRoutineIDs.contains(routine.id) {
            byID[routine.id] = routine
        }
        var seen: [String: SavedRoutine] = [:]
        for routine in byID.values.sorted(by: { $0.createdAt < $1.createdAt }) {
            seen[routine.name.lowercased()] = routine
        }
        routines = seen.values.sorted { $0.createdAt < $1.createdAt }
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
            todayExercises[ei].sets[si].weight = sanitizeDecimalInput(weight)
        }
        if let reps {
            // Timed work types seconds/minutes, which have no halves.
            todayExercises[ei].sets[si].reps = todayExercises[ei].timed
                ? sanitizeDecimalInput(reps)
                : snapReps(reps)
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

    /// Tag how a set was performed, or pass nil to make it an ordinary set again.
    func setType(exerciseID: ActiveExercise.ID, setID: WorkoutSet.ID, to type: SetType?) {
        guard let ei = todayExercises.firstIndex(where: { $0.id == exerciseID }),
              let si = todayExercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        todayExercises[ei].sets[si].type = type
        persistDraft()
    }

    /// Add, edit, or clear the note attached to one set.
    func setRemark(exerciseID: ActiveExercise.ID, setID: WorkoutSet.ID, to remark: String?) {
        guard let ei = todayExercises.firstIndex(where: { $0.id == exerciseID }),
              let si = todayExercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        todayExercises[ei].sets[si].remark = normalizedRemark(remark)
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

    /// Repositions an exercise in the active workout. `destinationIndex` is the
    /// final index the exercise should occupy, which keeps both drag-hover moves
    /// and VoiceOver's move up/down actions predictable.
    func moveExercise(_ exerciseID: ActiveExercise.ID, to destinationIndex: Int) {
        guard todayExercises.count > 1,
              let sourceIndex = todayExercises.firstIndex(where: { $0.id == exerciseID }) else { return }

        let clampedDestination = min(max(destinationIndex, 0), todayExercises.count - 1)
        guard sourceIndex != clampedDestination else { return }

        let exercise = todayExercises.remove(at: sourceIndex)
        todayExercises.insert(exercise, at: clampedDestination)
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
            minutes: template.minutes,
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
            return LoggedExercise(name: exercise.name, bodyweight: exercise.bodyweight, timed: exercise.timed, minutes: exercise.minutes, sets: sets)
        }
        guard !logged.isEmpty else {
            showToast("Log at least one set first")
            return
        }

        let session = WorkoutSession(
            userID: user?.id,
            createdAt: Date(),
            muscle: singleTargetMuscle,
            split: selectedSplit,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
            exercises: logged,
            syncState: supabase.isAuthenticated ? .pending : .localOnly
        )
        applyRecords(from: session)
        sessions.insert(session, at: 0)
        resetActiveWorkout()
        persistAll(clearDraft: true)
        progressSection = .history
        selectedTab = .progress
        await saveTask?.value
        guard storageError == nil else { return }
        showToast("Workout saved")
        if supabase.isAuthenticated { await syncPending() }
    }

    /// Body weight drives every run/walk calorie estimate. Stored canonically
    /// in KG like all weights; nil clears it (estimates then return nil).
    func setBodyWeight(_ kg: Double?) {
        guard let kg else {
            bodyWeight = nil
            currentBodyWeight = 0
            persistAll()
            return
        }
        guard kg.isFinite, EntryLimit.bodyWeightKg.contains(kg) else {
            return
        }
        // A tenth of a kg is finer than any scale worth owning; beyond that
        // the digits only hide the estimate's own coarseness.
        bodyWeight = (kg * 10).rounded() / 10
        currentBodyWeight = bodyWeight!
        persistAll()
    }

    func requestFuelBuddy(query: String, passport: NutritionPassport) async -> FuelBuddyResult {
        await FuelBuddyService(provider: supabase.fuelBuddyProvider).recommend(passport: passport, query: query)
    }

    func saveNutritionPassport(_ passport: NutritionPassport) {
        nutritionPassport = passport.normalized
        persistAll()
        showToast(passport.isComplete ? "Nutrition Passport saved" : "Passport progress saved")
    }

    func deleteNutritionPassport() {
        nutritionPassport = nil
        persistAll()
        showToast("Nutrition Passport deleted")
    }

    /// Save a run/walk logged by hand as its own session. It carries no
    /// exercises, so it bypasses `finishWorkout`'s set validation entirely; the
    /// streak and the History timeline pick it up like any other session.
    /// `at` can back-date a run the user did before opening the app.
    @discardableResult
    func saveRun(_ activity: CardioActivity, at date: Date = Date()) async -> Bool {
        let session = WorkoutSession(
            userID: user?.id,
            createdAt: date,
            muscle: nil,
            split: activity.kind.label,
            note: nil,
            exercises: [],
            syncState: supabase.isAuthenticated ? .pending : .localOnly,
            activity: activity
        )
        sessions.insert(session, at: 0)
        // A back-dated run belongs where its date puts it, not at the top.
        sessions.sort { $0.createdAt > $1.createdAt }
        persistAll()
        await saveTask?.value
        guard storageError == nil else { return false }
        progressSection = .history
        selectedTab = .progress
        showToast("\(activity.kind.label) saved")
        if supabase.isAuthenticated {
            Task { await syncPending() }
        }
        return true
    }

    func deleteSession(_ id: WorkoutSession.ID) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        sessions.removeAll { $0.id == id }
        if activeStoreOwnerID != nil {
            let cloudID = session.cloudID ?? session.id.uuidString.lowercased()
            deletedCloudSessionIDs.insert(cloudID)
            pendingCloudSessionDeletions.insert(cloudID)
            pendingPRSync = true
        }
        recalculateRecords()
        persistAll(replacingBackup: true)
        await saveTask?.value
        guard storageError == nil else { return }
        showToast(activeStoreOwnerID == nil ? "Session deleted on this iPhone" : "Session deleted; cloud sync pending")
        if supabase.isAuthenticated { await refreshAndSync() }
    }

    /// Save an edited past session. Sets pass through the same `loggedSet`
    /// validation as a live workout, PRs are recomputed (an edit can raise or
    /// lower one), and the session re-enters the existing pending-sync queue.
    @discardableResult
    func updateSession(id: WorkoutSession.ID, exercises: [ActiveExercise], note: String) async -> Bool {
        guard storageError == nil else { return false }
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return false }
        let logged = exercises.compactMap { exercise -> LoggedExercise? in
            let sets = exercise.sets.compactMap { loggedSet(for: exercise, set: $0) }
            guard !sets.isEmpty else { return nil }
            return LoggedExercise(name: exercise.name, bodyweight: exercise.bodyweight, timed: exercise.timed, minutes: exercise.minutes, sets: sets)
        }
        guard !logged.isEmpty else {
            showToast("Keep at least one valid set")
            return false
        }
        var session = sessions[index]
        let oldCloudID = session.cloudID
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        session.exercises = logged
        session.note = trimmedNote.isEmpty ? nil : trimmedNote
        if let oldCloudID, oldCloudID != session.id.uuidString.lowercased() {
            deletedCloudSessionIDs.insert(oldCloudID)
            pendingCloudSessionDeletions.insert(oldCloudID)
        }
        session.cloudID = nil
        session.syncState = supabase.isAuthenticated ? .pending : .localOnly
        sessions[index] = session
        recalculateRecords()
        pendingPRSync = activeStoreOwnerID != nil
        persistAll()
        await saveTask?.value
        guard storageError == nil else { return false }
        showToast(activeStoreOwnerID == nil ? "Session updated on this iPhone" : "Session updated; cloud sync pending")
        if supabase.isAuthenticated { await refreshAndSync() }
        return true
    }

    func setWater(index: Int) {
        let next = index < waterToday ? index : index + 1
        waterByDay[Date().dayKey] = next
        persistAll()
    }

    func setTimerPreset(_ seconds: Int) {
        guard restTimerPresets.contains(seconds) else { return }
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

    func syncPending(reportMigrationProgress: Bool = false, resetRetryOnSuccess: Bool = true) async {
        guard storageError == nil, supabase.isAuthenticated, !isSyncing, !isDeletingAllData,
              !pendingWorkoutWipe else { return }
        isSyncing = true
        defer { isSyncing = false }
        let ownerID = activeStoreOwnerID
        await flushPendingDeletes()
        guard activeStoreOwnerID == ownerID, supabase.isAuthenticated else { return }
        let uploadCount = sessions.filter { $0.syncState != .synced }.count
        if reportMigrationProgress, uploadCount > 0 {
            let message = "Uploading \(uploadCount) workout\(uploadCount == 1 ? "" : "s")…"
            syncMessage = message
            showToast(message)
        }
        let syncedUserID = supabase.currentUser?.id
        for session in sessions where session.syncState != .synced {
            guard activeStoreOwnerID == ownerID else { return }
            if deletedCloudSessionIDs.contains(session.cloudID ?? session.id.uuidString.lowercased()) { continue }
            do {
                let cloudID = try await supabase.backup(session: session, records: Array(personalRecords.values))
                guard activeStoreOwnerID == ownerID else { return }
                if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                    // An edit can land while the upload is in flight. Keep its
                    // pending state so the next pass uploads the newer value.
                    if sessions[index] == session {
                        sessions[index].cloudID = cloudID
                        sessions[index].userID = syncedUserID ?? sessions[index].userID
                        sessions[index].syncState = .synced
                    }
                } else {
                    deletedCloudSessionIDs.insert(cloudID)
                    pendingCloudSessionDeletions.insert(cloudID)
                }
            } catch SupabaseError.sessionExpired {
                await handleExpiredSession()
                break
            } catch {
                markFailed(session.id, error: error)
            }
        }
        guard activeStoreOwnerID == ownerID else { return }
        persistAll()
        guard supabase.isAuthenticated else { return }
        let hasFailures = sessions.contains { $0.syncState != .synced }
            || !pendingCloudSessionDeletions.isEmpty || !pendingRoutineDeletions.isEmpty
        if hasFailures {
            scheduleSyncRetry()
        } else {
            if resetRetryOnSuccess { cancelSyncRetry(resetAttempt: true) }
            if reportMigrationProgress, uploadCount > 0 {
                let message = "Uploaded \(uploadCount) workout\(uploadCount == 1 ? "" : "s") to Supabase"
                syncMessage = message
                showToast(message)
            }
        }
    }

    func syncNow() async {
        guard supabase.isAuthenticated else {
            showAuth()
            return
        }
        syncMessage = "Syncing..."
        await refreshAndSync()
        if syncMessage == "Syncing..." {
            syncMessage = "Synced with Supabase"
        }
        showToast(syncMessage)
    }

    @discardableResult
    private func refreshFromCloud() async -> Bool {
        guard storageError == nil, !pendingWorkoutWipe else { return false }
        let ownerID = activeStoreOwnerID
        do {
            let cloudSessions = try await supabase.pullSessions()
            let cloudRoutines = try await supabase.pullRoutines()
            guard activeStoreOwnerID == ownerID, !isDeletingAllData, !pendingWorkoutWipe else { return false }
            mergeCloudSessions(cloudSessions)
            mergeCloudRoutines(cloudRoutines)
            persistAll()
            syncRoutines()
            syncMessage = "Synced with Supabase"
            return true
        } catch SupabaseError.sessionExpired {
            await handleExpiredSession()
            return false
        } catch {
            syncMessage = "Local first. Cloud unavailable."
            return false
        }
    }

    private func refreshAndSync(reportMigrationProgress: Bool = false) async {
        guard storageError == nil, !isDeletingAllData else { return }
        if pendingWorkoutWipe {
            _ = await flushPendingWorkoutWipe()
            guard !pendingWorkoutWipe, storageError == nil, supabase.isAuthenticated else { return }
        }
        await flushPendingDeletes()
        let cloudAvailable = await refreshFromCloud()
        guard supabase.isAuthenticated, !isDeletingAllData, !pendingWorkoutWipe else { return }
        await syncPending(reportMigrationProgress: reportMigrationProgress, resetRetryOnSuccess: false)
        guard supabase.isAuthenticated, !isDeletingAllData, !pendingWorkoutWipe else { return }
        if cloudAvailable && !sessions.contains(where: { $0.syncState != .synced })
            && pendingCloudSessionDeletions.isEmpty && pendingRoutineDeletions.isEmpty && pendingPRSync {
            do {
                try await supabase.replacePersonalRecords(Array(personalRecords.values))
                pendingPRSync = false
                persistAll()
            } catch {
                syncMessage = "Saved locally. Record sync pending."
            }
        }
        if cloudAvailable && !sessions.contains(where: { $0.syncState != .synced })
            && pendingCloudSessionDeletions.isEmpty && pendingRoutineDeletions.isEmpty && !pendingPRSync {
            cancelSyncRetry(resetAttempt: true)
            syncMessage = "Synced with Supabase"
        } else {
            if !cloudAvailable {
                syncMessage = "Saved locally. Cloud sync pending."
            }
            scheduleSyncRetry()
        }
    }

    private func flushPendingDeletes() async {
        guard storageError == nil, supabase.isAuthenticated, !pendingWorkoutWipe else { return }
        let ownerID = activeStoreOwnerID
        await saveTask?.value
        guard activeStoreOwnerID == ownerID else { return }
        for cloudID in pendingCloudSessionDeletions.sorted() {
            do {
                try await supabase.deleteCloudSession(cloudID)
                guard activeStoreOwnerID == ownerID else { return }
                pendingCloudSessionDeletions.remove(cloudID)
                persistAll()
                await saveTask?.value
            } catch SupabaseError.sessionExpired {
                await handleExpiredSession()
                return
            } catch {
                syncMessage = "Saved locally. Cloud delete pending."
                scheduleSyncRetry()
                return
            }
        }
        for id in pendingRoutineDeletions.sorted(by: { $0.uuidString < $1.uuidString }) {
            do {
                try await supabase.deleteCloudRoutine(id)
                guard activeStoreOwnerID == ownerID else { return }
                pendingRoutineDeletions.remove(id)
                persistAll()
                await saveTask?.value
            } catch SupabaseError.sessionExpired {
                await handleExpiredSession()
                return
            } catch {
                syncMessage = "Saved locally. Cloud delete pending."
                scheduleSyncRetry()
                return
            }
        }
    }

    @discardableResult
    private func flushPendingWorkoutWipe() async -> Bool {
        guard pendingWorkoutWipe, storageError == nil, supabase.isAuthenticated,
              !isFlushingWorkoutWipe else { return false }
        isFlushingWorkoutWipe = true
        defer { isFlushingWorkoutWipe = false }
        let ownerID = activeStoreOwnerID
        await saveTask?.value
        guard activeStoreOwnerID == ownerID, storageError == nil else { return false }
        do {
            try await supabase.deleteWorkoutData()
            guard activeStoreOwnerID == ownerID else { return false }
            pendingWorkoutWipe = false
            persistAll(replacingBackup: true)
            await saveTask?.value
            return storageError == nil
        } catch SupabaseError.sessionExpired {
            await handleExpiredSession()
            return false
        } catch {
            syncMessage = "Deleted locally. Cloud deletion pending."
            scheduleSyncRetry()
            return false
        }
    }

    private func handleExpiredSession() async {
        cancelSyncRetry(resetAttempt: true)
        await saveTask?.value
        await supabase.signOut()
        activeStoreOwnerID = nil
        do { applySnapshot(try await localStore.load(ownerID: nil), suppressOnboarding: true) }
        catch { storageError = error.localizedDescription; return }
        hasOnboarded = true
        user = nil
        showingAuth = true
        authMessage = SupabaseError.sessionExpired.localizedDescription
        syncMessage = "Sign in again to resume cloud sync"
        persistAll()
    }

    /// Retry transient pull or upload failures without making the user press
    /// Sync. Launch-time `refreshAndSync` remains the durable fallback when iOS
    /// suspends the app before one of these timers fires.
    static func syncRetryDelay(attempt: Int) -> Int {
        let delays = [5, 15, 45, 120]
        return delays[min(max(attempt, 0), delays.count - 1)]
    }

    func resumeForegroundSync() async {
        guard !isBooting, storageError == nil, supabase.isAuthenticated else { return }
        cancelSyncRetry(resetAttempt: true)
        await refreshAndSync()
    }

    private func scheduleSyncRetry() {
        guard supabase.isAuthenticated, storageError == nil, syncRetryTask == nil else { return }
        let delays = [5, 15, 45, 120]
        let delay = Self.syncRetryDelay(attempt: syncRetryAttempt)
        syncRetryAttempt = min(syncRetryAttempt + 1, delays.count - 1)
        syncRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            self.syncRetryTask = nil
            await self.refreshAndSync()
        }
    }

    private func cancelSyncRetry(resetAttempt: Bool = false) {
        syncRetryTask?.cancel()
        syncRetryTask = nil
        if resetAttempt { syncRetryAttempt = 0 }
    }

    /// Switch from the guest snapshot to an account-scoped snapshot. Guest
    /// workouts are intentionally imported on sign-in (the advertised local →
    /// cloud migration), then the guest file is cleared so a later sign-out
    /// cannot expose those workouts to another person using this device.
    private func activateStore(for profile: UserProfile) async -> Bool {
        guard storageError == nil else { return false }
        await saveTask?.value
        let guestSnapshot = makeSnapshot()
        let accountSnapshot: AppSnapshot
        do { accountSnapshot = try await localStore.load(ownerID: profile.id) }
        catch { storageError = error.localizedDescription; return false }
        let snapshot: AppSnapshot
        if activeStoreOwnerID == nil {
            snapshot = Self.merging(guest: guestSnapshot, into: accountSnapshot)
        } else {
            snapshot = accountSnapshot
        }
        activeStoreOwnerID = profile.id
        applySnapshot(snapshot)
        do { try await localStore.save(snapshot, ownerID: profile.id) }
        catch { storageError = error.localizedDescription; return false }
        if activeStoreOwnerID == profile.id {
            let guestShell = AppSnapshot(
                unitPreference: snapshot.unitPreference,
                hasOnboarded: true,
                timerPreset: snapshot.timerPreset
            )
            do { try await localStore.save(guestShell, ownerID: nil) }
            catch { storageError = error.localizedDescription; return false }
        }
        return true
    }

    private static func merging(guest: AppSnapshot, into account: AppSnapshot) -> AppSnapshot {
        var sessionsByID = Dictionary(uniqueKeysWithValues: account.sessions.map { ($0.id, $0) })
        for session in guest.sessions where sessionsByID[session.id] == nil {
            sessionsByID[session.id] = session
        }

        var routinesByID = Dictionary(uniqueKeysWithValues: (account.routines ?? []).map { ($0.id, $0) })
        for routine in guest.routines ?? [] where routinesByID[routine.id] == nil {
            routinesByID[routine.id] = routine
        }

        var water = account.waterByDay
        for (day, glasses) in guest.waterByDay {
            water[day] = max(water[day] ?? 0, glasses)
        }

        return AppSnapshot(
            sessions: sessionsByID.values.sorted { $0.createdAt > $1.createdAt },
            personalRecords: account.personalRecords + guest.personalRecords,
            waterByDay: water,
            draft: guest.draft ?? account.draft,
            unitPreference: account.unitPreference ?? guest.unitPreference,
            hasOnboarded: (account.hasOnboarded == true || guest.hasOnboarded == true),
            timerPreset: account.timerPreset ?? guest.timerPreset,
            routines: routinesByID.values.sorted { $0.createdAt < $1.createdAt },
            bodyWeight: account.bodyWeight ?? guest.bodyWeight,
            nutritionPassport: account.nutritionPassport ?? guest.nutritionPassport,
            deletedCloudSessionIDs: account.deletedCloudSessionIDs,
            pendingCloudSessionDeletions: account.pendingCloudSessionDeletions,
            deletedRoutineIDs: account.deletedRoutineIDs,
            pendingRoutineDeletions: account.pendingRoutineDeletions,
            pendingPRSync: account.pendingPRSync,
            pendingWorkoutWipe: account.pendingWorkoutWipe
        )
    }

    private func applySnapshot(_ snapshot: AppSnapshot, suppressOnboarding: Bool = false) {
        resetActiveWorkout()
        selectedTab = .workouts
        deletedCloudSessionIDs = snapshot.deletedCloudSessionIDs
        pendingCloudSessionDeletions = snapshot.pendingCloudSessionDeletions
        deletedRoutineIDs = snapshot.deletedRoutineIDs
        pendingRoutineDeletions = snapshot.pendingRoutineDeletions
        pendingPRSync = snapshot.pendingPRSync
        pendingWorkoutWipe = snapshot.pendingWorkoutWipe
        sessions = snapshot.sessions.filter { session in
            !deletedCloudSessionIDs.contains(session.cloudID ?? session.id.uuidString.lowercased())
        }.sorted { $0.createdAt > $1.createdAt }
        personalRecords = Dictionary(
            snapshot.personalRecords.map { ($0.exerciseName, $0) },
            uniquingKeysWith: { current, candidate in better(candidate, than: current) }
        )
        recalculateRecords()
        waterByDay = snapshot.waterByDay
        routines = (snapshot.routines ?? []).filter { !deletedRoutineIDs.contains($0.id) }
        unitPreference = snapshot.unitPreference ?? .kg
        currentWeightUnit = unitPreference
        bodyWeight = snapshot.bodyWeight
        currentBodyWeight = snapshot.bodyWeight ?? 0
        nutritionPassport = snapshot.nutritionPassport?.normalized
        timerMax = snapshot.timerPreset.flatMap { restTimerPresets.contains($0) ? $0 : nil } ?? 90
        timerSecs = timerMax
        hasOnboarded = snapshot.hasOnboarded ?? false
        showingOnboarding = !hasOnboarded && !suppressOnboarding

        if let draft = snapshot.draft {
            todayExercises = draft.exercises
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
        updateLiveActivity(clearedDraft: snapshot.draft == nil)
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
            guard let cloudID = cloud.cloudID, !deletedCloudSessionIDs.contains(cloudID) else { continue }
            if sessions.contains(where: { $0.cloudID == cloudID || $0.id.uuidString.lowercased() == cloudID }) { continue }
            sessions.append(cloud)
        }
        sessions.sort { $0.createdAt > $1.createdAt }
        recalculateRecords()
    }

    private func applyRecords(from session: WorkoutSession) {
        for exercise in session.exercises {
            // Timed work carries no weight and its `reps` are seconds, so a
            // 30-minute bike ride would land in Personal Records as "BW x 1800".
            // ponytail: timed work earns no PR at all; add a duration comparator
            // ("longest hold", "furthest row") if cardio records are wanted.
            guard !exercise.timed else { continue }
            for set in exercise.sets where set.isWorkingSet {
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

    /// Whether finishing this set just broke a record — announced once.
    ///
    /// `personalRecords` only refreshes when a session is saved, so all workout
    /// long it holds the *pre-workout* best. That is the right thing to beat,
    /// but it also means every back-off set at the same new weight beats it too
    /// and re-announces the same PR. Only the first set to clear the bar counts.
    ///
    /// An exercise with no record yet is not a PR either: there is nothing to
    /// beat, and on a fresh install that fired on literally every set.
    private func isNewPR(exercise: ActiveExercise, set: WorkoutSet) -> Bool {
        // Must match `applyRecords`, or the toast celebrates a PR that is never
        // recorded — including its warm-up exclusion.
        guard !exercise.timed, let pr = personalRecords[exercise.name],
              beats(pr, set) else { return false }
        return !exercise.sets.contains { $0.id != set.id && $0.done && beats(pr, $0) }
    }

    private func beats(_ pr: PersonalRecord, _ set: WorkoutSet) -> Bool {
        guard set.type?.countsAsVolume ?? true,
              let reps = decimalEntry(set.reps), EntryLimit.reps.contains(reps) else { return false }
        let weight = typedWeightKg(set) ?? 0
        return weight > pr.weight || (weight == pr.weight && reps > pr.reps)
    }

    /// Input→storage boundary: typed weight strings are in the display unit;
    /// convert to canonical KG here, the one place drafts become LoggedSets.
    ///
    /// `bodyweight` means weight is *optional*, not forbidden — loaded lunges,
    /// weighted pull-ups and dips log a weight; leaving the field blank keeps
    /// the set bodyweight. Timed sets have no weight field at all.
    private func loggedSet(for exercise: ActiveExercise, set: WorkoutSet) -> LoggedSet? {
        guard set.done, let reps = decimalEntry(set.reps), reps > 0 else { return nil }
        if exercise.timed {
            // Durations are stored in seconds; cardio machines type minutes.
            guard let seconds = boundedInteger(exercise.usesMinutes ? reps * 60 : reps,
                                               in: EntryLimit.timedSeconds),
                  exercise.usesMinutes || Double(seconds) == reps else { return nil }
            return LoggedSet(weight: nil, reps: Double(seconds), type: set.type, remark: normalizedRemark(set.remark))
        }
        guard EntryLimit.reps.contains(reps) else { return nil }
        guard let weight = typedWeightKg(set) else {
            return exercise.bodyweight ? LoggedSet(weight: nil, reps: reps, type: set.type, remark: normalizedRemark(set.remark)) : nil
        }
        return LoggedSet(weight: weight, reps: reps, type: set.type, remark: normalizedRemark(set.remark))
    }

    /// Typed weight in canonical KG, or nil when the field is blank/invalid.
    private func typedWeightKg(_ set: WorkoutSet) -> Double? {
        guard let weight = decimalEntry(set.weight), weight >= 0 else { return nil }
        let kg = displayWeightToKg(weight)
        return kg.isFinite && EntryLimit.setWeightKg.contains(kg) ? kg : nil
    }

    private func validationMessage(for exercise: ActiveExercise) -> String {
        if exercise.timed {
            return exercise.usesMinutes
                ? "Enter up to 1,440 minutes before marking the set done"
                : "Enter whole seconds up to 86,400 before marking the set done"
        }
        if exercise.bodyweight {
            return "Enter 0.5–1,000 reps before marking the set done"
        }
        let weightRange = unitPreference == .kg ? "0–1,000 kg" : "0–2,205 lb"
        return "Enter \(weightRange) and 0.5–1,000 reps before marking the set done"
    }

    private func markFailed(_ id: WorkoutSession.ID, error: Error) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].syncState = .failed
        }
        syncMessage = "Saved locally. Backup failed: \(error.localizedDescription)"
        persistAll()
        scheduleSyncRetry()
    }

    /// Internal (not private) so the Live Activity bridge in another file can
    /// persist after folding in Lock-Screen edits.
    func persistDraft() {
        persistAll(draft: currentDraft)
    }

    private func persistAll(clearDraft: Bool = false, draft: WorkoutDraft? = nil, replacingBackup: Bool = false) {
        guard storageError == nil else { return }
        let snapshot = makeSnapshot(clearDraft: clearDraft, draft: draft)
        let ownerID = activeStoreOwnerID
        let previous = saveTask
        saveTask = Task { [localStore] in
            await previous?.value
            do {
                try await localStore.save(snapshot, ownerID: ownerID, replacingBackup: replacingBackup)
                self.failedSave = nil
                self.storageError = nil
            } catch {
                self.failedSave = (snapshot, ownerID, replacingBackup)
                self.storageError = error.localizedDescription
            }
        }
        updateLiveActivity(clearedDraft: clearDraft)
    }

    func retryStorage() async {
        guard storageError != nil, !isRetryingStorage else { return }
        isRetryingStorage = true
        defer { isRetryingStorage = false }
        await saveTask?.value
        if let failedSave {
            do {
                try await localStore.save(failedSave.snapshot, ownerID: failedSave.ownerID,
                                          replacingBackup: failedSave.replacingBackup)
                self.failedSave = nil
                storageError = nil
                await resumeForegroundSync()
            } catch { storageError = error.localizedDescription }
        } else {
            // A read/migration failure must be retried as a read, never by
            // writing the empty initial in-memory state over the saved file.
            storageError = nil
            isBooting = true
            await boot()
        }
    }

    private func makeSnapshot(clearDraft: Bool = false, draft: WorkoutDraft? = nil) -> AppSnapshot {
        AppSnapshot(
            sessions: sessions,
            personalRecords: Array(personalRecords.values),
            waterByDay: waterByDay,
            draft: clearDraft ? nil : (draft ?? currentDraft),
            unitPreference: unitPreference,
            hasOnboarded: hasOnboarded,
            timerPreset: timerMax,
            routines: routines,
            bodyWeight: bodyWeight,
            nutritionPassport: nutritionPassport,
            deletedCloudSessionIDs: deletedCloudSessionIDs,
            pendingCloudSessionDeletions: pendingCloudSessionDeletions,
            deletedRoutineIDs: deletedRoutineIDs,
            pendingRoutineDeletions: pendingRoutineDeletions,
            pendingPRSync: pendingPRSync,
            pendingWorkoutWipe: pendingWorkoutWipe
        )
    }

    private var currentDraft: WorkoutDraft? {
        guard hasActiveWorkout else { return nil }
        return WorkoutDraft(
            exercises: todayExercises,
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
        selectedDay = nil
        selectedSplit = nil
        workoutStep = .split
        resetTimer()
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
//  Populates the in-memory store with realistic data so the five tabs and the
//  Lock-Screen Live Activity look "lived in" for capture. Gated behind launch
//  arguments AND `#if DEBUG`, so it is impossible to reach in a release build,
//  and it never writes to disk (no `persistAll`), so it can't clobber real data.
//
//  Enable via simctl, e.g.:
//    xcrun simctl launch booted com.parthjadhav.ironlog -seedDemo YES -seedTab stats
//    xcrun simctl launch booted com.parthjadhav.ironlog -seedDemo YES -seedActive YES -seedTab log
// ─────────────────────────────────────────────────────────────
extension AppState {
    func applyIronFuelUITestSeedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "UITest_IronFuelPassport"),
              arguments.indices.contains(index + 1) else { return }
        switch arguments[index + 1] {
        case "ready", "routed", "omnivore":
            nutritionPassport = NutritionPassport(
                sexContext: .preferNotToSay,
                goals: [.supportTraining, .steadyEnergy],
                dietaryIdentity: arguments[index + 1] == "omnivore" ? .omnivore : .vegetarian,
                allergies: ["peanut"],
                neverSuggest: ["mushroom"],
                preferredCuisines: ["Indian"],
                budget: .value,
                maxCookingMinutes: 25,
                cookingAbility: .basic,
                mealsPerDay: 4,
                isMinor: arguments[index + 1] == "routed",
                safetyReviewedAt: Date()
            )
        case "incomplete":
            nutritionPassport = NutritionPassport(
                sexContext: .preferNotToSay,
                goals: [.supportTraining]
            )
        default:
            break
        }
    }

    func applyDemoSeedIfRequested() {
        let defaults = UserDefaults.standard
        guard !ProcessInfo.processInfo.arguments.contains("UITest_ResetStore") else { return }
        guard defaults.bool(forKey: "seedDemo") else { return }

        // Clear any stale draft the local store may have restored, so every
        // non-active screen (Workouts / History / Stats) starts clean.
        resetActiveWorkout()
        showingOnboarding = false

        // A cloud-signed-in athlete reads better than "Local Athlete" for marketing.
        user = UserProfile(id: "demo", email: "alex@ironlog.app", fullName: "Alex Carter")
        syncMessage = "Synced with Supabase"
        // Body weight so the Run tab's calorie estimate is populated.
        bodyWeight = 70
        currentBodyWeight = 70
        nutritionPassport = NutritionPassport(
            sexContext: .preferNotToSay,
            goals: [.supportTraining, .improveRecovery, .steadyEnergy],
            targetSource: .none,
            dietaryIdentity: .vegetarian,
            allergies: ["peanut"],
            neverSuggest: ["mushroom"],
            preferredCuisines: ["Indian", "Mediterranean"],
            budget: .value,
            maxCookingMinutes: 25,
            cookingAbility: .basic,
            mealsPerDay: 4,
            availableFoods: ["rice", "dal", "yogurt"],
            safetyReviewedAt: Date()
        )

        let calendar = Calendar.current
        func day(_ offset: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return calendar.date(bySettingHour: 18, minute: 20, second: 0, of: base) ?? base
        }
        func exercise(_ name: String, _ sets: [(Double?, Double)], bodyweight: Bool = false) -> LoggedExercise {
            LoggedExercise(name: name, bodyweight: bodyweight, timed: false,
                           sets: sets.map { LoggedSet(weight: $0.0, reps: $0.1) })
        }
        func session(_ offset: Int, muscle: String, split: String, note: String? = nil,
                     _ exercises: [LoggedExercise]) -> WorkoutSession {
            WorkoutSession(createdAt: day(offset), muscle: muscle, split: split,
                           note: note, exercises: exercises, syncState: .synced)
        }
        func cardio(_ offset: Int, _ activity: CardioActivity) -> WorkoutSession {
            WorkoutSession(createdAt: day(offset), split: activity.kind.label,
                           exercises: [], syncState: .synced, activity: activity)
        }

        sessions = [
            cardio(0, CardioActivity(kind: .run, duration: 1_800, distance: 5_000, route: [],
                                     elevationGain: 45, terrain: .trail, calories: 401)),
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
            session(8, muscle: "shoulders", split: "Single Muscle", note: "Delts on fire.", [
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
        case "run": selectedTab = .run
        case "history":
            progressSection = .history
            selectedTab = .progress
        case "stats", "progress":
            progressSection = .stats
            selectedTab = .progress
        case "ironfuel": selectedTab = .ironFuel
        default: break
        }
    }
}
#endif
