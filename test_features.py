"""IronLog feature tests: workout persistence, draft, custom exercises."""
from playwright.sync_api import sync_playwright
import time

BASE = 'http://localhost:8765'
passes = []
failures = []

def ok(msg):
    passes.append(msg)
    print(f'  [PASS] {msg}')

def fail(msg):
    failures.append(msg)
    print(f'  [FAIL] {msg}')

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 390, 'height': 844})
    page.goto(BASE)
    page.wait_for_load_state('networkidle')

    # ── 1. Auth screen ────────────────────────────────────────────
    print('\n[1] AUTH SCREEN')
    if page.locator('#auth-screen').is_visible():
        ok('Auth screen visible on load')
    else:
        fail('Auth screen not visible')

    page.screenshot(path='/tmp/t01_auth.png')

    # ── 2. Check draft helpers exist in JS ───────────────────────
    print('\n[2] DRAFT HELPER FUNCTIONS EXIST')
    has_save = page.evaluate("typeof saveWorkoutDraft === 'function'")
    has_load = page.evaluate("typeof loadWorkoutDraft === 'function'")
    if has_save:
        ok('saveWorkoutDraft() is defined globally')
    else:
        fail('saveWorkoutDraft() NOT defined')
    if has_load:
        ok('loadWorkoutDraft() is defined globally')
    else:
        fail('loadWorkoutDraft() NOT defined')

    # ── 3. saveWorkoutDraft writes to localStorage ────────────────
    print('\n[3] saveWorkoutDraft PERSISTS TO localStorage')
    page.evaluate("""
        state.todayExercises = [{ name: 'Test Exercise', sets: [{ weight: '50', reps: '10', done: true }], expanded: true }];
        state.selectedMuscle = 'chest';
        state.selectedSplit  = 'PPL';
        saveWorkoutDraft();
    """)
    draft_raw = page.evaluate("localStorage.getItem('il_workout_draft')")
    if draft_raw:
        ok('Draft written to localStorage after saveWorkoutDraft()')
    else:
        fail('Draft NOT written to localStorage')

    # ── 4. Draft contains correct data ───────────────────────────
    print('\n[4] DRAFT CONTENT CORRECT')
    draft = page.evaluate("JSON.parse(localStorage.getItem('il_workout_draft') || '{}')")
    if draft.get('muscle') == 'chest':
        ok('Draft stores selectedMuscle correctly')
    else:
        fail(f'Draft muscle wrong: {draft.get("muscle")}')
    if draft.get('split') == 'PPL':
        ok('Draft stores selectedSplit correctly')
    else:
        fail(f'Draft split wrong: {draft.get("split")}')
    if draft.get('exercises') and draft['exercises'][0]['name'] == 'Test Exercise':
        ok('Draft stores todayExercises correctly')
    else:
        fail('Draft exercises wrong or missing')

    # ── 5. loadWorkoutDraft restores state ───────────────────────
    print('\n[5] loadWorkoutDraft RESTORES STATE')
    page.evaluate("""
        state.todayExercises = [];
        state.selectedMuscle = null;
        state.selectedSplit  = 'Full Body';
        loadWorkoutDraft();
    """)
    restored = page.evaluate("""({
        exCount: state.todayExercises.length,
        muscle:  state.selectedMuscle,
        split:   state.selectedSplit
    })""")
    if restored['exCount'] == 1:
        ok('loadWorkoutDraft restores todayExercises')
    else:
        fail(f'todayExercises count after restore: {restored["exCount"]}')
    if restored['muscle'] == 'chest':
        ok('loadWorkoutDraft restores selectedMuscle')
    else:
        fail(f'selectedMuscle after restore: {restored["muscle"]}')
    if restored['split'] == 'PPL':
        ok('loadWorkoutDraft restores selectedSplit')
    else:
        fail(f'selectedSplit after restore: {restored["split"]}')

    # ── 6. saveWorkoutDraft clears key when exercises empty ──────
    print('\n[6] saveWorkoutDraft CLEARS KEY ON EMPTY')
    page.evaluate("state.todayExercises = []; saveWorkoutDraft();")
    draft_after = page.evaluate("localStorage.getItem('il_workout_draft')")
    if draft_after is None:
        ok('Draft key removed when todayExercises is empty')
    else:
        fail('Draft key still present after empty save')

    # ── 7. state object has new fields ───────────────────────────
    print('\n[7] STATE HAS NEW FIELDS')
    fields = page.evaluate("({ show: 'showAddExerciseForm' in state, mode: 'addExMode' in state })")
    if fields['show']:
        ok('state.showAddExerciseForm exists')
    else:
        fail('state.showAddExerciseForm NOT in state')
    if fields['mode']:
        ok('state.addExMode exists')
    else:
        fail('state.addExMode NOT in state')

    # ── 8. onAuthStateChange guard functions defined ─────────────
    print('\n[8] FUNCTION EXISTENCE (new functions)')
    fns = ['startFreeWorkout', 'openAddExerciseForm', 'cancelAddExercise',
           'setAddExMode', 'confirmAddExercise']
    for fn in fns:
        exists = page.evaluate(f"typeof {fn} === 'function'")
        if exists:
            ok(f'{fn}() is defined')
        else:
            fail(f'{fn}() NOT defined')

    # ── 9. Log page empty state has Start Free Workout button ────
    print('\n[9] START FREE WORKOUT BUTTON IN EMPTY LOG')
    # Clear exercises and navigate to log page via JS
    page.evaluate("""
        state.todayExercises = [];
        state.showAddExerciseForm = false;
    """)
    # Simulate showing the log page content
    page.evaluate("renderTodayLog()")
    page.wait_for_timeout(300)
    btn_text = page.evaluate("""
        document.querySelector('#log-content .btn-primary')?.textContent?.trim()
    """)
    if btn_text and 'Free Workout' in btn_text:
        ok('Start Free Workout button present in empty log')
    else:
        fail(f'Start Free Workout button not found (got: {btn_text})')

    page.screenshot(path='/tmp/t09_empty_log.png')

    # ── 10. startFreeWorkout sets showAddExerciseForm ────────────
    print('\n[10] startFreeWorkout() SETS showAddExerciseForm')
    page.evaluate("startFreeWorkout()")
    page.wait_for_timeout(300)
    show_flag = page.evaluate("state.showAddExerciseForm")
    if show_flag:
        ok('showAddExerciseForm = true after startFreeWorkout()')
    else:
        fail('showAddExerciseForm not set by startFreeWorkout()')

    page.screenshot(path='/tmp/t10_free_workout.png')

    # ── 11. Add exercise form visible in log content ─────────────
    print('\n[11] ADD EXERCISE FORM VISIBLE')
    form_visible = page.evaluate("!!document.getElementById('add-ex-form')")
    if form_visible:
        ok('Add exercise form (#add-ex-form) rendered')
    else:
        fail('Add exercise form not found in DOM')

    name_input = page.evaluate("!!document.getElementById('new-ex-name')")
    if name_input:
        ok('#new-ex-name input rendered')
    else:
        fail('#new-ex-name input not found')

    page.screenshot(path='/tmp/t11_add_form.png')

    # ── 12. confirmAddExercise adds exercise ─────────────────────
    print('\n[12] confirmAddExercise() ADDS EXERCISE')
    page.evaluate("""
        document.getElementById('new-ex-name').value = 'Cable Curl';
        state.addExMode = 'weighted';
    """)
    page.evaluate("confirmAddExercise()")
    page.wait_for_timeout(300)
    ex_count = page.evaluate("state.todayExercises.length")
    if ex_count == 1:
        ok('Exercise added to state.todayExercises')
    else:
        fail(f'todayExercises length after add: {ex_count}')

    added_ex = page.evaluate("state.todayExercises[0]")
    if added_ex.get('name') == 'Cable Curl':
        ok('Exercise name stored correctly')
    else:
        fail(f'Exercise name wrong: {added_ex.get("name")}')
    if added_ex.get('bodyweight') == False:
        ok('Weight + Reps mode: bodyweight=false')
    else:
        fail(f'bodyweight flag wrong for weighted mode: {added_ex.get("bodyweight")}')
    if added_ex.get('custom') == True:
        ok('custom=true flag set on added exercise')
    else:
        fail('custom flag not set')

    # ── 13. Draft saved after confirmAddExercise ─────────────────
    print('\n[13] DRAFT SAVED AFTER ADD')
    draft_after_add = page.evaluate("localStorage.getItem('il_workout_draft')")
    if draft_after_add:
        ok('Draft persisted after adding exercise')
    else:
        fail('Draft NOT saved after adding exercise')

    page.screenshot(path='/tmp/t13_after_add.png')

    # ── 14. Reps-only mode sets bodyweight=true ──────────────────
    print('\n[14] REPS-ONLY MODE')
    page.evaluate("""
        state.todayExercises = [];
        state.showAddExerciseForm = true;
        state.addExMode = 'reps';
        renderTodayLog();
    """)
    page.wait_for_timeout(200)
    page.evaluate("document.getElementById('new-ex-name').value = 'Pull-Up Custom'")
    page.evaluate("confirmAddExercise()")
    page.wait_for_timeout(200)
    reps_ex = page.evaluate("state.todayExercises[0]")
    if reps_ex.get('bodyweight') == True:
        ok('Reps-only mode: bodyweight=true')
    else:
        fail(f'Reps-only bodyweight flag wrong: {reps_ex.get("bodyweight")}')

    page.screenshot(path='/tmp/t14_reps_only.png')

    browser.close()

# ── SUMMARY ──────────────────────────────────────────────────────
print(f'\n{"="*50}')
print(f'RESULTS: {len(passes)} passed, {len(failures)} failed')
print(f'{"="*50}')
if failures:
    print('\nFAILURES:')
    for f in failures:
        print(f'  [!] {f}')
else:
    print('\nAll tests passed!')
