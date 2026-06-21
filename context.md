# IronLog Project Context

## Overview
IronLog is a beginner-friendly personal gym tracker. It is completely free, has no third-party dependencies on either client, and uses Supabase as its backend. Two clients share the same backend:
1. A Progressive Web App (PWA) — Vanilla HTML/CSS/JS, hosted on GitHub Pages.
2. A Native iOS App — SwiftUI, zero third-party SDK dependencies.

## Architecture

### 1. Backend (Supabase)
- **Database**: PostgreSQL hosted on Supabase (free tier, `ap-southeast-2`, project ID `dvqevdydldxjqjrpkkjc`).
- **Auth**: Supabase Auth (Email/Password).
- **Tables**: `exercises`, `sessions`, `session_sets`, `personal_records`.
- **Security**: Row Level Security (RLS) — users only access their own data.
- **Keep-alive**: `.github/workflows/supabase-keepalive.yml` pings the REST endpoint daily to prevent free-tier auto-pause.

### 2. Frontend: Web App (PWA)
- **Tech Stack**: Vanilla HTML5, CSS3, JavaScript. No build steps or bundlers.
- **Hosting**: GitHub Pages (`main` branch, root `/`).
- **Key files**: `index.html`, `js/log.js`, `js/timer.js`, `css/`.
- **Testing**: `test_features.py`, `test_ui.py`, `test_wizard.py` (Python + Playwright).

### 3. Frontend: iOS App (Native)
- **Tech Stack**: Swift 5, SwiftUI.
- **Project file**: `IronLog.xcodeproj` is committed directly — no XcodeGen step needed at checkout.
- **Dependencies**: None. Supabase REST API called via native `URLSession` in `SupabaseService.swift`.
- **Architecture**: MVVM-like. `AppState` is the single `ObservableObject` / environment object. `ExerciseLibrary` owns the exercise catalog. `LocalStore` handles draft persistence via `UserDefaults`.
- **Tests**: `IronLogTests` (unit), `IronLogUITests` (UI).
- **Signing**: Release builds use team `75LRT8TRQY` (friend's account, TestFlight). Dev installs use `HSC7466MX4` (Neeraj's personal free Apple ID).

## Key Features (current)
- **Exercise Catalog**: 100+ exercises across 7 muscle groups (chest, back, legs, shoulders, biceps, triceps, core) stored in `IronLog/Resources/workouts.json` under the `LIBRARY` key. Each entry has `name`, `sets`, `reps`, `tip`, and optional `bodyweight`/`timed` flags.
- **Add Exercise form**: searchable catalog with muscle-group filter chips, inline in the log screen.
- **Splits**: PPL, Full Body, Upper/Lower, Bro Split. Multi-muscle days (e.g. "Legs + Core") start in a single session via `selectedWorkoutMuscleIDs`.
- **ConfirmActionModal**: reusable modal (`IronLog/Views/ConfirmActionModal.swift`) used for destructive actions (discard workout). Triggered by the workout-level trash button in LogView and WorkoutsView.
- **Rest Timer**: auto-restarts from the full preset (`restartTimer()`) each time a set is marked done — both in the iOS app and the web PWA (`js/timer.js`).
- **Draft Persistence**: in-progress workout survives app restarts via `LocalStore`.
- **Stats & PRs**: volume, streaks, personal records auto-detected on save.
- **Water Tracker**: 8-glass daily counter.

## Development Workflow

### Web PWA
```bash
python -m http.server 8765   # local server at http://localhost:8765
python test_features.py      # run Playwright feature tests
```

### iOS App — Simulator
```bash
xcodebuild -project IronLog.xcodeproj -scheme IronLog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/dd build
```

### iOS App — Install to Physical iPhone (free, no TestFlight)
```bash
# One-time: set your personal team ID (HSC7466MX4 for Neeraj)
export IRONLOG_TEAM_ID=HSC7466MX4   # already in ~/.zshrc

# Every install:
git pull && ./scripts/install_iphone.sh
```
Script: `scripts/install_iphone.sh` — builds with the personal team, signs under `com.neerajchormale.ironlog.dev`, installs via `xcrun devicectl`. Expires every 7 days (free Apple ID limit); re-run to refresh.

### iOS App — TestFlight (release)
```bash
scripts/build_ios_release.sh    # archive
scripts/upload_testflight.sh    # upload to App Store Connect (requires ASC credentials)
```

## Supabase Keep-alive
`.github/workflows/supabase-keepalive.yml` — runs daily at 09:00 UTC, pings `/rest/v1/exercises?select=id&limit=1` with `--retry 5`. Prevents free-tier auto-pause (which requires a manual restore if it fires).
