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
