# Workout Page Wizard Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert the Workouts page from a single stacked view into a multi-step wizard with split-aware muscle filtering, PPL arms split into Triceps/Biceps, and a new "Single Muscle" split type.

**Architecture:** Replace the three static HTML sections in `index.html` with a single container. A new `renderWorkoutStep()` function in `workout.js` renders each wizard step based on `state.workoutStep`. The `SPLIT_DAYS` config in `data.js` controls which splits have a day-selection step and which muscles appear for each day. PPL's `arms` exercises are split into `triceps` and `biceps` keys.

**Tech Stack:** Vanilla JS (global scope, no modules), static HTML/CSS PWA, Supabase.

---

## Task 1: Add `SPLIT_DAYS` config and split PPL arms in `data.js`

**Files:**
- Modify: `js/data.js`

**Step 1: Add 'Single Muscle' to SPLITS and add SPLIT_DAYS config**

Find:
```js
const SPLITS = ['Full Body', 'PPL', 'Upper/Lower', 'Bro Split'];
```
Replace with:
```js
const SPLITS = ['Full Body', 'PPL', 'Upper/Lower', 'Bro Split', 'Single Muscle'];
```

Then find the `PPL_DAY` and `UL_DAY` constants (lines 49–64):
```js
// Split-day labels shown under muscle selection
const PPL_DAY = {
  chest:     'Push Day',
  shoulders: 'Push Day',
  arms:      'Push Day (Triceps) + Pull Day (Biceps)',
  back:      'Pull Day',
  legs:      'Leg Day',
  core:      'Any Day',
};
const UL_DAY = {
  chest:     'Upper Day',
  shoulders: 'Upper Day',
  arms:      'Upper Day',
  back:      'Upper Day',
  legs:      'Lower Day',
  core:      'Lower Day',
};
```

Replace the entire block with:
```js
// ─────────────────────────────────────────────────────────────
//  SPLIT → DAY → MUSCLE MAPPING
//  Splits listed here show a "day" step before muscle selection.
//  Splits NOT listed skip the day step and show all 6 default muscles.
// ─────────────────────────────────────────────────────────────
const SPLIT_DAYS = {
  'PPL': [
    { day: 'Push', muscles: ['chest', 'shoulders', 'triceps'] },
    { day: 'Pull', muscles: ['back', 'biceps'] },
    { day: 'Legs', muscles: ['legs', 'core'] },
  ],
  'Upper/Lower': [
    { day: 'Upper', muscles: ['chest', 'back', 'shoulders', 'arms'] },
    { day: 'Lower', muscles: ['legs', 'core'] },
  ],
};
```

**Step 2: Add Triceps and Biceps to MUSCLES array**

Find:
```js
const MUSCLES = [
  { id: 'chest',     label: 'Chest',     icon: MUSCLE_ICONS.chest },
  { id: 'back',      label: 'Back',      icon: MUSCLE_ICONS.back },
  { id: 'legs',      label: 'Legs',      icon: MUSCLE_ICONS.legs },
  { id: 'shoulders', label: 'Shoulders', icon: MUSCLE_ICONS.shoulders },
  { id: 'arms',      label: 'Arms',      icon: MUSCLE_ICONS.arms },
  { id: 'core',      label: 'Core',      icon: MUSCLE_ICONS.core },
];
```
Replace with:
```js
const MUSCLES = [
  { id: 'chest',     label: 'Chest',     icon: MUSCLE_ICONS.chest },
  { id: 'back',      label: 'Back',      icon: MUSCLE_ICONS.back },
  { id: 'legs',      label: 'Legs',      icon: MUSCLE_ICONS.legs },
  { id: 'shoulders', label: 'Shoulders', icon: MUSCLE_ICONS.shoulders },
  { id: 'arms',      label: 'Arms',      icon: MUSCLE_ICONS.arms },
  { id: 'triceps',   label: 'Triceps',   icon: MUSCLE_ICONS.arms },
  { id: 'biceps',    label: 'Biceps',    icon: MUSCLE_ICONS.arms },
  { id: 'core',      label: 'Core',      icon: MUSCLE_ICONS.core },
];
```

**Step 3: Split PPL arms into triceps and biceps**

Find the PPL `arms` key (line 128):
```js
    arms: [ // Triceps on Push Day + Biceps on Pull Day (both shown)
      { name: 'Tricep Pushdown (Cable)',    sets: 3, reps: '12–15', tip: 'Push Day — Triceps. Lock elbows at sides. Push all the way to full extension. Rope or straight bar.' },
      { name: 'Overhead Tricep Extension',  sets: 3, reps: '12',    tip: 'Push Day — Triceps. Dumbbell overhead. Lower slowly behind head. Best for long tricep head stretch.' },
      { name: 'Tricep Dips',                sets: 3, reps: '10–15', tip: 'Push Day — Triceps. Stay upright for tricep focus. Elbows back. Control the descent.', bodyweight: true },
      { name: 'Barbell / EZ-Bar Curl',      sets: 3, reps: '10–12', tip: 'Pull Day — Biceps. Heavy and strict. No swinging. Elbows pinned at sides. Full range of motion.' },
      { name: 'Hammer Curl',                sets: 3, reps: '10–12', tip: 'Pull Day — Biceps. Neutral grip. Works brachialis for arm girth. Alternate arms, full range.' },
      { name: 'Incline Dumbbell Curl',      sets: 2, reps: '12',    tip: 'Pull Day — Biceps. Arms hang behind you on incline bench. Maximum stretch at bottom for peak.' },
    ],
```
Replace with:
```js
    triceps: [ // Push Day
      { name: 'Tricep Pushdown (Cable)',    sets: 3, reps: '12–15', tip: 'Lock elbows at sides. Push all the way to full extension. Rope or straight bar.' },
      { name: 'Overhead Tricep Extension',  sets: 3, reps: '12',    tip: 'Dumbbell overhead. Lower slowly behind head. Best for long tricep head stretch.' },
      { name: 'Tricep Dips',                sets: 3, reps: '10–15', tip: 'Stay upright for tricep focus. Elbows back. Control the descent.', bodyweight: true },
    ],
    biceps: [ // Pull Day
      { name: 'Barbell / EZ-Bar Curl',      sets: 3, reps: '10–12', tip: 'Heavy and strict. No swinging. Elbows pinned at sides. Full range of motion.' },
      { name: 'Hammer Curl',                sets: 3, reps: '10–12', tip: 'Neutral grip. Works brachialis for arm girth. Alternate arms, full range.' },
      { name: 'Incline Dumbbell Curl',      sets: 2, reps: '12',    tip: 'Arms hang behind you on incline bench. Maximum stretch at bottom for peak.' },
    ],
```

**Step 4: Add Single Muscle split (references Bro Split data)**

After the closing `},` of `'Bro Split': { ... },`, add:
```js
  // ── SINGLE MUSCLE ───────────────────────────────────────────
  // One muscle per day. Uses Bro Split exercises.
  'Single Muscle': null, // placeholder, resolved at runtime
```

Then after the closing `};` of the entire `WORKOUTS` object, add:
```js
// Single Muscle reuses Bro Split exercise data
WORKOUTS['Single Muscle'] = WORKOUTS['Bro Split'];
```

**Step 5: Commit**
```bash
git add js/data.js
git commit -m "feat: add SPLIT_DAYS config, split PPL arms, add Single Muscle split"
```

---

## Task 2: Add wizard state fields to `state.js`

**Files:**
- Modify: `js/state.js`

**Step 1: Add `selectedDay` and `workoutStep` to state object**

Find in the state object:
```js
  selectedSplit:   'PPL',
  selectedMuscle:  null,
```
Replace with:
```js
  selectedSplit:   null,
  selectedDay:     null,
  selectedMuscle:  null,
  workoutStep:     'split',
```

`workoutStep` values: `'split'` | `'day'` | `'muscle'` | `'workout'`
`selectedSplit` starts as `null` (no pre-selection — user must pick).

**Step 2: Commit**
```bash
git add js/state.js
git commit -m "feat: add selectedDay and workoutStep to state"
```

---

## Task 3: Simplify the Workouts page HTML in `index.html`

**Files:**
- Modify: `index.html`

**Step 1: Replace the Workouts page content with a single container**

Find the entire workouts page div (lines 57–80):
```html
    <div class="page active" id="page-workouts">
      <div>
        <div class="section-label">SPLIT TYPE</div>
        <div class="section-sub">Choose your training program</div>
        <div style="height:10px"></div>
        <div class="pills" id="split-pills"></div>
      </div>
      <div>
        <div class="section-label">MUSCLE GROUP</div>
        <div class="section-sub">Select today's focus</div>
        <div style="height:10px"></div>
        <div class="muscle-grid" id="muscle-grid"></div>
      </div>
      <div id="suggestions-section" style="display:none">
        <div style="display:flex;align-items:baseline;gap:10px;flex-wrap:wrap">
          <div class="section-label">SUGGESTED WORKOUT</div>
          <span class="chip" id="split-tag"></span>
        </div>
        <div class="section-sub" id="sug-sub"></div>
        <div style="height:10px"></div>
        <div id="ex-list"></div>
        <button class="btn btn-primary" onclick="startWorkout()">▶ Start This Workout</button>
      </div>
    </div>
```

Replace with:
```html
    <div class="page active" id="page-workouts">
      <div id="workout-wizard"></div>
    </div>
```

**Step 2: Commit**
```bash
git add index.html
git commit -m "refactor: simplify workouts page to single wizard container"
```

---

## Task 4: Rewrite `workout.js` as a wizard renderer

**Files:**
- Modify: `js/workout.js`

**Step 1: Replace entire file contents**

Replace the full contents of `js/workout.js` with:

```js
// ─────────────────────────────────────────────────────────────
//  WORKOUTS PAGE — WIZARD STEPS
// ─────────────────────────────────────────────────────────────

function renderWorkoutStep() {
  const c = document.getElementById('workout-wizard');
  if (!c) return;

  switch (state.workoutStep) {
    case 'split':   return renderStepSplit(c);
    case 'day':     return renderStepDay(c);
    case 'muscle':  return renderStepMuscle(c);
    case 'workout': return renderStepWorkout(c);
    default:        state.workoutStep = 'split'; return renderStepSplit(c);
  }
}

// ── Step 1: Pick Split ─────────────────────────────────────────
function renderStepSplit(c) {
  c.innerHTML = `
    <div class="section-label">SPLIT TYPE</div>
    <div class="section-sub">Choose your training program</div>
    <div style="height:14px"></div>
    <div class="pills" style="flex-direction:column">
      ${SPLITS.map(s => `
        <button class="pill" style="text-align:left;padding:14px 18px;font-size:14px"
          onclick="selectSplit('${s}')">${s}</button>
      `).join('')}
    </div>`;
}

function selectSplit(s) {
  state.selectedSplit = s;
  state.selectedDay = null;
  state.selectedMuscle = null;

  if (SPLIT_DAYS[s]) {
    state.workoutStep = 'day';
  } else {
    state.workoutStep = 'muscle';
  }
  renderWorkoutStep();
}

// ── Step 2: Pick Day (PPL / Upper-Lower only) ──────────────────
function renderStepDay(c) {
  const days = SPLIT_DAYS[state.selectedSplit] || [];
  c.innerHTML = `
    <button class="wizard-back" onclick="goBackToSplit()">← ${state.selectedSplit}</button>
    <div class="section-label">TRAINING DAY</div>
    <div class="section-sub">Select your training day</div>
    <div style="height:14px"></div>
    <div class="pills" style="flex-direction:column">
      ${days.map(d => `
        <button class="pill" style="text-align:left;padding:14px 18px;font-size:14px"
          onclick="selectDay('${d.day}')">${d.day}</button>
      `).join('')}
    </div>`;
}

function selectDay(day) {
  state.selectedDay = day;
  state.selectedMuscle = null;
  state.workoutStep = 'muscle';
  renderWorkoutStep();
}

function goBackToSplit() {
  state.workoutStep = 'split';
  state.selectedSplit = null;
  state.selectedDay = null;
  state.selectedMuscle = null;
  renderWorkoutStep();
}

// ── Step 3: Pick Muscle ────────────────────────────────────────
function renderStepMuscle(c) {
  const backLabel = state.selectedDay
    ? state.selectedDay + ' · ' + state.selectedSplit
    : state.selectedSplit;
  const backFn = state.selectedDay ? 'goBackToDay' : 'goBackToSplit';

  // Determine which muscles to show
  let muscleIds;
  if (SPLIT_DAYS[state.selectedSplit] && state.selectedDay) {
    const dayConfig = SPLIT_DAYS[state.selectedSplit].find(d => d.day === state.selectedDay);
    muscleIds = dayConfig ? dayConfig.muscles : [];
  } else {
    // Non-day splits: show the 6 default muscles (exclude triceps/biceps)
    muscleIds = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  }

  const muscles = muscleIds.map(id => MUSCLES.find(m => m.id === id)).filter(Boolean);

  c.innerHTML = `
    <button class="wizard-back" onclick="${backFn}()">← ${backLabel}</button>
    <div class="section-label">MUSCLE GROUP</div>
    <div class="section-sub">Select today's focus</div>
    <div style="height:14px"></div>
    <div class="muscle-grid">
      ${muscles.map(m => `
        <button class="muscle-btn" onclick="selectMuscle('${m.id}')">
          <span class="icon">${m.icon}</span>${m.label}
        </button>
      `).join('')}
    </div>`;
}

function selectMuscle(id) {
  state.selectedMuscle = id;
  state.workoutStep = 'workout';
  renderWorkoutStep();
}

function goBackToDay() {
  state.workoutStep = 'day';
  state.selectedDay = null;
  state.selectedMuscle = null;
  renderWorkoutStep();
}

// ── Step 4: Suggested Workout ──────────────────────────────────
function renderStepWorkout(c) {
  const backFn = SPLIT_DAYS[state.selectedSplit] ? 'goBackToMuscle' : 'goBackToMuscleNonDay';

  const m = MUSCLES.find(x => x.id === state.selectedMuscle);
  const dayLabel = state.selectedDay ? ' · ' + state.selectedDay : '';
  const contextChip = state.selectedSplit + dayLabel;

  const exercises = WORKOUTS[state.selectedSplit]?.[state.selectedMuscle] || [];

  c.innerHTML = `
    <button class="wizard-back" onclick="${backFn}()">← ${m?.label || 'Back'}</button>
    <div style="display:flex;align-items:baseline;gap:10px;flex-wrap:wrap">
      <div class="section-label">SUGGESTED WORKOUT</div>
      <span class="chip">${contextChip}</span>
    </div>
    <div class="section-sub">${m?.icon || ''} ${m?.label || ''}</div>
    <div style="height:10px"></div>
    ${exercises.map(ex => {
      const pr = state.prs[ex.name];
      const isBodyweight = ex.bodyweight || ex.timed;
      const prText = pr
        ? (pr.weight > 0
            ? 'Best: ' + pr.weight + 'kg\u00d7' + pr.reps
            : 'Best: ' + (ex.timed ? pr.reps + 's' : 'BW\u00d7' + pr.reps))
        : '';

      return '<div class="ex-card" onclick="this.querySelector(\\'.ex-tip\\').style.display=this.querySelector(\\'.ex-tip\\').style.display===\\'block\\'?\\'none\\':\\'block\\'">' +
        '<div class="ex-card-top">' +
          '<div style="flex:1">' +
            '<div class="ex-card-name">' + ex.name + '</div>' +
            '<div class="ex-card-meta">' +
              ex.sets + ' sets \u00d7 ' + ex.reps + ' ' + (ex.timed ? 'sec' : 'reps') +
              (isBodyweight ? ' <span class="bw-badge">Bodyweight</span>' : '') +
              (prText ? ' \u00b7 <strong style="color:var(--accent)">' + prText + '</strong>' : '') +
            '</div>' +
          '</div>' +
          (pr ? '<span class="pr-tag">' + ICON_TROPHY + ' PR</span>' : '') +
        '</div>' +
        '<div class="ex-tip">\ud83d\udca1 ' + ex.tip + '</div>' +
      '</div>';
    }).join('')}
    <button class="btn btn-primary" onclick="startWorkout()">▶ Start This Workout</button>`;
}

function goBackToMuscle() {
  state.workoutStep = 'muscle';
  state.selectedMuscle = null;
  renderWorkoutStep();
}

function goBackToMuscleNonDay() {
  state.workoutStep = 'muscle';
  state.selectedMuscle = null;
  renderWorkoutStep();
}

// ── Start Workout (unchanged logic) ────────────────────────────
function startWorkout() {
  if (!state.selectedMuscle) return;
  const exercises = WORKOUTS[state.selectedSplit]?.[state.selectedMuscle] || [];
  state.todayExercises = exercises.map(ex => ({
    ...ex,
    expanded: true,
    sets: Array(ex.sets).fill(null).map(() => ({ weight: '', reps: '', done: false })),
  }));
  renderTodayLog();
  showPage('log', document.querySelectorAll('.nav-btn')[1]);
  saveWorkoutDraft();
  toast('Workout started! 💪');
}
```

**Step 2: Commit**
```bash
git add js/workout.js
git commit -m "feat: rewrite workout page as multi-step wizard"
```

---

## Task 5: Add `.wizard-back` CSS rule to `styles.css`

**Files:**
- Modify: `css/styles.css`

**Step 1: Add the wizard-back button style**

Find the `.pill.active` rule:
```css
.pill.active { background:var(--accent); color:#000; border-color:var(--accent); font-weight:700; }
```

Add immediately after it:
```css
.wizard-back { background:none; border:none; color:var(--muted2); font-size:13px; font-family:'DM Sans',sans-serif; cursor:pointer; padding:4px 0; margin-bottom:10px; display:block; }
.wizard-back:active { color:var(--text); }
```

**Step 2: Commit**
```bash
git add css/styles.css
git commit -m "feat: add wizard-back button style"
```

---

## Task 6: Update `bootApp()` in `app.js` to use `renderWorkoutStep()`

**Files:**
- Modify: `js/app.js`

**Step 1: Replace `renderSplits()` and `renderMuscles()` with `renderWorkoutStep()`**

Find in `bootApp()`:
```js
  renderSplits();
  renderMuscles();
  renderTodayLog();
```
Replace with:
```js
  renderWorkoutStep();
  renderTodayLog();
```

**Step 2: Add `renderWorkoutStep()` call in `showPage()`**

Find:
```js
  if (name === 'log')     renderTodayLog();
```
Add after it:
```js
  if (name === 'workouts') renderWorkoutStep();
```

**Step 3: Commit**
```bash
git add js/app.js
git commit -m "feat: boot and navigate with renderWorkoutStep instead of renderSplits/renderMuscles"
```

---

## Task 7: Update `showSuggestions()` references and cleanup

**Files:**
- Modify: `js/workout.js` (already done — `showSuggestions` was removed in Task 4)

No action needed — `showSuggestions()`, `renderSplits()`, and `renderMuscles()` were all replaced in Task 4. `PPL_DAY` and `UL_DAY` were removed in Task 1. Verify no remaining references.

**Step 1: Search for stale references**

Run:
```bash
grep -rn "renderSplits\|renderMuscles\|showSuggestions\|PPL_DAY\|UL_DAY" js/ index.html
```
Expected: zero matches.

If any are found, remove them.

**Step 2: Commit (if changes needed)**
```bash
git add -A
git commit -m "chore: remove stale references to old workout functions"
```

---

## Task 8: Manual end-to-end verification

**Step 1: Serve the app**
```bash
python -m http.server 8080
```

**Step 2: Verify each flow**

Checklist:
- [ ] Step 1 shows all 5 splits (Full Body, PPL, Upper/Lower, Bro Split, Single Muscle)
- [ ] Selecting PPL → shows day step (Push, Pull, Legs)
- [ ] Push day → shows Chest, Shoulders, Triceps
- [ ] Pull day → shows Back, Biceps
- [ ] Legs day → shows Legs, Core
- [ ] Selecting Upper/Lower → shows day step (Upper, Lower)
- [ ] Upper → shows Chest, Back, Shoulders, Arms
- [ ] Lower → shows Legs, Core
- [ ] Selecting Full Body → skips day step → shows all 6 muscles
- [ ] Selecting Bro Split → skips day step → shows all 6 muscles
- [ ] Selecting Single Muscle → skips day step → shows all 6 muscles
- [ ] Single Muscle exercises match Bro Split exercises
- [ ] Workout step shows exercise cards with PR badges
- [ ] "Start This Workout" works and navigates to Log tab
- [ ] Back button works at every step without losing prior selections
- [ ] Back button from muscle → day (for PPL/UL) correctly returns to day step
- [ ] Back button from muscle → split (for non-day splits) correctly returns to split step
- [ ] Draft persistence still works (start workout → refresh → workout restored)
