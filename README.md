# IronLog — Personal Gym Tracker

A beginner-friendly gym tracking app available as a **Native iOS App** and a **Progressive Web App (PWA)**. Completely free, no ads, no build step.

## Features

- **Workout Suggestions** — 100+ validated exercises across Chest, Back, Legs, Shoulders, Biceps, Triceps, Core — each with form tips and default sets/reps
- **Exercise Catalog Search** — search and filter exercises by muscle group while logging
- **Split Support** — Full Body, PPL, Upper/Lower, Bro Split with day labeling; multi-muscle days start in a single session
- **Set Logger** — log weight (kg) + reps per set; mark sets as done with haptic feedback
- **Custom Exercises** — add any exercise mid-workout (Reps only or Weight + Reps)
- **Free Workout Mode** — start a blank session without picking a muscle group
- **Confirm Before Discard** — modal confirmation protects against accidental workout loss
- **Draft Persistence** — in-progress workout survives app restarts and screen locks
- **Rest Timer** — auto-restarts from full preset on every completed set (1 min / 1:30 / 2 min / 3 min)
- **Workout History** — full session history saved to the database
- **Personal Records** — auto-detected and saved when you beat your best weight
- **Stats Dashboard** — sessions, streak, sets, total volume, weekly activity
- **Water Tracker** — 8-glass daily counter
- **Authentication** — secure login via Supabase Auth (email/password)
- **Cloud Database** — all data saved to Supabase (PostgreSQL) with Row Level Security

---

## Architecture & Tech Stack

IronLog uses a shared Supabase backend with two separate frontend clients.

| Layer | Technology |
|-------|------------|
| **Backend** | Supabase (PostgreSQL, Auth, Row Level Security) |
| **Web PWA** | Vanilla HTML / CSS / JS — no build step |
| **iOS App** | Swift, SwiftUI — zero third-party SDK dependencies |
| **Web Testing** | Python + Playwright |

---

## Backend Setup (Required for both clients)

### Step 1: Create a Supabase Project
1. Go to [supabase.com](https://supabase.com) and create a free account.
2. Click **New Project**, name it `ironlog`, set a database password.
3. Wait ~2 minutes for provisioning.

### Step 2: Set Up the Database
1. In your Supabase project, open **SQL Editor → New Query**.
2. Paste the contents of `supabase_schema.sql` and click **Run**.

### Step 3: Get Your API Keys
1. Go to **Settings → API**.
2. Copy your **Project URL** and **anon / public key** — you'll need these below.

---

## Option A: iOS App (Native)

The iOS app is built in SwiftUI. It calls the Supabase REST API directly via `URLSession` — no third-party SDKs, no CocoaPods.

### Prerequisites
- macOS with **Xcode** installed (Xcode 15 or later)
- The `.xcodeproj` is committed — no XcodeGen step needed

### Setup
1. Clone the repo.
2. In `IronLog/Services/SupabaseService.swift`, replace `supabaseURL` and `supabaseKey` with your keys from Step 3.
3. Open `IronLog.xcodeproj` in Xcode.
4. Select a Simulator or your iPhone and press **⌘R**.

### Install Directly to Your iPhone (Free, No TestFlight)

You can build and install IronLog on your own iPhone using a free Apple ID — no paid developer account needed.

**One-time setup (do this once):**

1. Connect your iPhone by cable → tap **Trust This Computer** on the phone.
2. In Xcode, open the **IronLog** target → **Signing & Capabilities** → tick **Automatically manage signing** → set **Team** to your Personal Team (add your free Apple ID via **Add an Account…** if not listed).
3. With your iPhone selected, press **⌘R** once to register the device. You can stop the build once it starts.
4. On the iPhone: **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**.
5. Enable **Developer Mode**: **Settings → Privacy & Security → Developer Mode → ON** → restart → confirm.
6. Find your Team ID: **Xcode → Settings (⌘,) → Accounts → your Apple ID** → the 10-character code next to your Personal Team. Then:
   ```bash
   echo 'export IRONLOG_TEAM_ID=XXXXXXXXXX' >> ~/.zshrc && source ~/.zshrc
   ```

**Every install after that:**
```bash
git pull && ./scripts/install_iphone.sh
```

The script builds with your personal team, signs under a `.dev` bundle ID (so it coexists with any TestFlight build), and installs directly to the connected phone.

> **Note:** Free Apple ID builds expire after **7 days**. Re-run the script to reset the clock — no need to redo the setup steps.

---

## Option B: Web PWA

### Step 1: Add Your Supabase Keys
Open `index.html` and replace the placeholders near the top of the `<script>` block:

```javascript
const SUPABASE_URL = 'https://yourproject.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
```

### Step 2: Deploy to GitHub Pages
1. Push to a public GitHub repo (`main` branch).
2. Go to **Settings → Pages → Deploy from branch** (`main`, root `/`).
3. Your PWA is live at `https://YOUR_USERNAME.github.io/ironlog`.

### Install as PWA on iPhone
1. Open the GitHub Pages URL in **Safari** on your iPhone.
2. Tap the **Share** button → **Add to Home Screen**.
3. The app opens fullscreen like a native app.

---

## Database Schema

```
auth.users       ← Supabase built-in auth
exercises        ← master exercise list (name, id)
sessions         ← each workout (user, muscle group, split, note, date)
session_sets     ← each set (session_id, exercise_id, weight_kg, reps)
personal_records ← best weight per exercise per user (auto-updated on save)
```

All tables have **Row Level Security (RLS)** — users can only access their own data.

---

## Supabase Keep-Alive

The free Supabase tier auto-pauses projects after ~1 week of inactivity. A GitHub Actions workflow ([`.github/workflows/supabase-keepalive.yml`](.github/workflows/supabase-keepalive.yml)) pings the REST endpoint **daily** to prevent this. If your project ever pauses anyway, restore it from the Supabase dashboard or via the Supabase MCP.

---

## Development

### Web PWA
```bash
python -m http.server 8765   # local server
python test_features.py      # Playwright tests
```

### iOS App
```bash
# Run in simulator
xcodebuild -project IronLog.xcodeproj -scheme IronLog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Install to connected iPhone
IRONLOG_TEAM_ID=XXXXXXXXXX ./scripts/install_iphone.sh
```
