// ─────────────────────────────────────────────────────────────
//  STATS PAGE
// ─────────────────────────────────────────────────────────────
function renderStats() {
  document.getElementById('pr-title').innerHTML = `Personal Records ${ICON_TROPHY}`;
  document.getElementById('st-sessions').textContent = state.history.length;

  let sets = 0, vol = 0;
  state.history.forEach(s => s.exercises.forEach(ex => {
    sets += ex.sets.length;
    ex.sets.forEach(st => {
      if (st.weight != null && st.weight > 0 && st.reps)
        vol += parseFloat(st.weight) * parseInt(st.reps);
    });
  }));

  document.getElementById('st-sets').textContent   = sets;
  document.getElementById('st-volume').textContent = vol >= 1000 ? (vol / 1000).toFixed(1) + 'k' : Math.round(vol);

  // Streak calculation
  let streak = 0;
  const chk = new Date();
  const dates = state.history.map(s => s.date);
  while (dates.includes(chk.toDateString())) {
    streak++;
    chk.setDate(chk.getDate() - 1);
  }
  document.getElementById('st-streak').textContent = streak;

  // Weekly activity bar
  const mon = getMondayOfWeek(new Date());
  document.getElementById('week-bar').innerHTML = Array(7).fill(0).map((_, i) => {
    const d = new Date(mon);
    d.setDate(mon.getDate() + i);
    return `<div class="week-dot ${dates.includes(d.toDateString()) ? 'done' : ''}"></div>`;
  }).join('');

  // Personal records
  const prKeys = Object.keys(state.prs);
  document.getElementById('pr-list').innerHTML = prKeys.length
    ? prKeys.map(k => {
        const pr = state.prs[k];
        const display = pr.weight > 0
          ? `${pr.weight}kg × ${pr.reps} reps`
          : `BW × ${pr.reps}`;
        return `<div class="pr-row"><div class="pr-ex">${k}</div><div class="pr-val">${display}</div></div>`;
      }).join('')
    : '<div style="font-size:13px;color:var(--muted2)">Complete workouts to see your PRs!</div>';

  // Water tracker
  document.getElementById('glasses').innerHTML = Array(8).fill(0).map((_, i) =>
    `<div class="glass ${i < state.water ? 'filled' : ''}" onclick="setWater(${i})">💧</div>`
  ).join('');
  document.getElementById('water-n').textContent = state.water;
}

function setWater(i) {
  state.water = i < state.water ? i : i + 1;
  localStorage.setItem('il_water_' + today(), state.water);
  renderStats();
}
