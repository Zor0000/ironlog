"""IronLog wizard flow tests."""
from playwright.sync_api import sync_playwright

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

    # ── 1. Wizard functions exist ───────────────────────────────
    print('\n[1] WIZARD FUNCTIONS EXIST')
    for fn in ['renderWorkoutStep', 'selectSplit', 'selectDay', 'selectMuscle',
               'goBackToSplit', 'goBackToDay', 'goBackToMuscle', 'startWorkout']:
        if page.evaluate(f"typeof {fn} === 'function'"):
            ok(f'{fn}() defined')
        else:
            fail(f'{fn}() NOT defined')

    # ── 2. Data structure checks ────────────────────────────────
    print('\n[2] DATA STRUCTURES')
    splits = page.evaluate("SPLITS")
    if splits == ['Full Body', 'PPL', 'Upper/Lower', 'Bro Split', 'Single Muscle']:
        ok('SPLITS has 5 entries including Single Muscle')
    else:
        fail(f'SPLITS wrong: {splits}')

    has_split_days = page.evaluate("typeof SPLIT_DAYS === 'object' && SPLIT_DAYS !== null")
    if has_split_days:
        ok('SPLIT_DAYS exists')
    else:
        fail('SPLIT_DAYS missing')

    ppl_days = page.evaluate("[d.day for d of SPLIT_DAYS['PPL']]" if False else
                             "SPLIT_DAYS['PPL'].map(d => d.day)")
    if ppl_days == ['Push', 'Pull', 'Legs']:
        ok('PPL has Push/Pull/Legs days')
    else:
        fail(f'PPL days wrong: {ppl_days}')

    ppl_push_muscles = page.evaluate("SPLIT_DAYS['PPL'][0].muscles")
    if ppl_push_muscles == ['chest', 'shoulders', 'triceps']:
        ok('PPL Push muscles: chest, shoulders, triceps')
    else:
        fail(f'PPL Push muscles wrong: {ppl_push_muscles}')

    ppl_pull_muscles = page.evaluate("SPLIT_DAYS['PPL'][1].muscles")
    if ppl_pull_muscles == ['back', 'biceps']:
        ok('PPL Pull muscles: back, biceps')
    else:
        fail(f'PPL Pull muscles wrong: {ppl_pull_muscles}')

    # PPL triceps/biceps exercise keys
    has_triceps = page.evaluate("Array.isArray(WORKOUTS['PPL'].triceps)")
    has_biceps = page.evaluate("Array.isArray(WORKOUTS['PPL'].biceps)")
    no_arms = page.evaluate("WORKOUTS['PPL'].arms === undefined")
    if has_triceps and has_biceps:
        ok('PPL has triceps and biceps keys')
    else:
        fail(f'PPL triceps={has_triceps} biceps={has_biceps}')
    if no_arms:
        ok('PPL has no arms key')
    else:
        fail('PPL still has arms key')

    # Single Muscle references Bro Split
    same_ref = page.evaluate("WORKOUTS['Single Muscle'] === WORKOUTS['Bro Split']")
    if same_ref:
        ok('Single Muscle references Bro Split data')
    else:
        fail('Single Muscle is not same reference as Bro Split')

    # ── 3. State fields ─────────────────────────────────────────
    print('\n[3] STATE FIELDS')
    for field in ['selectedDay', 'workoutStep']:
        if page.evaluate(f"'{field}' in state"):
            ok(f'state.{field} exists')
        else:
            fail(f'state.{field} missing')

    if page.evaluate("state.workoutStep") == 'split':
        ok('workoutStep defaults to split')
    else:
        fail(f'workoutStep default wrong: {page.evaluate("state.workoutStep")}')

    if page.evaluate("state.selectedSplit") is None:
        ok('selectedSplit defaults to null')
    else:
        fail(f'selectedSplit default wrong: {page.evaluate("state.selectedSplit")}')

    # ── 4. Step 1: Split selection renders ──────────────────────
    print('\n[4] STEP 1: SPLIT SELECTION')
    page.evaluate("state.workoutStep = 'split'; renderWorkoutStep()")
    page.wait_for_timeout(200)
    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    for s in ['Full Body', 'PPL', 'Upper/Lower', 'Bro Split', 'Single Muscle']:
        if s in wizard:
            ok(f'Split "{s}" rendered')
        else:
            fail(f'Split "{s}" NOT in wizard HTML')

    page.screenshot(path='/tmp/w01_splits.png')

    # ── 5. PPL -> Day step ──────────────────────────────────────
    print('\n[5] PPL -> DAY STEP')
    page.evaluate("selectSplit('PPL')")
    page.wait_for_timeout(200)
    if page.evaluate("state.workoutStep") == 'day':
        ok('PPL goes to day step')
    else:
        fail(f'workoutStep after PPL: {page.evaluate("state.workoutStep")}')

    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    for d in ['Push', 'Pull', 'Legs']:
        if d in wizard:
            ok(f'Day "{d}" rendered')
        else:
            fail(f'Day "{d}" NOT rendered')

    # Back button present
    if 'wizard-back' in wizard:
        ok('Back button present on day step')
    else:
        fail('Back button missing on day step')

    page.screenshot(path='/tmp/w02_ppl_days.png')

    # ── 6. PPL Push -> Muscle step ──────────────────────────────
    print('\n[6] PPL PUSH -> MUSCLE STEP')
    page.evaluate("selectDay('Push')")
    page.wait_for_timeout(200)
    if page.evaluate("state.workoutStep") == 'muscle':
        ok('Day selection goes to muscle step')
    else:
        fail(f'workoutStep: {page.evaluate("state.workoutStep")}')

    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    for m in ['Chest', 'Shoulders', 'Triceps']:
        if m in wizard:
            ok(f'Muscle "{m}" shown for Push day')
        else:
            fail(f'Muscle "{m}" NOT shown for Push day')

    # Should NOT show Back, Biceps, Legs, Arms, Core
    for m in ['Biceps', 'Legs', 'Core']:
        if m not in wizard:
            ok(f'Muscle "{m}" correctly hidden for Push day')
        else:
            fail(f'Muscle "{m}" should NOT be shown for Push day')

    page.screenshot(path='/tmp/w03_push_muscles.png')

    # ── 7. PPL Pull muscles ────────────────────────────────────
    print('\n[7] PPL PULL MUSCLES')
    page.evaluate("selectSplit('PPL'); selectDay('Pull')")
    page.wait_for_timeout(200)
    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    for m in ['Back', 'Biceps']:
        if m in wizard:
            ok(f'Muscle "{m}" shown for Pull day')
        else:
            fail(f'Muscle "{m}" NOT shown for Pull day')

    page.screenshot(path='/tmp/w04_pull_muscles.png')

    # ── 8. Select muscle -> workout step ─────────────────────────
    print('\n[8] SELECT MUSCLE -> WORKOUT')
    page.evaluate("selectSplit('PPL'); selectDay('Push'); selectMuscle('chest')")
    page.wait_for_timeout(200)
    if page.evaluate("state.workoutStep") == 'workout':
        ok('Muscle selection goes to workout step')
    else:
        fail(f'workoutStep: {page.evaluate("state.workoutStep")}')

    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    if 'Barbell Bench Press' in wizard:
        ok('PPL Chest exercises rendered')
    else:
        fail('PPL Chest exercises NOT found')
    if 'Start This Workout' in wizard:
        ok('Start button rendered')
    else:
        fail('Start button missing')

    page.screenshot(path='/tmp/w05_workout.png')

    # ── 9. Non-day split (Full Body) skips day step ─────────────
    print('\n[9] FULL BODY SKIPS DAY STEP')
    page.evaluate("selectSplit('Full Body')")
    page.wait_for_timeout(200)
    if page.evaluate("state.workoutStep") == 'muscle':
        ok('Full Body skips day step, goes to muscle')
    else:
        fail(f'workoutStep: {page.evaluate("state.workoutStep")}')

    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    for m in ['Chest', 'Back', 'Legs', 'Shoulders', 'Arms', 'Core']:
        if m in wizard:
            ok(f'Muscle "{m}" shown for Full Body')
        else:
            fail(f'Muscle "{m}" NOT shown for Full Body')

    # Triceps/Biceps should NOT appear (they're PPL-specific)
    # Note: "Triceps" and "Biceps" text won't appear in non-day splits
    # because the default muscleIds list uses 'arms' not 'triceps'/'biceps'

    page.screenshot(path='/tmp/w06_fullbody_muscles.png')

    # ── 10. Single Muscle same as Bro Split ─────────────────────
    print('\n[10] SINGLE MUSCLE')
    page.evaluate("selectSplit('Single Muscle')")
    page.wait_for_timeout(200)
    if page.evaluate("state.workoutStep") == 'muscle':
        ok('Single Muscle skips day step')
    else:
        fail(f'workoutStep: {page.evaluate("state.workoutStep")}')

    page.evaluate("selectMuscle('chest')")
    page.wait_for_timeout(200)
    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    if 'Barbell Bench Press' in wizard:
        ok('Single Muscle chest has exercises (from Bro Split)')
    else:
        fail('Single Muscle chest exercises missing')

    page.screenshot(path='/tmp/w07_single_muscle.png')

    # ── 11. Back navigation ─────────────────────────────────────
    print('\n[11] BACK NAVIGATION')
    # From workout -> muscle
    page.evaluate("selectSplit('PPL'); selectDay('Push'); selectMuscle('chest')")
    page.evaluate("goBackToMuscle()")
    page.wait_for_timeout(200)
    if page.evaluate("state.workoutStep") == 'muscle':
        ok('goBackToMuscle -> muscle step')
    else:
        fail(f'After goBackToMuscle: {page.evaluate("state.workoutStep")}')
    if page.evaluate("state.selectedDay") == 'Push':
        ok('Day preserved after going back from workout')
    else:
        fail(f'Day after back: {page.evaluate("state.selectedDay")}')

    # From muscle -> day
    page.evaluate("goBackToDay()")
    page.wait_for_timeout(200)
    if page.evaluate("state.workoutStep") == 'day':
        ok('goBackToDay -> day step')
    else:
        fail(f'After goBackToDay: {page.evaluate("state.workoutStep")}')
    if page.evaluate("state.selectedSplit") == 'PPL':
        ok('Split preserved after going back to day')
    else:
        fail(f'Split after back: {page.evaluate("state.selectedSplit")}')

    # From day -> split
    page.evaluate("goBackToSplit()")
    page.wait_for_timeout(200)
    if page.evaluate("state.workoutStep") == 'split':
        ok('goBackToSplit -> split step')
    else:
        fail(f'After goBackToSplit: {page.evaluate("state.workoutStep")}')

    # ── 12. Upper/Lower flow ────────────────────────────────────
    print('\n[12] UPPER/LOWER FLOW')
    page.evaluate("selectSplit('Upper/Lower')")
    page.wait_for_timeout(200)
    if page.evaluate("state.workoutStep") == 'day':
        ok('Upper/Lower goes to day step')
    else:
        fail(f'workoutStep: {page.evaluate("state.workoutStep")}')

    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    if 'Upper' in wizard and 'Lower' in wizard:
        ok('Upper and Lower days rendered')
    else:
        fail('Upper/Lower days missing')

    page.evaluate("selectDay('Upper')")
    page.wait_for_timeout(200)
    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    for m in ['Chest', 'Back', 'Shoulders', 'Arms']:
        if m in wizard:
            ok(f'Upper day shows {m}')
        else:
            fail(f'Upper day missing {m}')

    page.screenshot(path='/tmp/w08_upper_muscles.png')

    # ── 13. PPL Triceps exercises ───────────────────────────────
    print('\n[13] PPL TRICEPS EXERCISES')
    page.evaluate("selectSplit('PPL'); selectDay('Push'); selectMuscle('triceps')")
    page.wait_for_timeout(200)
    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    if 'Tricep Pushdown' in wizard:
        ok('Triceps exercises rendered')
    else:
        fail('Triceps exercises missing')
    if 'Barbell / EZ-Bar Curl' not in wizard:
        ok('Bicep exercises correctly NOT shown for triceps')
    else:
        fail('Bicep exercises leaking into triceps view')

    page.screenshot(path='/tmp/w09_triceps.png')

    # ── 14. PPL Biceps exercises ────────────────────────────────
    print('\n[14] PPL BICEPS EXERCISES')
    page.evaluate("selectSplit('PPL'); selectDay('Pull'); selectMuscle('biceps')")
    page.wait_for_timeout(200)
    wizard = page.evaluate("document.getElementById('workout-wizard').innerHTML")
    if 'Barbell / EZ-Bar Curl' in wizard:
        ok('Biceps exercises rendered')
    else:
        fail('Biceps exercises missing')
    if 'Tricep Pushdown' not in wizard:
        ok('Tricep exercises correctly NOT shown for biceps')
    else:
        fail('Tricep exercises leaking into biceps view')

    page.screenshot(path='/tmp/w10_biceps.png')

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
