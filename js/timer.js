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
  document.querySelector('.timer-bar')?.classList.add('timer-active');
  feelTap(12);
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

// Restart the rest timer from the full preset. Used when a set is completed
// so each set's rest counts down fresh instead of resuming the previous value.
function restartTimer() {
  clearInterval(state.timerInterval);
  state.timerRunning = false;
  state.timerSecs = state.timerMax;
  document.getElementById('timer-disp').textContent = fmtTime(state.timerSecs);
  startTimer();
}

function toggleTimer() {
  if (state.timerRunning) {
    clearInterval(state.timerInterval);
    state.timerRunning = false;
    document.getElementById('timer-toggle').textContent = '▶';
    document.getElementById('timer-toggle').classList.remove('running');
    document.querySelector('.timer-bar')?.classList.remove('timer-active');
    feelTap(6);
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
  document.querySelector('.timer-bar')?.classList.remove('timer-active');
  feelTap(6);
}

function setTimerPreset(val) {
  state.timerMax = parseInt(val);
  resetTimer();
}
