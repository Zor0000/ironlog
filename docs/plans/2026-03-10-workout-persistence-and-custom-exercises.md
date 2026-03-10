# Workout Persistence, Save Fix & Custom Exercises Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix workout data loss on screen-off/app-resume and add the ability to append custom exercises to any active session (or start a fully free-form session).

**Architecture:** Persist `state.todayExercises + selectedMuscle + selectedSplit` to `localStorage` key `il_workout_draft` on every mutation. Restore on `bootApp()`. Guard `onAuthStateChange` so token refreshes don't re-run boot and wipe state. Add inline "+ Add Exercise" form rendered inside `renderTodayLog()`.

**Tech Stack:** Vanilla JS (global scope, no modules), localStorage, Supabase JS SDK v2, static HTML/CSS PWA.

---

## Task 1: Add `saveWorkoutDraft()` and `loadWorkoutDraft()` to `state.js`

**Files:**
- Modify: `js/state.js` (append after the `updateHeaderDate` function)

**Step 1: Add the two draft helpers**

Append to the bottom of `js/state.js`:

```js
// ─────────────────────────────────────────────────────────────
//  WORKOUT DRAFT PERSISTENCE
// ─────────────────────────────────────────────────────────────
function saveWorkoutDraft() {
  if (state.todayExercises.length) {
    localStorage.setItem('il_workout_draft', JSON.stringify({
      exercises: state.todayExercises,
      muscle:    state.selectedMuscle,
      split:     state.selectedSplit,
    }));
  } else {
    localStorage.removeItem('il_workout_draft');
  }
}

function loadWorkoutDraft() {
  const raw = localStorage.getItem('il_workout_draft');
  if (!raw) return;
  try {
    const d = JSON.parse(raw);
    if (Array.isArray(d.exercises) && d.exercises.length) {
      state.todayExercises = d.exercises;
      if (d.muscle) state.selectedMuscle = d.muscle;
      if (d.split)  state.selectedSplit  = d.split;
    }
  } catch (e) {
    console.warn('Failed to restore workout draft:', e);
    localStorage.removeItem('il_workout_draft');
  }
}
```

**Step 2: Manual verify**

Open browser console on the app. Run:
```js
state.todayExercises = [{ name: 'Test', sets: [], expanded: true }];
saveWorkoutDraft();
console.log(localStorage.getItem('il_workout_draft')); // should print JSON
loadWorkoutDraft();
console.log(state.todayExercises[0].name); // should print "Test"
```
Expected: both pass without errors.

**Step 3: Commit**

```bash
git add js/state.js
git commit -m "feat: add saveWorkoutDraft and loadWorkoutDraft helpers"
```

---

## Task 2: Fix `bootApp()` and `onAuthStateChange` in `app.js`

**Files:**
- Modify: `js/app.js`

**Step 1: Call `loadWorkoutDraft()` in `bootApp()`**

In `bootApp()`, find the line:
```js
  state.water = parseInt(localStorage.getItem('il_water_' + today()) || '0');
```
Add `loadWorkoutDraft();` on the next line, before `await loadHistory()`:
```js
  state.water = parseInt(localStorage.getItem('il_water_' + today()) || '0');
  loadWorkoutDraft();
```

**Step 2: Guard `onAuthStateChange` to prevent re-boot on token refresh**

Find the existing listener block:
```js
  sb.auth.onAuthStateChange(async (_event, session) => {
    if (session?.user) {
      document.getElementById('auth-screen').classList.remove('visible');
      await bootApp(session.user);
    } else {
      document.getElementById('app').classList.remove('visible');
      showAuth();
    }
  });
```

Replace it with:
```js
  sb.auth.onAuthStateChange(async (event, session) => {
    if (event === 'SIGNED_IN' && session?.user && !currentUser) {
      document.getElementById('auth-screen').classList.remove('visible');
      await bootApp(session.user);
    } else if (event === 'SIGNED_OUT') {
      currentUser = null;
      document.getElementById('app').classList.remove('visible');
      showAuth();
    }
  });
```

The `!currentUser` guard prevents re-running `bootApp()` on `TOKEN_REFRESHED` events (which fire when the screen wakes up and Supabase silently refreshes the JWT).

**Step 3: Manual verify — simulate screen-off reset**

1. Start a workout (pick a muscle, click "Start This Workout")
2. Open DevTools → Application → Local Storage → confirm `il_workout_draft` exists
3. Hard-reload the page (Ctrl+Shift+R) — simulates the browser resuming
4. Navigate to Today tab
5. Expected: in-progress workout is still there

**Step 4: Commit**

```bash
git add js/app.js
git commit -m "fix: restore workout draft on boot, guard auth re-boot on token refresh"
```

---

## Task 3: Call `saveWorkoutDraft()` in `workout.js` after `startWorkout()`

**Files:**
- Modify: `js/workout.js`

**Step 1: Save draft when a workout begins**

In `startWorkout()`, find the last line before the closing `}`:
```js
  toast('Workout started! 💪');
```
Add `saveWorkoutDraft();` before it:
```js
  saveWorkoutDraft();
  toast('Workout started! 💪');
```

**Step 2: Manual verify**

Start a workout. Check `localStorage.getItem('il_workout_draft')` in console — should immediately contain the exercises.

**Step 3: Commit**

```bash
git add js/workout.js
git commit -m "feat: persist workout draft immediately on startWorkout"
```

---

## Task 4: Call `saveWorkoutDraft()` on set mutations in `log.js`; clear draft on save

**Files:**
- Modify: `js/log.js`

**Step 1: Save draft after `updateSet()`**

Find the end of `updateSet()`:
```js
  state.todayExercises[ei].sets[si][field] = val;
}
```
Add `saveWorkoutDraft();` before the closing brace:
```js
  state.todayExercises[ei].sets[si][field] = val;
  saveWorkoutDraft();
}
```

**Step 2: Save draft after `addSet()`**

Find:
```js
function addSet(ei) {
  state.todayExercises[ei].sets.push({ weight: '', reps: '', done: false });
  renderTodayLog();
}
```
Add `saveWorkoutDraft();` before `renderTodayLog()`:
```js
function addSet(ei) {
  state.todayExercises[ei].sets.push({ weight: '', reps: '', done: false });
  saveWorkoutDraft();
  renderTodayLog();
}
```

**Step 3: Save draft after `toggleDone()`**

Find the end of `toggleDone()` just before `renderTodayLog();`:
```js
  renderTodayLog();
}
```
Add `saveWorkoutDraft();` before it:
```js
  saveWorkoutDraft();
  renderTodayLog();
}
```

**Step 4: Clear draft on successful save in `finishWorkout()`**

Find in `finishWorkout()` the success block:
```js
    state.todayExercises = [];
    document.getElementById('session-note').value = '';
    renderTodayLog();
```
Add `localStorage.removeItem('il_workout_draft');` after clearing state:
```js
    state.todayExercises = [];
    localStorage.removeItem('il_workout_draft');
    document.getElementById('session-note').value = '';
    renderTodayLog();
```

**Step 5: Manual verify**

1. Start a workout, log a set weight and reps
2. Check `il_workout_draft` in localStorage — should contain filled-in set data
3. Finish & Save — check `il_workout_draft` is gone from localStorage

**Step 6: Commit**

```bash
git add js/log.js
git commit -m "feat: save draft on every set mutation, clear on save"
```

---

## Task 5: Add "Start free workout" to empty Log state

**Files:**
- Modify: `js/log.js`

**Step 1: Add `startFreeWorkout()` function**

Append to the bottom of `js/log.js`:

```js
function startFreeWorkout() {
  state.todayExercises = []; // blank slate
  state.showAddExerciseForm = true;
  saveWorkoutDraft();
  renderTodayLog();
  toast('Free workout started! Add your exercises below.');
}
```

**Step 2: Update the empty state in `renderTodayLog()`**

Find the empty-state HTML string:
```js
    c.innerHTML = `<div class="empty"><div class="empty-icon">${ICON_DUMBBELL}</div><div class="empty-text">No workout started yet.<br>Go to <strong>Workouts</strong> tab and pick your muscles!</div></div>`;
```
Replace with:
```js
    c.innerHTML = `<div class="empty">
      <div class="empty-icon">${ICON_DUMBBELL}</div>
      <div class="empty-text">No workout started yet.<br>Go to <strong>Workouts</strong> tab and pick your muscles!</div>
      <button class="btn btn-primary" style="margin-top:16px" onclick="startFreeWorkout()">＋ Start Free Workout</button>
    </div>`;
```

**Step 3: Manual verify**

Navigate to Today tab with no workout active — "Start Free Workout" button appears. Tap it — empty exercise list with add-exercise form visible (form added in Task 6).

**Step 4: Commit**

```bash
git add js/log.js
git commit -m "feat: add Start Free Workout button to empty log state"
```

---

## Task 6: Add "+ Add Exercise" inline form in `log.js`

**Files:**
- Modify: `js/log.js`

**Step 1: Add `state.showAddExerciseForm` initializer**

In `js/state.js`, add to the `state` object:
```js
  showAddExerciseForm: false,
```
(Add it after the `prs: {}` line.)

**Step 2: Add the "+ Add Exercise" button + inline form to `renderTodayLog()`**

In `renderTodayLog()`, find the closing of the exercise list map, just before the closing template literal of `c.innerHTML`. The current code ends with:
```js
    ${state.todayExercises.map((ex, ei) => { ... }).join('')}`;
```

After the `.join('')}` and before the closing backtick, append:

```js
    <div style="margin-top:12px">
      ${state.showAddExerciseForm ? `
      <div class="card" style="padding:16px;margin-bottom:8px" id="add-ex-form">
        <div class="card-title" style="margin-bottom:12px">Add Exercise</div>
        <input id="new-ex-name" class="set-inp" type="text" placeholder="Exercise name"
          style="width:100%;padding:10px 12px;margin-bottom:12px;font-size:14px;border-radius:10px;border:1px solid var(--border);background:var(--surface2);color:var(--text)">
        <div style="display:flex;gap:8px;margin-bottom:14px">
          <button id="mode-reps"   class="pill ${state._addExMode !== 'weighted' ? 'active' : ''}" onclick="setAddExMode('reps')">Reps only</button>
          <button id="mode-weight" class="pill ${state._addExMode === 'weighted' ? 'active' : ''}" onclick="setAddExMode('weighted')">Weight + Reps</button>
        </div>
        <div style="display:flex;gap:8px">
          <button class="btn btn-primary" style="flex:1" onclick="confirmAddExercise()">Add</button>
          <button class="btn" style="flex:0 0 auto;background:var(--surface2)" onclick="cancelAddExercise()">✕</button>
        </div>
      </div>` : `
      <button class="add-set-btn" style="width:100%;padding:14px;font-size:14px" onclick="openAddExerciseForm()">＋ Add Exercise</button>`}
    </div>
```

**Step 3: Add the form handler functions**

Append to the bottom of `js/log.js`:

```js
function openAddExerciseForm() {
  state.showAddExerciseForm = true;
  state._addExMode = 'reps';
  renderTodayLog();
  document.getElementById('new-ex-name')?.focus();
}

function cancelAddExercise() {
  state.showAddExerciseForm = false;
  renderTodayLog();
}

function setAddExMode(mode) {
  state._addExMode = mode;
  renderTodayLog();
  document.getElementById('new-ex-name')?.focus();
}

function confirmAddExercise() {
  const nameEl = document.getElementById('new-ex-name');
  const name = nameEl?.value.trim();
  if (!name) { toast('Enter an exercise name first'); return; }

  const isWeighted = state._addExMode === 'weighted';
  state.todayExercises.push({
    name,
    bodyweight: !isWeighted,
    timed:      false,
    custom:     true,
    expanded:   true,
    sets:       [{ weight: '', reps: '', done: false }],
  });

  state.showAddExerciseForm = false;
  saveWorkoutDraft();
  renderTodayLog();
  // Show finish section since we now have exercises
  document.getElementById('finish-section').style.display = 'block';
  toast('Exercise added!');
}
```

**Step 4: Manual verify end-to-end**

1. Start a workout from Workouts tab (muscle picker flow)
2. Go to Today tab — see `+ Add Exercise` button at the bottom
3. Tap it — form expands with name input and two toggle pills
4. Type "Cable Curl", select "Weight + Reps", tap Add
5. New exercise appears in list with KG + REPS inputs
6. Tap "Reps only" mode — new exercise shows only REPS input
7. Mark sets done, tap "Finish & Save" — saves successfully
8. Check History — custom exercise appears in session

Also verify free-form path:
1. No active workout → Today tab → "Start Free Workout"
2. Form immediately open — add 2 exercises
3. Log sets, save — appears in history

**Step 5: Commit**

```bash
git add js/log.js js/state.js
git commit -m "feat: add inline custom exercise form with Reps only / Weight+Reps toggle"
```

---

## Final Smoke Test

Serve the app:
```bash
python -m http.server 8080
# then open http://localhost:8080
```

Checklist:
- [ ] Start workout → lock screen (or navigate away) → return → workout still there
- [ ] Add sets, toggle done → refresh page → sets still there
- [ ] Finish & Save → localStorage `il_workout_draft` removed
- [ ] `+ Add Exercise` visible during any active workout
- [ ] Custom exercise (reps-only) shows only REPS input
- [ ] Custom exercise (weighted) shows KG + REPS inputs
- [ ] "Start Free Workout" appears on empty Log page
- [ ] Free-form session saves correctly to History
