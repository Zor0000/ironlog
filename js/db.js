// ─────────────────────────────────────────────────────────────
//  DATABASE OPERATIONS
// ─────────────────────────────────────────────────────────────

async function loadHistory() {
  const { data, error } = await sb
    .from('sessions')
    .select('*, session_sets(weight_kg, reps, exercises(name))')
    .eq('user_id', currentUser.id)
    .order('created_at', { ascending: false })
    .limit(100);
  if (error) { console.error('loadHistory:', error); return; }
  state.history = (data || []).map(s => ({
    id:        s.id,
    date:      new Date(s.created_at).toDateString(),
    muscle:    s.muscle_group,
    split:     s.split_type,
    note:      s.note,
    exercises: groupSets(s.session_sets || []),
  }));
}

function groupSets(sets) {
  const map = {};
  sets.forEach(s => {
    const n = s.exercises?.name || '?';
    if (!map[n]) map[n] = { name: n, sets: [] };
    if (s.weight_kg != null || s.reps != null)
      map[n].sets.push({ weight: s.weight_kg, reps: s.reps ?? '' });
  });
  return Object.values(map).filter(e => e.sets.length);
}

async function loadPRs() {
  const { data, error } = await sb
    .from('personal_records')
    .select('weight_kg, reps, exercises(name)')
    .eq('user_id', currentUser.id);
  if (error) { console.error('loadPRs:', error); return; }
  state.prs = {};
  (data || []).forEach(r => {
    if (r.exercises?.name) state.prs[r.exercises.name] = { weight: r.weight_kg, reps: r.reps };
  });
}

async function deleteSession(id) {
  if (!confirm('Delete this workout session?')) return;
  try {
    await sb.from('session_sets').delete().eq('session_id', id);
    const { error } = await sb.from('sessions').delete().eq('id', id).eq('user_id', currentUser.id);
    if (error) throw error;
    state.history = state.history.filter(s => s.id !== id);
    renderHistory();
    toast('Session deleted');
  } catch (e) {
    console.error(e);
    toast('Failed to delete: ' + e.message);
  }
}

async function saveWorkoutToDB(session) {
  // 1. Insert session row
  const { data: row, error: se } = await sb
    .from('sessions')
    .insert({ user_id: currentUser.id, muscle_group: session.muscle, split_type: session.split, note: session.note || null })
    .select().single();
  if (se) throw se;

  // 2. Upsert exercise names, then fetch IDs
  const names = [...new Set(session.exercises.map(e => e.name))];
  await sb.from('exercises').upsert(names.map(n => ({ name: n })), { onConflict: 'name', ignoreDuplicates: true });
  const { data: exRows } = await sb.from('exercises').select('id,name').in('name', names);
  const exMap = {};
  (exRows || []).forEach(r => exMap[r.name] = r.id);

  // 3. Insert set rows
  const setRows = [];
  session.exercises.forEach(ex => ex.sets.forEach(s => setRows.push({
    session_id:  row.id,
    exercise_id: exMap[ex.name],
    weight_kg:   (!ex.bodyweight && !ex.timed && s.weight !== '') ? parseFloat(s.weight) : null,
    reps:        s.reps !== '' ? parseInt(s.reps) : null,
  })));
  if (setRows.length) {
    const { error: ste } = await sb.from('session_sets').insert(setRows);
    if (ste) throw ste;
  }

  // 4. Update personal records
  for (const ex of session.exercises) {
    const eid = exMap[ex.name];
    if (!eid) continue;

    for (const s of ex.sets) {
      if (!s.reps) continue;

      if (ex.bodyweight || ex.timed) {
        // Bodyweight / timed: track best reps (or seconds)
        const r = parseInt(s.reps);
        const pr = state.prs[ex.name];
        if (!pr || r > parseInt(pr.reps)) {
          await sb.from('personal_records').upsert(
            { user_id: currentUser.id, exercise_id: eid, weight_kg: 0, reps: r, achieved_at: new Date().toISOString() },
            { onConflict: 'user_id,exercise_id' }
          );
        }
      } else {
        // Weighted: track best weight lifted
        if (!s.weight) continue;
        const w = parseFloat(s.weight), r = parseInt(s.reps);
        const pr = state.prs[ex.name];
        if (!pr || w > parseFloat(pr.weight)) {
          await sb.from('personal_records').upsert(
            { user_id: currentUser.id, exercise_id: eid, weight_kg: w, reps: r, achieved_at: new Date().toISOString() },
            { onConflict: 'user_id,exercise_id' }
          );
        }
      }
    }
  }
}
