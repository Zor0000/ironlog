// ─────────────────────────────────────────────────────────────
//  APP BOOT & NAVIGATION
// ─────────────────────────────────────────────────────────────
window.addEventListener('load', async () => {
  updateHeaderDate();

  // Init Supabase client
  try {
    sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  } catch (e) {
    splashError('Supabase init failed: ' + e.message);
    return;
  }

  // Check for existing session
  let session = null;
  try {
    const { data, error } = await sb.auth.getSession();
    if (error) throw error;
    session = data.session;
  } catch (e) {
    splashError('Could not reach Supabase: ' + e.message);
    return;
  }

  hideSplash();

  if (session?.user) {
    await bootApp(session.user);
  } else {
    showAuth();
  }

  // React to login/logout from any tab
  sb.auth.onAuthStateChange(async (_event, session) => {
    if (session?.user) {
      document.getElementById('auth-screen').classList.remove('visible');
      await bootApp(session.user);
    } else {
      document.getElementById('app').classList.remove('visible');
      showAuth();
    }
  });
});

function hideSplash() {
  const s = document.getElementById('splash');
  s.classList.add('hidden');
  setTimeout(() => s.style.display = 'none', 450);
}

function splashError(msg) {
  document.querySelector('.splash-spinner').style.display = 'none';
  const el = document.createElement('div');
  el.className = 'splash-err';
  el.textContent = msg;
  document.getElementById('splash').appendChild(el);
}

function showAuth() {
  document.getElementById('auth-screen').classList.add('visible');
  document.getElementById('app').classList.remove('visible');
}

async function bootApp(user) {
  currentUser = user;
  document.getElementById('auth-screen').classList.remove('visible');
  document.getElementById('app').classList.add('visible');

  const name = user.user_metadata?.full_name?.split(' ')[0] || user.email.split('@')[0];
  document.getElementById('stats-user-name').textContent = 'Keep grinding, ' + name + ' 🔥';

  state.water = parseInt(localStorage.getItem('il_water_' + today()) || '0');

  await loadHistory();
  await loadPRs();
  renderSplits();
  renderMuscles();
  renderTodayLog();
}

function showPage(name, btn) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
  document.getElementById('page-' + name).classList.add('active');
  btn.classList.add('active');
  if (name === 'stats')   renderStats();
  if (name === 'history') renderHistory();
  if (name === 'log')     renderTodayLog();
}
