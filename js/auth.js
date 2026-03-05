// ─────────────────────────────────────────────────────────────
//  AUTHENTICATION
// ─────────────────────────────────────────────────────────────
let authMode = 'signin';

function switchTab(mode) {
  authMode = mode;
  document.getElementById('tab-signin').classList.toggle('active', mode === 'signin');
  document.getElementById('tab-signup').classList.toggle('active', mode === 'signup');
  document.getElementById('auth-name').style.display = mode === 'signup' ? 'block' : 'none';
  document.getElementById('auth-btn').textContent = mode === 'signin' ? 'Sign In' : 'Create Account';
  document.getElementById('auth-password').autocomplete = mode === 'signin' ? 'current-password' : 'new-password';
  document.getElementById('auth-msg').className = 'auth-msg';
}

function setAuthMsg(text, type) {
  const el = document.getElementById('auth-msg');
  el.textContent = text;
  el.className = 'auth-msg ' + type;
}

async function handleAuth() {
  const email = document.getElementById('auth-email').value.trim();
  const pass  = document.getElementById('auth-password').value;
  const name  = document.getElementById('auth-name').value.trim();
  const btn   = document.getElementById('auth-btn');

  document.getElementById('auth-msg').className = 'auth-msg';
  if (!email || !pass)                { setAuthMsg('Please fill in all fields.', 'error'); return; }
  if (pass.length < 6)                { setAuthMsg('Password must be at least 6 characters.', 'error'); return; }
  if (authMode === 'signup' && !name) { setAuthMsg('Please enter your name.', 'error'); return; }

  btn.disabled = true;
  btn.textContent = authMode === 'signin' ? 'Signing in…' : 'Creating account…';

  try {
    if (authMode === 'signin') {
      const { error } = await sb.auth.signInWithPassword({ email, password: pass });
      if (error) throw error;
      // onAuthStateChange in app.js fires → bootApp
    } else {
      const { error } = await sb.auth.signUp({ email, password: pass, options: { data: { full_name: name } } });
      if (error) throw error;
      setAuthMsg('✓ Account created! Check your email to confirm, then sign in.', 'success');
      switchTab('signin');
    }
  } catch (e) {
    setAuthMsg(e.message || 'Something went wrong.', 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = authMode === 'signin' ? 'Sign In' : 'Create Account';
  }
}

// Enter key shortcut on auth screen
document.addEventListener('keydown', e => {
  if (e.key === 'Enter' && document.getElementById('auth-screen').classList.contains('visible'))
    handleAuth();
});

async function doSignOut() {
  await sb.auth.signOut(); // triggers onAuthStateChange → showAuth
}
