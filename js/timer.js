// ─────────────────────────────────────────────────────────────
//  REST TIMER
// ─────────────────────────────────────────────────────────────
function fmtTime(s) {
  return `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, '0')}`;
}

function startTimer() {
  if (state.timerRunning) return;
  state.timerRunning = true;
  document.getElementById('timer-toggle').textContent = '⏸';
  document.getElementById('timer-toggle').classList.add('running');
  state.timerInterval = setInterval(() => {
    if (state.timerSecs <= 0) {
      resetTimer();
      toast('⏱ Rest over! Next set.');
      return;
    }
    state.timerSecs--;
    document.getElementById('timer-disp').textContent = fmtTime(state.timerSecs);
  }, 1000);
}

function toggleTimer() {
  if (state.timerRunning) {
    clearInterval(state.timerInterval);
    state.timerRunning = false;
    document.getElementById('timer-toggle').textContent = '▶';
    document.getElementById('timer-toggle').classList.remove('running');
  } else {
    startTimer();
  }
}

function resetTimer() {
  clearInterval(state.timerInterval);
  state.timerRunning = false;
  state.timerSecs = state.timerMax;
  document.getElementById('timer-disp').textContent = fmtTime(state.timerSecs);
  document.getElementById('timer-toggle').textContent = '▶';
  document.getElementById('timer-toggle').classList.remove('running');
}

function setTimerPreset(val) {
  state.timerMax = parseInt(val);
  resetTimer();
}
