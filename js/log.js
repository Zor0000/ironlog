// ─────────────────────────────────────────────────────────────
//  LOG PAGE
// ─────────────────────────────────────────────────────────────
function renderTodayLog() {
  const c = document.getElementById('log-content');
  const f = document.getElementById('finish-section');

  if (!state.todayExercises.length) {
    c.innerHTML = `<div class="empty">
      <div class="empty-icon">${ICON_DUMBBELL}</div>
      <div class="empty-text">No workout started yet.<br>Go to <strong>Workouts</strong> tab and pick your muscles!</div>
      <button class="btn btn-primary" style="margin-top:16px" onclick="startFreeWorkout()">＋ Start Free Workout</button>
    </div>`;
    f.style.display = 'none';
    return;
  }

  f.style.display = 'block';
  const m = MUSCLES.find(x => x.id === state.selectedMuscle);

  c.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px">
      <div class="section-label">TODAY</div>
      <span class="chip">${m?.icon || ''} ${m?.label || ''} · ${state.selectedSplit}</span>
    </div>
    ${state.todayExercises.map((ex, ei) => {
      const isBodyweight = ex.bodyweight || false;
      const isTimed      = ex.timed || false;
      const inputLabel   = isTimed ? 'SECS' : 'REPS';

      return `
      <div class="log-ex">
        <div class="log-ex-hdr" onclick="toggleLogEx(${ei})">
          <div>
            <div class="log-ex-name">
              ${ex.name}
              ${isBodyweight ? '<span class="bw-badge">Bodyweight</span>' : ''}
              ${isTimed ? '<span class="bw-badge">Timed</span>' : ''}
            </div>
            <div class="log-ex-prog">${ex.sets.filter(s => s.done).length}/${ex.sets.length} sets done</div>
          </div>
          <span style="color:var(--muted2);font-size:16px">${ex.expanded ? '▾' : '▸'}</span>
        </div>
        ${ex.expanded ? `<div class="log-ex-body">
          ${ex.sets.map((s, si) => `
            <div class="set-row">
              <div class="set-num">${si + 1}</div>
              ${!isBodyweight && !isTimed ? `
              <div class="inp-wrap">
                <div class="inp-lbl">KG</div>
                <input class="set-inp" type="text" inputmode="decimal" placeholder="0" value="${s.weight}"
                  onchange="updateSet(${ei},${si},'weight',this.value)">
              </div>` : ''}
              <div class="inp-wrap">
                <div class="inp-lbl">${inputLabel}</div>
                <input class="set-inp" type="text" inputmode="numeric" placeholder="0" value="${s.reps}"
                  onchange="updateSet(${ei},${si},'reps',this.value)">
              </div>
              <button class="done-btn ${s.done ? 'done' : ''}" onclick="toggleDone(${ei},${si})">${s.done ? '✓' : ''}</button>
            </div>`).join('')}
          <button class="add-set-btn" onclick="addSet(${ei})">＋ Add Set</button>
        </div>` : ''}
      </div>`;
    }).join('')}
    <div style="margin-top:12px">
      ${state.showAddExerciseForm ? `
      <div class="card" style="padding:16px;margin-bottom:8px" id="add-ex-form">
        <div class="card-title" style="margin-bottom:12px">Add Exercise</div>
        <input id="new-ex-name" class="set-inp" type="text" placeholder="Exercise name"
          style="width:100%;padding:10px 12px;margin-bottom:12px;font-size:14px;border-radius:10px;border:1px solid var(--border);background:var(--surface2);color:var(--text)">
        <div style="display:flex;gap:8px;margin-bottom:14px">
          <button id="mode-reps"   class="pill ${state.addExMode !== 'weighted' ? 'active' : ''}" onclick="setAddExMode('reps')">Reps only</button>
          <button id="mode-weight" class="pill ${state.addExMode === 'weighted' ? 'active' : ''}" onclick="setAddExMode('weighted')">Weight + Reps</button>
        </div>
        <div style="display:flex;gap:8px">
          <button class="btn btn-primary" style="flex:1" onclick="confirmAddExercise()">Add</button>
          <button class="btn" style="flex:0 0 auto;background:var(--surface2)" onclick="cancelAddExercise()">✕</button>
        </div>
      </div>` : `
      <button class="add-set-btn" style="width:100%;padding:14px;font-size:14px" onclick="openAddExerciseForm()">＋ Add Exercise</button>`}
    </div>`;
}

function toggleLogEx(ei) {
  state.todayExercises[ei].expanded = !state.todayExercises[ei].expanded;
  renderTodayLog();
}

function updateSet(ei, si, field, val) {
  if (field === 'weight') val = val.replace(/[^0-9.]/g, '');  // digits + decimal only
  if (field === 'reps')   val = val.replace(/[^0-9]/g,  '');  // digits only
  state.todayExercises[ei].sets[si][field] = val;
  saveWorkoutDraft();
}

function addSet(ei) {
  state.todayExercises[ei].sets.push({ weight: '', reps: '', done: false });
  saveWorkoutDraft();
  renderTodayLog();
}

function toggleDone(ei, si) {
  const ex = state.todayExercises[ei];
  const s  = ex.sets[si];
  s.done = !s.done;

  if (s.done) {
    startTimer();
    // PR notification check
    const pr = state.prs[ex.name];
    if (ex.bodyweight || ex.timed) {
      if (s.reps && (!pr || parseInt(s.reps) > parseInt(pr.reps)))
        toast('🏆 New PR on ' + ex.name + '!');
    } else {
      if (s.weight && s.reps && (!pr || parseFloat(s.weight) > parseFloat(pr.weight)))
        toast('🏆 New PR on ' + ex.name + '!');
    }
  }

  saveWorkoutDraft();
  renderTodayLog();
}

async function finishWorkout() {
  const note = document.getElementById('session-note').value.trim();
  const exs = state.todayExercises
    .map(ex => ({
      name:       ex.name,
      bodyweight: ex.bodyweight || false,
      timed:      ex.timed || false,
      sets:       ex.sets.filter(s => s.done && s.reps !== ''),
    }))
    .filter(e => e.sets.length);

  if (!exs.length) { toast('Log at least one set first!'); return; }

  const btn = document.getElementById('finish-btn');
  btn.textContent = 'Saving…';
  btn.disabled = true;

  try {
    await saveWorkoutToDB({ muscle: state.selectedMuscle, split: state.selectedSplit, note, exercises: exs });
    await loadHistory();
    await loadPRs();
    state.todayExercises = [];
    localStorage.removeItem('il_workout_draft');
    state.showAddExerciseForm = false;
    state.addExMode = 'reps';
    document.getElementById('session-note').value = '';
    renderTodayLog();
    renderHistory();
    toast('✅ Workout saved!');
    showPage('history', document.querySelectorAll('.nav-btn')[2]);
  } catch (e) {
    console.error(e);
    toast('❌ Save failed: ' + e.message);
  } finally {
    btn.textContent = '✓ Finish & Save Workout';
    btn.disabled = false;
  }
}

function startFreeWorkout() {
  state.todayExercises = [];
  state.showAddExerciseForm = true;
  saveWorkoutDraft();
  renderTodayLog();
  toast('Free workout started! Add your exercises below.');
}

function openAddExerciseForm() {
  state.showAddExerciseForm = true;
  state.addExMode = 'reps';
  renderTodayLog();
  document.getElementById('new-ex-name')?.focus();
}

function cancelAddExercise() {
  state.showAddExerciseForm = false;
  renderTodayLog();
}

function setAddExMode(mode) {
  state.addExMode = mode;
  renderTodayLog();
  document.getElementById('new-ex-name')?.focus();
}

function confirmAddExercise() {
  const nameEl = document.getElementById('new-ex-name');
  const name = nameEl?.value.trim();
  if (!name) { toast('Enter an exercise name first'); return; }

  const isWeighted = state.addExMode === 'weighted';
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
  toast('Exercise added!');
}
