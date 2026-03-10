# Design: Workout Persistence, Save Fix & Custom Exercises

**Date:** 2026-03-10
**Status:** Approved

---

## Problems Being Solved

1. **Workout resets on screen-off** — `onAuthStateChange` fires on every token refresh, re-calling `bootApp()` which wipes `state.todayExercises`.
2. **Save failures** — Caused by the above: state is cleared before the user taps Save.
3. **No custom exercises** — Users can only log exercises from the predefined `WORKOUTS` lists.

---

## Approach: localStorage persistence + inline custom exercise form

Minimal changes across existing files. No new dependencies, no schema changes.

---

## Section 1 — Fix: Workout resets on screen-off

### Fix 1a — Guard `onAuthStateChange` (app.js)
Only call `bootApp()` when `event === 'SIGNED_IN'` AND `currentUser` is not already set. All other events (`TOKEN_REFRESHED`, `INITIAL_SESSION`, etc.) are ignored, preventing re-boot on screen wake.

### Fix 1b — localStorage draft persistence (state.js)
Add two helpers:

- `saveWorkoutDraft()` — writes `{ exercises, muscle, split }` to `localStorage` key `il_workout_draft` when `todayExercises.length > 0`; removes the key when empty.
- `loadWorkoutDraft()` — reads and restores state from that key on boot.

**Call sites:**
- `saveWorkoutDraft()` after: `startWorkout()`, `addSet()`, `toggleDone()`, `updateSet()`
- `loadWorkoutDraft()` in `bootApp()` before `renderTodayLog()`
- `localStorage.removeItem('il_workout_draft')` after successful save in `finishWorkout()`

---

## Section 2 — Fix: Save workout reliability

With Section 1 in place, draft state persists through any page reload or auth refresh. The existing `finishWorkout()` → `saveWorkoutToDB()` logic in `log.js` / `db.js` is correct and requires no changes.

---

## Section 3 — Feature: Add custom exercise to active session

### UI (log.js + index.html)
- A `+ Add Exercise` button at the bottom of the log exercise list, always visible when a workout is active.
- Tapping it expands an inline form (no modal):
  - Text input: exercise name
  - Two toggle buttons: `Reps only` | `Weight + Reps`
  - `Add` confirm and `✕` cancel buttons

### Data shape pushed to `state.todayExercises`
```js
{
  name: inputName,
  bodyweight: mode === 'reps',  // true = reps only, false = weight+reps
  timed: false,
  custom: true,
  expanded: true,
  sets: [{ weight: '', reps: '', done: false }],
}
```
After adding: call `saveWorkoutDraft()` and `renderTodayLog()`.

### Free-form workout (no muscle selected)
When `state.todayExercises` is empty and no muscle is selected, the Log page empty state gains a `Start free workout` button. Tapping it sets a blank exercise list and shows the `+ Add Exercise` form immediately, allowing a fully custom session without going through the muscle picker.

---

## Files Changed

| File | Change |
|------|--------|
| `js/state.js` | Add `saveWorkoutDraft()` and `loadWorkoutDraft()` helpers |
| `js/app.js` | Guard `onAuthStateChange`; call `loadWorkoutDraft()` in `bootApp()` |
| `js/workout.js` | Call `saveWorkoutDraft()` after `startWorkout()` |
| `js/log.js` | Call `saveWorkoutDraft()` after set mutations; add `+ Add Exercise` UI and handler; clear draft on save; add `startFreeWorkout()` |
| `index.html` | No structural changes needed (form rendered dynamically in log.js) |
