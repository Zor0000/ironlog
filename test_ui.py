"""IronLog UI/UX audit using Playwright."""
from playwright.sync_api import sync_playwright
import time, os

BASE = 'http://localhost:8765'

issues = []
passes = []

def ok(msg):
    passes.append(msg)
    print(f'  [PASS] {msg}')

def warn(msg):
    issues.append(msg)
    print(f'  [WARN] {msg}')

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 390, 'height': 844})  # iPhone 14 size

    # ── 1. Splash / load ──────────────────────────────────────────
    print('\n[1] SPLASH & INITIAL LOAD')
    page.wait_for_timeout(1000)
    page.goto(BASE)
    page.wait_for_load_state('networkidle')
    page.screenshot(path='/tmp/01_splash.png')

    splash = page.locator('#splash')
    if splash.count():
        ok('Splash screen present')
        splash_text = splash.inner_text()
        if 'IronLog' in splash_text:
            ok('Splash shows app name')
        else:
            warn('Splash does not show app name')
    else:
        warn('No splash screen found')

    # Wait a moment for splash to hide
    page.wait_for_timeout(800)
    page.screenshot(path='/tmp/02_after_splash.png')

    # ── 2. Auth Screen ────────────────────────────────────────────
    print('\n[2] AUTH SCREEN')
    auth = page.locator('#auth-screen')
    if auth.is_visible():
        ok('Auth screen shown when not logged in')
    else:
        warn('Auth screen not visible — may already be logged in or error')

    page.screenshot(path='/tmp/03_auth.png')

    logo = page.locator('.auth-logo')
    if logo.count() and 'IronLog' in logo.inner_text():
        ok('Auth logo visible')
    else:
        warn('Auth logo missing or wrong text')

    tagline = page.locator('.auth-tagline')
    if tagline.count():
        ok(f'Auth tagline: "{tagline.inner_text()}"')
    else:
        warn('No auth tagline found')

    # Tabs
    tabs = page.locator('.auth-tab')
    if tabs.count() == 2:
        ok('Sign In / Sign Up tabs present')
    else:
        warn(f'Expected 2 auth tabs, found {tabs.count()}')

    # Inputs
    email_inp = page.locator('#auth-email')
    pwd_inp = page.locator('#auth-password')
    if email_inp.count():
        ok('Email input present')
    else:
        warn('Email input missing')
    if pwd_inp.count():
        ok('Password input present')
    else:
        warn('Password input missing')

    auth_btn = page.locator('#auth-btn')
    if auth_btn.count():
        ok(f'Auth button: "{auth_btn.inner_text()}"')
    else:
        warn('Auth button missing')

    # Test Sign Up tab switch
    page.click('#tab-signup')
    page.wait_for_timeout(200)
    name_inp = page.locator('#auth-name')
    if name_inp.is_visible():
        ok('Name field appears on Sign Up tab')
    else:
        warn('Name field not visible on Sign Up')

    page.screenshot(path='/tmp/04_signup_tab.png')

    # ── 3. Empty state / validation ───────────────────────────────
    print('\n[3] AUTH VALIDATION')
    page.click('#auth-btn')
    page.wait_for_timeout(400)
    msg = page.locator('#auth-msg')
    if msg.count() and msg.inner_text().strip():
        ok(f'Auth shows error message: "{msg.inner_text().strip()}"')
    else:
        warn('No validation message shown on empty submit')
    page.screenshot(path='/tmp/05_auth_validation.png')

    # ── 4. Accessibility checks ───────────────────────────────────
    print('\n[4] ACCESSIBILITY & META')
    title = page.title()
    if title:
        ok(f'Page title: "{title}"')
    else:
        warn('No page title set')

    viewport_meta = page.locator('meta[name="viewport"]')
    if viewport_meta.count():
        ok('Viewport meta tag present')
    else:
        warn('Viewport meta tag missing')

    theme_color = page.locator('meta[name="theme-color"]')
    if theme_color.count():
        ok('Theme-color meta present (PWA)')
    else:
        warn('Missing theme-color meta')

    manifest = page.locator('link[rel="manifest"]')
    if manifest.count():
        ok('Web manifest linked (PWA)')
    else:
        warn('No manifest link found')

    # ── 5. Check main nav structure (pre-login) ───────────────────
    print('\n[5] APP STRUCTURE (pre-login check)')
    app = page.locator('#app')
    app_visible = app.is_visible()
    if not app_visible:
        ok('App hidden before login (correct)')
    else:
        warn('App visible before login (security concern?)')

    # ── 6. Test font and visual rendering ─────────────────────────
    print('\n[6] VISUAL / FONT RENDERING')
    auth_logo_font = page.evaluate("window.getComputedStyle(document.querySelector('.auth-logo')).fontFamily")
    if 'Bebas' in auth_logo_font or 'bebas' in auth_logo_font.lower():
        ok('Logo uses Bebas Neue font')
    else:
        warn(f'Logo font: {auth_logo_font} (expected Bebas Neue)')

    # ── 7. Button hover states / touch targets ─────────────────────
    print('\n[7] TOUCH TARGETS')
    btn_height = page.evaluate("document.querySelector('#auth-btn')?.getBoundingClientRect().height")
    if btn_height and btn_height >= 44:
        ok(f'Auth button height {btn_height:.0f}px (≥44px touch target)')
    else:
        warn(f'Auth button height {btn_height:.0f}px — may be too small for touch (<44px)')

    auth_tab_h = page.evaluate("document.querySelector('.auth-tab')?.getBoundingClientRect().height")
    if auth_tab_h and auth_tab_h >= 36:
        ok(f'Auth tab height {auth_tab_h:.0f}px — OK')
    else:
        warn(f'Auth tab height {auth_tab_h:.0f}px — may be tight for touch')

    # ── 8. Responsive layout check ───────────────────────────────
    print('\n[8] RESPONSIVE LAYOUT')
    body_overflow = page.evaluate("window.getComputedStyle(document.body).overflowX")
    if body_overflow in ('hidden', 'clip'):
        ok('Body overflow-x controlled (no horizontal scroll)')
    else:
        warn(f'Body overflow-x: {body_overflow} — may cause horizontal scroll')

    auth_card_w = page.evaluate("document.querySelector('.auth-card')?.getBoundingClientRect().width")
    viewport_w = 390
    if auth_card_w and auth_card_w <= viewport_w:
        ok(f'Auth card fits viewport ({auth_card_w:.0f}px ≤ {viewport_w}px)')
    else:
        warn(f'Auth card ({auth_card_w:.0f}px) exceeds viewport ({viewport_w}px)')

    # ── 9. Check toast element ─────────────────────────────────────
    print('\n[9] TOAST NOTIFICATION')
    toast = page.locator('#toast')
    if toast.count():
        ok('Toast container present')
    else:
        warn('No toast container found')

    # ── 10. Screenshot final state ────────────────────────────────
    page.screenshot(path='/tmp/06_final.png', full_page=True)

    browser.close()

# ── SUMMARY ───────────────────────────────────────────────────────
print(f'\n{"="*50}')
print(f'RESULTS: {len(passes)} passed, {len(issues)} issues found')
print(f'{"="*50}')
if issues:
    print('\nISSUES:')
    for i in issues:
        print(f'  [!] {i}')
else:
    print('\nNo issues found!')
