# PR evidence: deterministic screenshots

Every UI change should ship with screenshots that anyone can regenerate.
`scripts/capture_evidence.sh` drives the app through fixed **scenarios** on a
fixed **device × Dynamic Type** matrix and writes stably-named PNGs.

```bash
scripts/capture_evidence.sh AddExercise                      # one scenario, all devices/sizes
scripts/capture_evidence.sh --all --reduce-motion            # everything, plus Reduce Motion
scripts/capture_evidence.sh ExerciseFinder --publish issue-39 # push + print a Markdown table
```

Output lands in `evidence/<UTC stamp>/` (git-ignored):

```
compact-default-addexercise-01-initial.png
compact-ax-addexercise-01-initial.png
standard-default-reduce-motion-exercisefinder-02-searching.png
MANIFEST.txt   # commit (+dirty if uncommitted changes), seed, simulators + runtimes, Xcode
```

A reused `--out` must be empty or passed with `--clean`. A failing scenario
fails the run (exit 1) and nothing is published. Publishing from a dirty
worktree is refused unless `--allow-dirty`, and the stamp says `+dirty`.

`--publish <label>` copies the set to the `pr-evidence` orphan branch under
`<label>/` and prints Markdown you can paste straight into the PR body. Nothing
binary lands in `main`.

## Matrix

| class | simulator (first available) | why |
|---|---|---|
| `compact` | iPhone SE (3rd gen) → iPhone 17e → 16e → 16 → 17 | smallest supported width/height |
| `standard` | iPhone 17 Pro → 17 → 16 Pro → 16 → 18 Pro | the common case |
| `large` | iPhone 18 Pro Max → 17 Pro Max → 16 Pro Max → 18 Pro | widest layout |

| size | `UIPreferredContentSizeCategoryName` |
|---|---|
| `default` | `UICTContentSizeCategoryL` (passed explicitly, never inherited) |
| `ax` | `UICTContentSizeCategoryAccessibilityL` |
| `ax-xxxl` | `UICTContentSizeCategoryAccessibilityXXXL` |
| `xl` | `UICTContentSizeCategoryExtraLarge` |

Use `--devices` / `--sizes` to trim the matrix while iterating.

## What makes it deterministic

- `UITest_ResetStore` — clean local store, no onboarding, signed out.
- `UITest_Seed <n>` — features that use randomness read `UITestHooks.seed` and
  swap in a seeded generator. Default seed is 7; change with `--seed`.
- Status bar override — 9:41, Wi-Fi, full battery (`simctl status_bar`).
- `en_US` language/region and `TZ=UTC` passed at launch, so the date header
  and keyboard don't follow the simulator's settings.
- Fixed content-size category per run; Reduce Motion toggled via simulator
  defaults and restored to whatever it was afterwards.
- Each screenshot is taken only after `waitForExistence` on the element that
  marks the state, then a short settle so springs finish.

Same commit + same simulator runtime + same inputs ⇒ the same pixels.

## Adding a scenario

Scenarios are test methods in `IronLogUITests/EvidenceCaptureTests.swift`:

```swift
func testScenarioMyScreen() {
    waitFor(app.buttons["my-entry-button"])
    app.buttons["my-entry-button"].tap()
    snap("initial")           // → <device>-<size>-myscreen-1-initial.png
    app.buttons["Do thing"].tap()
    waitFor(app.staticTexts["Done"])
    snap("done")
}
```

Rules of thumb:

- Address elements by accessibility identifier, never by position.
- Keep step names stable — PR templates and reviewers key off the filenames.
- Don't `sleep`; wait on the element that proves the state, then `snap`.
- The class is skipped unless `EVIDENCE_CAPTURE=1`, so it never runs in CI's
  `xcodebuild test`.
