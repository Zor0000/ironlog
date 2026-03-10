// ─────────────────────────────────────────────────────────────
//  LOG PAGE
// ─────────────────────────────────────────────────────────────
function renderTodayLog() {
  const c = document.getElementById('log-content');
  const f = document.getElementById('finish-section');

  if (!state.todayExercises.length) {
    c.innerHTML = `<div class="empty"><div class="empty-icon">${ICON_DUMBBELL}</div><div class="empty-text">No workout started yet.<br>Go to <strong>Workouts</strong> tab and pick your muscles!</div></div>`;
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
    }).join('')}`;
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
