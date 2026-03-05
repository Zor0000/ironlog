// ─────────────────────────────────────────────────────────────
//  SPLITS & MUSCLES
// ─────────────────────────────────────────────────────────────
const SPLITS = ['Full Body', 'PPL', 'Upper/Lower', 'Bro Split'];

const MUSCLE_ICONS = {
  // Two pectoral lobes meeting at the sternum
  chest:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9C3 6 5.5 4 8.5 4c2 0 3 1.5 3.5 3C12.5 5.5 13.5 4 15.5 4 18.5 4 21 6 21 9c0 5.5-4.5 9-9 11C7.5 18 3 14.5 3 9z"/><line x1="12" y1="5.5" x2="12" y2="14"/></svg>`,
  // V-taper torso — wide shoulders, spine down center, lat flare
  back:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8c2-1.5 4.5-2.5 8-2.5S18 6.5 20 8c0 5.5-1.5 10-3 12H7C5.5 18 4 13.5 4 8z"/><line x1="12" y1="5.5" x2="12" y2="20"/><path d="M8 12c1-.5 2.5-.8 4-.8s3 .3 4 .8"/></svg>`,
  // Two legs with visible knee joints
  legs:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 2v9l-2 4v6"/><path d="M15 2v9l2 4v6"/><path d="M9 9h6"/><path d="M7 13h3M17 13h-3"/></svg>`,
  // Deltoid cap with arms hanging — shoulder round and wide
  shoulders:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 7a3 3 0 0 1 6 0"/><path d="M5 15a7 7 0 0 1 14 0"/><path d="M3 11c1-2 2-4 2-4M21 11c-1-2-2-4-2-4"/><path d="M5 15v4M19 15v4"/><path d="M5 19c2 1.5 4.5 2.5 7 2.5s5-1 7-2.5"/></svg>`,
  // Classic flexed bicep — the universal symbol of strength
  arms:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 17c0 1 1.5 2 4 2h4c2.5 0 4-1 4-3 0-1.5-1.5-2.5-4-2.5H12c.5-1.5 1-3.5 1-5 0-2-1-3.5-3-3.5C8 5 6.5 7 6 9.5"/><path d="M6 9.5C5.5 11.5 5.5 14 6 17"/></svg>`,
  // 6-pack grid — two columns, three rows of ab blocks
  core:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="7.5" y="3" width="4" height="5" rx="1.5"/><rect x="12.5" y="3" width="4" height="5" rx="1.5"/><rect x="7.5" y="9.5" width="4" height="5" rx="1.5"/><rect x="12.5" y="9.5" width="4" height="5" rx="1.5"/><rect x="7.5" y="16" width="4" height="5" rx="1.5"/><rect x="12.5" y="16" width="4" height="5" rx="1.5"/></svg>`,
};

const ICON_TROPHY =
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 21h8M12 17v4"/><path d="M5 3h14v6a7 7 0 0 1-14 0V3z"/><path d="M5 6H3a2 2 0 0 0 0 4h2"/><path d="M19 6h2a2 2 0 0 1 0 4h-2"/></svg>`;

const ICON_TRASH =
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4h6v2"/></svg>`;

const ICON_CALENDAR =
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="16" y1="2" x2="16" y2="6"/></svg>`;

const ICON_DUMBBELL =
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><line x1="6" y1="12" x2="18" y2="12"/><rect x="2" y="9" width="4" height="6" rx="1"/><rect x="18" y="9" width="4" height="6" rx="1"/><rect x="8" y="7" width="2" height="10" rx="1"/><rect x="14" y="7" width="2" height="10" rx="1"/></svg>`;

const MUSCLES = [
  { id: 'chest',     label: 'Chest',     icon: MUSCLE_ICONS.chest },
  { id: 'back',      label: 'Back',      icon: MUSCLE_ICONS.back },
  { id: 'legs',      label: 'Legs',      icon: MUSCLE_ICONS.legs },
  { id: 'shoulders', label: 'Shoulders', icon: MUSCLE_ICONS.shoulders },
  { id: 'arms',      label: 'Arms',      icon: MUSCLE_ICONS.arms },
  { id: 'core',      label: 'Core',      icon: MUSCLE_ICONS.core },
];

// Split-day labels shown under muscle selection
const PPL_DAY = {
  chest:     'Push Day',
  shoulders: 'Push Day',
  arms:      'Push Day (Triceps) + Pull Day (Biceps)',
  back:      'Pull Day',
  legs:      'Leg Day',
  core:      'Any Day',
};
const UL_DAY = {
  chest:     'Upper Day',
  shoulders: 'Upper Day',
  arms:      'Upper Day',
  back:      'Upper Day',
  legs:      'Lower Day',
  core:      'Lower Day',
};

// ─────────────────────────────────────────────────────────────
//  EXERCISE FLAGS
//  weighted  (default) → shows KG + REPS inputs
//  bodyweight: true    → shows REPS input only (no KG)
//  timed: true         → shows SECS input only (no KG/REPS label)
// ─────────────────────────────────────────────────────────────

const WORKOUTS = {

  // ── FULL BODY ────────────────────────────────────────────────
  // 3 days/week (Mon/Wed/Fri). Focus on big compound lifts.
  // Keep volume low per muscle — quality over quantity.
  'Full Body': {
    chest: [
      { name: 'Barbell Bench Press',    sets: 3, reps: '5–8',   tip: 'Arch slightly, feet flat. Bar touches lower chest. Drive up and slightly back. Best compound for chest mass.' },
      { name: 'Incline Dumbbell Press', sets: 3, reps: '10–12', tip: '30–45° bench angle. Lower dumbbells until elbows go just below bench height. Upper chest focus.' },
      { name: 'Push-Ups',               sets: 2, reps: '10–15', tip: 'Body in a straight line. Elbows at 45° from torso — not flared at 90°. Great finisher.', bodyweight: true },
    ],
    back: [
      { name: 'Barbell Row',               sets: 3, reps: '5–8',   tip: 'Hinge at hips ~45°. Pull bar to belly button. Squeeze shoulder blades hard at top. Back stays flat.' },
      { name: 'Lat Pulldown',              sets: 3, reps: '10–12', tip: 'Lean back slightly, pull bar to upper chest. Fully extend arms at top for full lat stretch.' },
      { name: 'Pull-Up / Assisted Pull-Up',sets: 2, reps: '5–8',   tip: 'Dead hang at the bottom. Pull chest toward the bar. Control the lowering — 2 seconds down.', bodyweight: true },
    ],
    legs: [
      { name: 'Barbell Back Squat',     sets: 3, reps: '5–8',   tip: 'Bar on upper traps, chest up. Knees track toes. Hip crease BELOW knees at the bottom. King of all exercises.' },
      { name: 'Romanian Deadlift (DB)', sets: 3, reps: '10–12', tip: 'Push hips BACK — not down. This is a hip hinge, not a squat. Feel hamstring stretch. Back stays neutral.' },
      { name: 'Walking Lunges',         sets: 2, reps: '10 each', tip: 'Big step forward. Front shin stays vertical. Back knee nearly touches the floor. Step through, don\'t rock.', bodyweight: true },
    ],
    shoulders: [
      { name: 'Barbell Overhead Press', sets: 3, reps: '5–8',   tip: 'Bar starts at chin level. Press straight up, slightly back at top. Keep core and glutes tight throughout.' },
      { name: 'Dumbbell Lateral Raise', sets: 3, reps: '12–15', tip: 'Lead with elbows, slight bend. Raise to shoulder height only. Go lighter than you think — feel the burn.' },
    ],
    arms: [
      { name: 'Barbell Curl',            sets: 3, reps: '8–10',  tip: 'Elbows pinned at sides. Full range of motion — all the way down and all the way up. No swinging.' },
      { name: 'Tricep Dips (Bench)',      sets: 3, reps: '10–12', tip: 'Hands on bench behind you, feet forward. Elbows point BACK not out. Lower until 90°. Keep chest up.', bodyweight: true },
      { name: 'Hammer Curl',             sets: 2, reps: '10–12', tip: 'Neutral grip (thumbs up). Works brachialis for arm thickness. Alternate arms, full range.' },
    ],
    core: [
      { name: 'Plank',            sets: 3, reps: '30–45', tip: 'Squeeze glutes AND abs at the same time. Don\'t let hips sag or rise. Breathe normally.', timed: true },
      { name: 'Dead Bug',         sets: 3, reps: '10 each', tip: 'Press lower back into floor throughout. Move OPPOSITE arm and leg slowly. Best core stability exercise.', bodyweight: true },
      { name: 'Hanging Leg Raise',sets: 3, reps: '10–12', tip: 'Full dead hang. Posterior pelvic tilt at the top for full ab contraction. Control the descent.', bodyweight: true },
    ],
  },

  // ── PPL ──────────────────────────────────────────────────────
  // Push/Pull/Legs — 6 days/week (or 3 with rest between).
  // Push = Chest + Shoulders + Triceps
  // Pull = Back + Biceps
  // Legs = Quads + Hamstrings + Glutes + Calves + Core
  'PPL': {
    chest: [ // Push Day
      { name: 'Barbell Bench Press',    sets: 4, reps: '6–10',  tip: 'Arch slightly, feet flat. Bar touches lower chest. Drive through the sticking point — don\'t grind slowly.' },
      { name: 'Incline Dumbbell Press', sets: 3, reps: '10–12', tip: '30–45° incline. PPL means more chest volume — focus upper chest. Lower until elbows go below bench level.' },
      { name: 'Cable Chest Fly',        sets: 3, reps: '12–15', tip: 'High cables. Slight bend in elbows throughout. Arc motion, squeeze hard at center. Keep shoulder blades back.' },
      { name: 'Push-Ups',               sets: 3, reps: '12–15', tip: 'Great burnout finisher. Can add a weight plate on back to progress. Elbows at 45°, full range.', bodyweight: true },
    ],
    shoulders: [ // Push Day
      { name: 'Seated DB Shoulder Press', sets: 3, reps: '10–12', tip: 'Press straight up. Elbows at ~75° to body. Don\'t lock out fully — keep tension on delts.' },
      { name: 'Lateral Raises',           sets: 4, reps: '15–20', tip: 'PPL gets high shoulder volume. Use lighter weight and feel every rep. Lead with elbows, not wrists.' },
      { name: 'Rear Delt Fly',            sets: 3, reps: '15–20', tip: 'Bend forward 45°. Raise elbows to shoulder height. Rear delts are critical for posture and shoulder health.' },
      { name: 'Cable Front Raise',        sets: 3, reps: '12–15', tip: 'Single cable, alternate arms. Raise to eye level. Keep core tight. Front delts get worked by pressing too.' },
    ],
    arms: [ // Triceps on Push Day + Biceps on Pull Day (both shown)
      { name: 'Tricep Pushdown (Cable)',    sets: 3, reps: '12–15', tip: 'Push Day — Triceps. Lock elbows at sides. Push all the way to full extension. Rope or straight bar.' },
      { name: 'Overhead Tricep Extension',  sets: 3, reps: '12',    tip: 'Push Day — Triceps. Dumbbell overhead. Lower slowly behind head. Best for long tricep head stretch.' },
      { name: 'Tricep Dips',                sets: 3, reps: '10–15', tip: 'Push Day — Triceps. Stay upright for tricep focus. Elbows back. Control the descent.', bodyweight: true },
      { name: 'Barbell / EZ-Bar Curl',      sets: 3, reps: '10–12', tip: 'Pull Day — Biceps. Heavy and strict. No swinging. Elbows pinned at sides. Full range of motion.' },
      { name: 'Hammer Curl',                sets: 3, reps: '10–12', tip: 'Pull Day — Biceps. Neutral grip. Works brachialis for arm girth. Alternate arms, full range.' },
      { name: 'Incline Dumbbell Curl',      sets: 2, reps: '12',    tip: 'Pull Day — Biceps. Arms hang behind you on incline bench. Maximum stretch at bottom for peak.' },
    ],
    back: [ // Pull Day
      { name: 'Deadlift',                    sets: 3, reps: '4–6',   tip: 'Bar over mid-foot. Neutral spine. Push the floor away — don\'t think of it as pulling. Biggest strength builder.' },
      { name: 'Lat Pulldown',                sets: 4, reps: '10–12', tip: 'Wide grip for lat width. Lean back slightly. Pull to upper chest. Fully extend at top every rep.' },
      { name: 'Seated Cable Row',            sets: 3, reps: '10–12', tip: 'Chest up, sit tall. Pull handle to belly button. Squeeze shoulder blades and hold 1 second at peak.' },
      { name: 'Single-Arm Dumbbell Row',     sets: 3, reps: '10–12', tip: 'Row to your hip — not your shoulder. Elbow tracks close to body. Keep back flat.' },
      { name: 'Pull-Up / Assisted Pull-Up',  sets: 3, reps: '6–10',  tip: 'Dead hang at bottom. Pull chest to the bar. The single best exercise for lat width.', bodyweight: true },
      { name: 'Face Pulls',                  sets: 3, reps: '15–20', tip: 'Cable at eye height. Pull rope to forehead, elbows flared HIGH. Essential for shoulder health and posture.' },
    ],
    legs: [
      { name: 'Barbell Back Squat',      sets: 4, reps: '6–10',   tip: 'High bar or low bar — your choice. Knees track toes. Go below parallel if mobility allows. Breathe in on the way down.' },
      { name: 'Leg Press (Machine)',     sets: 3, reps: '12–15',  tip: 'Feet shoulder-width. Press through heels. Don\'t lock knees at top. High foot = more hamstrings.' },
      { name: 'Romanian Deadlift',       sets: 3, reps: '10–12',  tip: 'Hip hinge. Push hips back slowly. Feel every inch of hamstring stretch. 2–3 second eccentric.' },
      { name: 'Leg Curl (Machine)',      sets: 3, reps: '12–15',  tip: '3-second negative. Don\'t let hips rise off the pad. Full range of motion for hamstring health.' },
      { name: 'Leg Extension (Machine)', sets: 3, reps: '15',     tip: 'Pause and squeeze at the top. Quad isolation finisher. Don\'t use too much weight — feel the contraction.' },
      { name: 'Standing Calf Raises',    sets: 4, reps: '15–20',  tip: 'Full stretch at the bottom. Pause and squeeze at the top every single rep. Calves need high reps.' },
    ],
    core: [
      { name: 'Cable Crunch',      sets: 3, reps: '15–20', tip: 'Kneel at cable. Crunch ribs TO hips — not head to knees. Keep hips still. Heavy cable crunch builds ab thickness.' },
      { name: 'Plank',             sets: 3, reps: '45–60', tip: 'Posterior pelvic tilt slightly. Squeeze abs and glutes. Breathe normally. Increase duration over time.', timed: true },
      { name: 'Hanging Leg Raise', sets: 3, reps: '12–15', tip: 'Dead hang. Raise legs to parallel or higher. No swinging — use ab contraction, not momentum.', bodyweight: true },
      { name: 'Russian Twist',     sets: 3, reps: '20 total', tip: 'Lean back slightly, feet off floor. Rotate from torso, not just arms. Add a dumbbell for progression.', bodyweight: true },
    ],
  },

  // ── UPPER / LOWER ────────────────────────────────────────────
  // 4 days/week (Upper-A Mon, Lower-A Tue, off Wed, Upper-B Thu, Lower-B Fri).
  // Balanced push+pull each upper day. Quad+hamstring each lower day.
  'Upper/Lower': {
    chest: [ // Upper Day — balanced push + pull
      { name: 'Barbell Bench Press',    sets: 4, reps: '6–8',      tip: 'Upper/Lower allows heavier pressing. Control the descent 2–3 sec. Explosive press up. Shoulder blades stay retracted.' },
      { name: 'Incline Dumbbell Press', sets: 3, reps: '10–12',    tip: 'Upper chest emphasis. Keep dumbbells in line with lower chest. Full range of motion.' },
      { name: 'Dumbbell Flat Fly',      sets: 3, reps: '12–15',    tip: 'Light weight. Arc motion. Feel the chest stretch at the bottom. Slight elbow bend throughout.' },
      { name: 'Push-Ups',               sets: 2, reps: 'To failure', tip: 'Great burnout finisher at the end of chest work. Elevate feet for upper chest focus.', bodyweight: true },
    ],
    back: [ // Upper Day
      { name: 'Barbell Row',               sets: 4, reps: '6–8',   tip: 'Hinge at hips. Pull bar to navel. Chest stays up. The back mass builder — treat it like a deadlift for the upper back.' },
      { name: 'Lat Pulldown',              sets: 3, reps: '10–12', tip: 'Wide grip for back width. Pull to upper chest. Feel each lat independently.' },
      { name: 'Cable Row',                 sets: 3, reps: '12',    tip: 'Vary the grip each session (wide, narrow, neutral) for complete back development.' },
      { name: 'Face Pulls',                sets: 3, reps: '20',    tip: 'High pulley, pull to forehead with external rotation. Non-negotiable for shoulder health. Every upper day.' },
      { name: 'Pull-Up / Assisted Pull-Up',sets: 3, reps: '6–10',  tip: 'Full dead hang at the bottom. Chin over bar at the top. Best lat width exercise.', bodyweight: true },
    ],
    legs: [ // Lower Day
      { name: 'Barbell Back Squat',    sets: 4, reps: '6–10',   tip: 'Primary quad and glute driver. Controlled descent. Explode up through heels.' },
      { name: 'Romanian Deadlift',     sets: 3, reps: '10–12',  tip: 'Hip hinge pattern. Push hips back. Feel hamstrings load under tension. Back neutral throughout.' },
      { name: 'Leg Press',             sets: 3, reps: '12–15',  tip: 'Great quad volume after squats. Vary foot placement each session for different emphasis.' },
      { name: 'Leg Curl (Machine)',    sets: 3, reps: '12–15',  tip: 'Slow eccentric (3 sec). Vital for hamstring health and knee injury prevention.' },
      { name: 'Bulgarian Split Squat', sets: 3, reps: '10 each', tip: 'Rear foot elevated on bench. Front foot far forward. One of the best quad and glute exercises. Brutal but effective.', bodyweight: true },
      { name: 'Standing Calf Raises',  sets: 4, reps: '15–20',  tip: 'Pause at top. Full stretch at bottom. Calves are used to bodyweight daily — they need serious volume.' },
    ],
    shoulders: [ // Upper Day
      { name: 'Barbell Overhead Press', sets: 4, reps: '6–8',   tip: 'Heavy compound shoulder work. Bar starts at chin. Press straight up. Keep core braced.' },
      { name: 'Dumbbell Lateral Raise', sets: 3, reps: '15–20', tip: 'Side delt isolation. Can do seated for stricter form. Lead with elbows, not wrists.' },
      { name: 'Rear Delt Fly',          sets: 3, reps: '15–20', tip: 'Bent-over or on incline bench. Rear delts are typically undertrained — critical for shoulder balance.' },
      { name: 'Arnold Press',           sets: 3, reps: '10–12', tip: 'Start with palms facing you, rotate outward as you press. Hits all 3 heads of the deltoid.' },
    ],
    arms: [ // Upper Day
      { name: 'Barbell Curl',             sets: 3, reps: '8–10',  tip: 'Standing strict curl. Full range of motion. Keep elbows pinned. No body sway.' },
      { name: 'Skull Crushers (EZ Bar)', sets: 3, reps: '10–12', tip: 'Lower bar toward forehead carefully. Elbows stay fixed pointing at ceiling. Great tricep mass builder.' },
      { name: 'Hammer Curl',              sets: 3, reps: '10–12', tip: 'Neutral grip. Adds brachialis thickness. Alternate arms, full range.' },
      { name: 'Tricep Pushdown (Cable)',  sets: 3, reps: '12–15', tip: 'Lock elbows at sides. Full extension every rep. Rope vs. bar changes the feel — try both.' },
    ],
    core: [ // Lower Day
      { name: 'Plank',              sets: 3, reps: '45–60', tip: 'Squeeze every muscle. Quality beats duration. Posterior pelvic tilt for better ab activation.', timed: true },
      { name: 'Ab Wheel Rollout',   sets: 3, reps: '8–12',  tip: 'Start from knees. Roll out until back is flat. Pull back using abs — not arms. Best ab exercise for strength.', bodyweight: true },
      { name: 'Hanging Leg Raise',  sets: 3, reps: '12–15', tip: 'Posterior pelvic tilt at the top for full rectus abdominis contraction. Control the descent.', bodyweight: true },
      { name: 'Cable Crunch',       sets: 3, reps: '15–20', tip: 'Round your back. Crunch ribs to hips. Controlled movement throughout. Great for lower ab thickness.' },
    ],
  },

  // ── BRO SPLIT ────────────────────────────────────────────────
  // 5 days/week: Mon=Chest, Tue=Back, Wed=Legs, Thu=Shoulders, Fri=Arms.
  // Highest volume per muscle. Mix of heavy compound + isolation.
  'Bro Split': {
    chest: [
      { name: 'Barbell Bench Press',    sets: 4, reps: '6–10',    tip: 'Primary mass builder. Vary grip width (wide hits outer chest, closer hits inner). Own the bench press.' },
      { name: 'Incline Dumbbell Press', sets: 4, reps: '10–12',   tip: 'Upper chest often lags — prioritize this. 30–45° angle. Dumbbells allow deeper stretch.' },
      { name: 'Decline Barbell Press',  sets: 3, reps: '10–12',   tip: 'Slight decline (15–30°). Hits the lower chest for full chest development. Often skipped but very effective.' },
      { name: 'Cable Chest Fly',        sets: 3, reps: '12–15',   tip: 'High cables. Squeeze hard at the center. Constant tension throughout the motion. Great isolation.' },
      { name: 'Dumbbell Flat Fly',      sets: 3, reps: '12–15',   tip: 'Deep stretch at the bottom. Go light — form first. Feel the chest open up on every rep.' },
      { name: 'Push-Ups',               sets: 3, reps: 'To failure', tip: 'Burnout finisher after heavy pressing. Elevate feet for upper chest. Elbows at 45°.', bodyweight: true },
    ],
    back: [
      { name: 'Deadlift',                   sets: 3, reps: '4–6',   tip: 'Heaviest compound. Drive the floor away. Don\'t jerk the bar. Biggest overall strength builder.' },
      { name: 'Barbell Row',                 sets: 4, reps: '8–10',  tip: 'Overhand grip. Pull to navel. Squeeze shoulder blades at top. Heaviest back exercise after deadlift.' },
      { name: 'Lat Pulldown',                sets: 3, reps: '10–12', tip: 'Wide grip for width. Feel each lat pull down independently. Don\'t use momentum.' },
      { name: 'Single-Arm Dumbbell Row',     sets: 3, reps: '10–12', tip: 'Heavy. Row elbow past your torso level. Full range of motion. Back flat.' },
      { name: 'Pull-Up / Assisted Pull-Up',  sets: 3, reps: '8–12',  tip: 'Add a weight belt as you get stronger. Ultimate lat exercise. Full hang to chin over bar.', bodyweight: true },
      { name: 'Straight-Arm Pulldown',       sets: 3, reps: '15',    tip: 'Arms stay straight. Pull the bar to your thighs. Pure lat isolation. Great mind-muscle connection.' },
      { name: 'Face Pulls',                  sets: 3, reps: '20',    tip: 'Never skip these. External rotation and rear delt work. Pull to ears with elbows high and wide.' },
    ],
    legs: [
      { name: 'Barbell Back Squat',      sets: 4, reps: '6–10',   tip: 'King of exercises. Proper form over heavy weight. Knees track toes. Hip crease below parallel.' },
      { name: 'Leg Press (Machine)',     sets: 4, reps: '12–15',  tip: 'High foot placement hits glutes/hamstrings. Low foot placement hits quads. Vary each session.' },
      { name: 'Romanian Deadlift',       sets: 3, reps: '10–12',  tip: 'Slow, controlled hip hinge. Feel every inch of hamstring stretch. 3-second eccentric.' },
      { name: 'Leg Curl (Machine)',      sets: 3, reps: '12–15',  tip: '3-second eccentric. Don\'t let hips lift. Complete hamstring isolation.' },
      { name: 'Leg Extension (Machine)', sets: 3, reps: '15–20',  tip: 'Pause and squeeze quad at the top every rep. Great isolation finisher after squats.' },
      { name: 'Walking Lunges',          sets: 3, reps: '12 each', tip: 'Big step. Front shin stays vertical. Glute stretch at bottom. Functional and highly effective.', bodyweight: true },
      { name: 'Standing Calf Raises',    sets: 5, reps: '15–20',  tip: 'Calves are stubborn — they need high frequency and FULL ROM. Pause at top, stretch at bottom.' },
    ],
    shoulders: [
      { name: 'Barbell Overhead Press',  sets: 4, reps: '6–8',   tip: 'Strict press, no leg drive. The shoulder strength and size builder. Keep core and glutes tight.' },
      { name: 'Dumbbell Shoulder Press', sets: 3, reps: '10–12', tip: 'Greater range of motion than barbell. Let dumbbells come down beside your ears at the bottom.' },
      { name: 'Lateral Raises',          sets: 4, reps: '15–20', tip: 'Bro Split gets high lateral delt volume. Cables + dumbbells in same session gives constant tension variety.' },
      { name: 'Rear Delt Fly',           sets: 4, reps: '15–20', tip: 'Bent-over or on incline bench. High reps. Rear delts severely underworked in most programs.' },
      { name: 'Upright Row',             sets: 3, reps: '12',    tip: 'EZ-bar or cable. Pull to chin level. Elbows flare wide and high. Works traps and lateral delts.' },
      { name: 'Face Pulls',              sets: 3, reps: '20',    tip: 'Always include for shoulder health. External rotation under load keeps rotator cuffs healthy.' },
    ],
    arms: [ // Dedicated Arm Day — Bro Split's signature session
      { name: 'Barbell Curl',              sets: 4, reps: '8–10',  tip: 'Heavy and strict. The primary bicep mass builder. Supinate wrist fully at the top.' },
      { name: 'Incline Dumbbell Curl',     sets: 3, reps: '10–12', tip: 'Full stretch at the bottom. Supinate at the top. Great for bicep peak development.' },
      { name: 'Hammer Curl',               sets: 3, reps: '10–12', tip: 'Neutral grip. Brachialis and forearm thickness. Alternate arms, controlled movement.' },
      { name: 'Preacher Curl (EZ Bar)',    sets: 3, reps: '12',    tip: 'Bench enforces strict form. No cheating possible. Full range on the pad for peak isolation.' },
      { name: 'Tricep Pushdown (Cable)',   sets: 4, reps: '12–15', tip: 'Lock elbows at sides — they don\'t move. Full extension on every rep. Rope or straight bar.' },
      { name: 'Overhead Tricep Extension',sets: 3, reps: '12',    tip: 'Long head of tricep. Dumbbell or EZ-bar. Control the eccentric. Best tricep stretch.' },
      { name: 'Tricep Dips',               sets: 3, reps: '10–15', tip: 'Stay upright to target triceps (lean forward = chest). Can add weight with a dipping belt.', bodyweight: true },
    ],
    core: [
      { name: 'Hanging Leg Raise',  sets: 4, reps: '15–20',  tip: 'Dead hang. Posterior pelvic tilt. Raise legs above parallel. Weighted if you can do 20 easily.', bodyweight: true },
      { name: 'Cable Crunch',       sets: 3, reps: '15–20',  tip: 'Heavy cable crunch builds ab thickness. Round your back. Ribs to hips every rep.' },
      { name: 'Plank',              sets: 3, reps: '60',      tip: 'Add a weight plate on your back for Bro Split level. Maximum full-body tension.', timed: true },
      { name: 'Ab Wheel Rollout',   sets: 3, reps: '10–15',  tip: 'Best overall ab exercise. Works entire core. Control both directions. Advance to standing rollout.', bodyweight: true },
      { name: 'Russian Twist',      sets: 3, reps: '20 total', tip: 'Hold a weight plate or medicine ball. Rotate from torso. Oblique focus.', bodyweight: true },
      { name: 'Decline Sit-Up',     sets: 3, reps: '15–20',  tip: 'Full range. Hold a weight plate at chest for progression. Classic ab builder.', bodyweight: true },
    ],
  },
};
