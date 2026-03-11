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
            ? 'Best: ' + pr.weight + 'kg×' + pr.reps
            : 'Best: ' + (ex.timed ? pr.reps + 's' : 'BW×' + pr.reps))
        : '';

      return '<div class="ex-card" onclick="this.querySelector(\'.ex-tip\').style.display=this.querySelector(\'.ex-tip\').style.display===\'block\'?\'none\':\'block\'">' +
        '<div class="ex-card-top">' +
          '<div style="flex:1">' +
            '<div class="ex-card-name">' + ex.name + '</div>' +
            '<div class="ex-card-meta">' +
              ex.sets + ' sets × ' + ex.reps + ' ' + (ex.timed ? 'sec' : 'reps') +
              (isBodyweight ? ' <span class="bw-badge">Bodyweight</span>' : '') +
              (prText ? ' · <strong style="color:var(--accent)">' + prText + '</strong>' : '') +
            '</div>' +
          '</div>' +
          (pr ? '<span class="pr-tag">' + ICON_TROPHY + ' PR</span>' : '') +
        '</div>' +
        '<div class="ex-tip">💡 ' + ex.tip + '</div>' +
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

// ── Start Workout ──────────────────────────────────────────────
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
