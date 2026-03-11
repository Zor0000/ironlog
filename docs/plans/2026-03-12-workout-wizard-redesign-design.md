# Design: Workout Page Multi-Step Wizard Redesign

**Date:** 2026-03-12
**Status:** Approved

---

## Problem

The Workouts page shows split type, muscle group, and suggested workout all stacked on one screen. This is cluttered and doesn't enforce a logical selection order. Muscle groups aren't filtered by split type, and there's no "Single Muscle" split option.

## Approach

Convert the Workouts page into a multi-step wizard where each step replaces the previous. Add split-aware muscle filtering via a day step for PPL and Upper/Lower. Add a "Single Muscle" split type that reuses Bro Split exercises.

---

## Section 1 — Wizard Step Navigation

Each step replaces the previous one (not stacked). A back button at the top-left lets you return to the prior step.

**Step flow varies by split:**

- Full Body / Bro Split / Single Muscle: Split → Muscle → Workout (3 steps)
- PPL / Upper-Lower: Split → Day → Muscle → Workout (4 steps)

**Back button:** Shown on steps 2+. Goes back one step, preserves prior selections (going back from muscle to day still remembers your split). Going forward again doesn't require re-picking.

**State:** `state.selectedSplit`, `state.selectedDay` (new), `state.selectedMuscle`. Changing a higher step clears all lower steps.

---

## Section 2 — Data Structure Changes

**New `SPLIT_DAYS` config in `data.js`:**

```js
const SPLIT_DAYS = {
  'PPL': [
    { day: 'Push', muscles: ['chest', 'shoulders', 'triceps'] },
    { day: 'Pull', muscles: ['back', 'biceps'] },
    { day: 'Legs', muscles: ['legs', 'core'] },
  ],
  'Upper/Lower': [
    { day: 'Upper', muscles: ['chest', 'back', 'shoulders', 'arms'] },
    { day: 'Lower', muscles: ['legs', 'core'] },
  ],
};
```

Splits NOT in `SPLIT_DAYS` skip the day step and show all 6 default muscles.

**PPL arms split:** Current `WORKOUTS.PPL.arms` (3 tricep + 3 bicep exercises) becomes `WORKOUTS.PPL.triceps` and `WORKOUTS.PPL.biceps`. The exercises already have day labels in their tips.

**New MUSCLES entries:** Add `triceps` and `biceps` with the existing Arms icon. These only appear when PPL day config references them.

**New split:** Add `'Single Muscle'` to `SPLITS`. `WORKOUTS['Single Muscle']` references `WORKOUTS['Bro Split']` data. No `SPLIT_DAYS` entry — goes straight to muscle selection.

**Removed:** `PPL_DAY` and `UL_DAY` mapping objects — day context is now explicit in the step flow.

---

## Section 3 — UI for Each Step

**Step 1: Pick Split** — Full page. Title: "SPLIT TYPE", subtitle: "Choose your training program". Pills for all splits including new "Single Muscle". Tapping advances immediately.

**Step 2: Pick Day** (PPL / Upper-Lower only) — Back button top-left showing selected split. Title: "TRAINING DAY". Large buttons per day. Tapping advances.

**Step 3: Pick Muscle** — Back button with prior context. Title: "MUSCLE GROUP". Shows only muscles relevant to current path (from `SPLIT_DAYS` or all 6 for non-day splits). Same grid card style. Tapping advances.

**Step 4: Suggested Workout** — Back button to muscle selection. Exercise cards + "Start This Workout" button. Chip shows full context (e.g. "PPL · Push Day · Chest").

**State resets:** Selecting a new split clears day + muscle. Selecting a new day clears muscle. Back button preserves selections.

---

## Files Changed

| File | Change |
|------|--------|
| `js/data.js` | Add `SPLIT_DAYS`, `SPLITS` update, split PPL arms into triceps/biceps, add Single Muscle, add triceps/biceps MUSCLES entries, remove `PPL_DAY`/`UL_DAY` |
| `js/state.js` | Add `state.selectedDay`, `state.workoutStep` |
| `js/workout.js` | Rewrite to wizard steps: `renderWorkoutStep()` replaces `renderSplits()`/`renderMuscles()`/`showSuggestions()` |
| `index.html` | Simplify workouts page div to a single container for wizard content |
