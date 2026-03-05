// ─────────────────────────────────────────────────────────────
//  HISTORY PAGE
// ─────────────────────────────────────────────────────────────
function renderHistory() {
  const list = document.getElementById('history-list');

  if (!state.history.length) {
    list.innerHTML = `<div class="empty">
      <div class="empty-icon">${ICON_CALENDAR}</div>
      <div class="empty-text">No sessions yet.<br>Complete your first workout!</div>
    </div>`;
    return;
  }

  list.innerHTML = state.history.map(s => {
    const m  = MUSCLES.find(x => x.id === s.muscle);
    const ts = s.exercises.reduce((a, e) => a + e.sets.length, 0);

    return `<div class="hist-card">
      <div class="hist-hdr">
        <div>
          <div class="hist-date">${s.date}</div>
          <div class="hist-sub">${ts} sets · ${s.split}</div>
        </div>
        <div style="display:flex;align-items:center;gap:8px">
          <span class="hist-tag">${m?.icon || ''} ${m?.label || s.muscle}</span>
          <button class="delete-session-btn" onclick="deleteSession('${s.id}')" title="Delete session">${ICON_TRASH}</button>
        </div>
      </div>
      ${s.exercises.map(ex => `
        <div class="hist-row">
          <div class="hist-ex-name">${ex.name}</div>
          <div class="hist-detail">${ex.sets.map(x => {
            const w = (x.weight != null && x.weight > 0) ? x.weight + 'kg' : 'BW';
            return `${w}×${x.reps || '?'}`;
          }).join(', ')}</div>
        </div>`).join('')}
      ${s.note ? `<div style="padding:9px 16px;font-size:11px;color:var(--muted2);border-top:1px solid var(--border)">📝 ${s.note}</div>` : ''}
    </div>`;
  }).join('');
}
