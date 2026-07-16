// ─────────────────────────────────────────────────────────────
//  GLOBAL CLIENT + USER
// ─────────────────────────────────────────────────────────────
let sb, currentUser;

// ─────────────────────────────────────────────────────────────
//  APP STATE
// ─────────────────────────────────────────────────────────────
let state = {
  selectedSplit:   null,
  selectedDay:     null,
  selectedMuscle:  null,
  workoutStep:     'split',
  todayExercises:  [],
  timerRunning:    false,
  timerSecs:       90,
  timerMax:        90,
  timerInterval:   null,
  history:         [],
  water:           0,
  prs:             {},
  showAddExerciseForm: false,
  addExMode:           'reps',
  newExName:           '',
};

// ─────────────────────────────────────────────────────────────
//  SHARED UTILITIES
// ─────────────────────────────────────────────────────────────
function today() {
  return new Date().toDateString();
}

function getMondayOfWeek(d) {
  const m = new Date(d);
  m.setDate(d.getDate() - (d.getDay() === 0 ? 6 : d.getDay() - 1));
  m.setHours(0, 0, 0, 0);
  return m;
}

let _toastTimer;
function toast(msg) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => el.classList.remove('show'), 2800);
}

function updateHeaderDate() {
  const now = new Date();
  const d  = document.getElementById('hdr-day');
  const dt = document.getElementById('hdr-date');
  if (d)  d.textContent  = now.toLocaleDateString('en-US', { weekday: 'long' });
  if (dt) dt.textContent = now.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

// Escape a string for safe interpolation into an HTML attribute value.
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// Keep the in-progress "Add Exercise" name in state so re-renders (mode toggle,
// marking a set done, etc.) don't wipe what the user has typed.
function setNewExName(v) {
  state.newExName = v;
}

// True when the current workout has anything worth preserving — a logged/entered
// set or a session note. Used to warn before a new workout overwrites it.
function workoutHasUnsavedData() {
  const noteEl = document.getElementById('session-note');
  const hasNote = noteEl && noteEl.value.trim() !== '';
  const hasSets = state.todayExercises.some(ex =>
    ex.sets.some(s => s.done || s.weight !== '' || s.reps !== ''));
  return Boolean(hasSets || hasNote);
}

// ─────────────────────────────────────────────────────────────
//  WEIGHT / PERFORMANCE HELPERS  (shared logic — see CLAUDE design rules)
//  Weight is stored canonically in KG everywhere. formatWeight is the single
//  chokepoint that turns a KG value into a display string, so a future kg/lb
//  toggle is a one-function flip. Unit is fixed to kg for now.
// ─────────────────────────────────────────────────────────────

// Cleaned numeric portion of a KG weight: integer when whole, else 1 decimal.
// (Mirrors the iOS `clean(_:)` helper so both clients render identically.)
function cleanWeight(kg) {
  const n = Number(kg);
  if (!isFinite(n)) return '';
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

// Display string for a KG weight, e.g. "60 kg" / "62.5 kg".
function formatWeight(kg) {
  const s = cleanWeight(kg);
  return s === '' ? '' : s + ' kg';
}

// Most recent prior session containing `exerciseName` (exact name match).
// Returns that session's exercise object { name, sets:[{weight, reps}] }, or
// null when the exercise has no history. `state.history` is newest-first, so
// callers map by set index and fall back to the last set.
function lastPerformance(exerciseName) {
  for (const session of state.history) {
    const ex = session.exercises.find(e => e.name === exerciseName);
    if (ex && ex.sets.length) return ex;
  }
  return null;
}

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
