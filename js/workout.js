// ─────────────────────────────────────────────────────────────
//  WORKOUTS PAGE
// ─────────────────────────────────────────────────────────────
function renderSplits() {
  document.getElementById('split-pills').innerHTML = SPLITS.map(s =>
    `<button class="pill ${s === state.selectedSplit ? 'active' : ''}" onclick="selectSplit('${s}')">${s}</button>`
  ).join('');
}

function renderMuscles() {
  document.getElementById('muscle-grid').innerHTML = MUSCLES.map(m =>
    `<button class="muscle-btn ${m.id === state.selectedMuscle ? 'selected' : ''}" onclick="selectMuscle('${m.id}')">
      <span class="icon">${m.icon}</span>${m.label}
    </button>`
  ).join('');
}

function selectSplit(s) {
  state.selectedSplit = s;
  renderSplits();
  if (state.selectedMuscle) showSuggestions();
}

function selectMuscle(id) {
  state.selectedMuscle = id;
  renderMuscles();
  showSuggestions();
}

function showSuggestions() {
  const sec = document.getElementById('suggestions-section');
  sec.style.display = 'block';

  const m = MUSCLES.find(x => x.id === state.selectedMuscle);
  let day = '';
  if (state.selectedSplit === 'PPL')         day = ' — ' + (PPL_DAY[state.selectedMuscle] || '');
  if (state.selectedSplit === 'Upper/Lower') day = ' — ' + (UL_DAY[state.selectedMuscle] || '');

  document.getElementById('sug-sub').innerHTML = m.icon + ' ' + m.label + day;
  document.getElementById('split-tag').textContent = state.selectedSplit;

  const exercises = WORKOUTS[state.selectedSplit][state.selectedMuscle] || [];

  document.getElementById('ex-list').innerHTML = exercises.map(ex => {
    const pr = state.prs[ex.name];
    const isBodyweight = ex.bodyweight || ex.timed;
    const prText = pr
      ? (pr.weight > 0
          ? `Best: ${pr.weight}kg×${pr.reps}`
          : `Best: ${ex.timed ? pr.reps + 's' : 'BW×' + pr.reps}`)
      : '';

    return `<div class="ex-card" onclick="this.querySelector('.ex-tip').style.display=this.querySelector('.ex-tip').style.display==='block'?'none':'block'">
      <div class="ex-card-top">
        <div style="flex:1">
          <div class="ex-card-name">${ex.name}</div>
          <div class="ex-card-meta">
            ${ex.sets} sets × ${ex.reps} ${ex.timed ? 'sec' : 'reps'}
            ${isBodyweight ? '<span class="bw-badge">Bodyweight</span>' : ''}
            ${prText ? ` · <strong style="color:var(--accent)">${prText}</strong>` : ''}
          </div>
        </div>
        ${pr ? `<span class="pr-tag">${ICON_TROPHY} PR</span>` : ''}
      </div>
      <div class="ex-tip">💡 ${ex.tip}</div>
    </div>`;
  }).join('');

  sec.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function startWorkout() {
  if (!state.selectedMuscle) return;
  const exercises = WORKOUTS[state.selectedSplit][state.selectedMuscle] || [];
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
