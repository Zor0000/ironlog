// ─────────────────────────────────────────────────────────────
//  GLOBAL CLIENT + USER
// ─────────────────────────────────────────────────────────────
let sb, currentUser;

// ─────────────────────────────────────────────────────────────
//  APP STATE
// ─────────────────────────────────────────────────────────────
let state = {
  selectedSplit:   'PPL',
  selectedMuscle:  null,
  todayExercises:  [],
  timerRunning:    false,
  timerSecs:       90,
  timerMax:        90,
  timerInterval:   null,
  history:         [],
  water:           0,
  prs:             {},
  showAddExerciseForm: false,
  _addExMode:          'reps',
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
