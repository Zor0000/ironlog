#  IronLog — Personal Gym Tracker

A beginner-friendly gym tracking PWA (Progressive Web App) that works on iPhone, Android, and desktop — **no App Store needed**.

## Features

- 💪 **Workout Suggestions** — Validated beginner exercises for Chest, Back, Legs, Shoulders, Arms, Core
- 🔀 **Split Support** — Full Body, PPL, Upper/Lower, Bro Split with day labeling
- 📝 **Set Logger** — Log weight (kg) + reps per set; mark sets as done
- ⏱️ **Rest Timer** — Auto-starts on set completion (1 min / 1:30 / 2 min / 3 min presets)
- 📅 **Workout History** — Full session history saved to database
- 🏆 **Personal Records** — Auto-detected and saved when you beat your best weight
- 📊 **Stats Dashboard** — Sessions, streak, sets, total volume
- 📆 **Weekly Activity Bar** — Visual 7-day overview
- 💧 **Water Tracker** — 8-glass daily counter
- 📝 **Session Notes** — Optional note after each workout
- 🔐 **Authentication** — Secure login via Supabase Auth (email/password)
- ☁️ **Cloud Database** — All data saved to Supabase (PostgreSQL) — persists forever

---

## Setup Instructions

### Step 1: Create a Supabase Project (Free)

1. Go to [https://supabase.com](https://supabase.com) and create a free account
2. Click **"New Project"**
3. Name it `ironlog`, pick a region close to you, set a database password
4. Wait ~2 minutes for it to provision

### Step 2: Set Up the Database

1. In your Supabase project, click **SQL Editor** in the left sidebar
2. Click **"New Query"**
3. Copy the entire contents of `supabase_schema.sql` and paste it in
4. Click **Run** — you should see "Success"

### Step 3: Get Your API Keys

1. In Supabase, go to **Settings → API**
2. Copy:
   - **Project URL** (looks like `https://xxxx.supabase.co`)
   - **anon / public key** (long string starting with `eyJ...`)

### Step 4: Add Keys to index.html

Open `index.html` and find these two lines near the top of the `<script>`:

```javascript
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

Replace with your actual values:

```javascript
const SUPABASE_URL = 'https://yourproject.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
```

---

## Deploy to GitHub Pages (Free Hosting)

### Step 1: Create GitHub Account
Go to [https://github.com](https://github.com) and sign up (free).

### Step 2: Create a New Repository

1. Click **"New"** (green button) or go to [https://github.com/new](https://github.com/new)
2. Repository name: `ironlog`
3. Set to **Public**
4. Do NOT initialize with README (you already have files)
5. Click **Create repository**

### Step 3: Upload Your Files

**Option A — Using GitHub website (easiest for Windows):**
1. On your new repo page, click **"uploading an existing file"**
2. Drag and drop both `index.html` and `supabase_schema.sql`
3. Click **"Commit changes"**

**Option B — Using Git on Windows:**
```bash
# Install Git from https://git-scm.com/ if not installed
git init
git add .
git commit -m "Initial commit — IronLog gym tracker"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/ironlog.git
git push -u origin main
```

### Step 4: Enable GitHub Pages

1. In your repo, go to **Settings → Pages**
2. Under "Source", select **"Deploy from a branch"**
3. Branch: **main** / folder: **/ (root)**
4. Click **Save**
5. Wait 1–2 minutes, then your app is live at:
   **`https://YOUR_USERNAME.github.io/ironlog`**

---

## Install on iPhone (No App Store Needed)

1. Open your GitHub Pages URL in **Safari** on iPhone
2. Tap the **Share button** (box with arrow)
3. Scroll down and tap **"Add to Home Screen"**
4. Tap **"Add"**
5. The app icon appears on your home screen — opens fullscreen like a native app! ✅

---

## Tech Stack

| Layer | Tech |
|-------|------|
| Frontend | Vanilla HTML/CSS/JS (single file) |
| Database | Supabase (PostgreSQL) |
| Auth | Supabase Auth (email/password) |
| Hosting | GitHub Pages (free) |
| Cost | **$0** total |

---

## Database Schema

```
auth.users          ← Supabase built-in auth
exercises           ← master exercise list (name, id)
sessions            ← each workout (user, muscle group, split, note, date)
session_sets        ← each set (session_id, exercise_id, weight_kg, reps)
personal_records    ← best weight per exercise per user (auto-updated)
```

All tables have **Row Level Security (RLS)** — users can only access their own data.
