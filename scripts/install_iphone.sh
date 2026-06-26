#!/usr/bin/env bash
#
# install_iphone.sh — build IronLog and install it on a connected iPhone using
# your OWN free Apple ID (a personal team), no TestFlight and no paid account.
#
# Day-to-day use, after the one-time setup below:
#
#     git pull && ./scripts/install_iphone.sh
#
# It signs with command-line overrides only, so it does NOT disturb the App
# Store / TestFlight release config (which still targets the original team).
# It installs under a separate bundle id (…ironlog.dev) so this dev build sits
# next to the TestFlight build as its own icon instead of replacing it.
#
# ───────────────────────── ONE-TIME SETUP (you do this once) ─────────────────
#  1. Connect your iPhone with a cable. On the phone tap "Trust This Computer"
#     and enter your passcode.
#  2. Open IronLog.xcodeproj in Xcode → click the "IronLog" target → Signing &
#     Capabilities → check "Automatically manage signing" → under Team, "Add an
#     Account…" and sign in with your normal (free) Apple ID. Pick the team that
#     looks like "Your Name (Personal Team)".
#  3. With your iPhone selected as the run destination, press ⌘R once. Xcode
#     registers the device and creates a free development profile. (You can stop
#     the app right after it launches.)
#  4. On the iPhone: Settings → General → VPN & Device Management → tap your
#     developer Apple ID → Trust.
#  5. Find your Team ID: Xcode → Settings (⌘,) → Accounts → select your Apple ID
#     → it's the 10-character string next to your Personal Team. Put it below or
#     export it: `export IRONLOG_TEAM_ID=XXXXXXXXXX`
#
#  After that, every future install is just running this script. NOTE: free
#  Apple ID builds STOP LAUNCHING AFTER 7 DAYS — just re-run this script to
#  refresh the 7-day clock.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
cd "$(dirname "$0")/.."

# --- config (override via env) ----------------------------------------------
TEAM_ID="${IRONLOG_TEAM_ID:-}"                 # your Personal Team ID (required)
DEV_BUNDLE_ID="${IRONLOG_DEV_BUNDLE_ID:-com.neerajchormale.ironlog.dev}"
SCHEME="IronLog"
PROJECT="IronLog.xcodeproj"
DERIVED="build/dd-device"

if [[ -z "$TEAM_ID" ]]; then
  cat >&2 <<'EOF'
✗ No Team ID set.
  Set it once with:  export IRONLOG_TEAM_ID=XXXXXXXXXX
  (Xcode → Settings → Accounts → your Apple ID → 10-char Team ID next to
   "Your Name (Personal Team)"), then re-run this script.
EOF
  exit 1
fi

# --- find a connected device -------------------------------------------------
echo "▸ Looking for a connected iPhone…"
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT
xcrun devicectl list devices --json-output "$TMP_JSON" >/dev/null 2>&1 || true

DEVICE_ID="$(/usr/bin/python3 - "$TMP_JSON" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for d in data.get("result", {}).get("devices", []):
    conn = (d.get("connectionProperties", {}) or {}).get("tunnelState", "")
    props = d.get("deviceProperties", {}) or {}
    hw = d.get("hardwareProperties", {}) or {}
    # iPhones only, that are paired/connected
    if "iPhone" in (hw.get("productType","") or hw.get("deviceType","")) or "iPhone" in props.get("name",""):
        if d.get("identifier"):
            print(d["identifier"]); break
PY
)"

if [[ -z "${DEVICE_ID:-}" ]]; then
  cat >&2 <<'EOF'
✗ No iPhone detected.
  • Plug the phone in with a cable (or, if already paired, make sure it's
    unlocked and on the same Wi-Fi).
  • If this is the first time, tap "Trust This Computer" on the phone.
  Then re-run this script.
EOF
  exit 1
fi
echo "  found device: $DEVICE_ID"

# --- build (signed with your personal team, dev bundle id) -------------------
# BASE_BUNDLE_ID drives BOTH targets: the app becomes $DEV_BUNDLE_ID and the
# Live Activity widget becomes $DEV_BUNDLE_ID.IronLogWidget, so they stay a
# matching app/extension pair without colliding.
echo "▸ Building $SCHEME for device (team $TEAM_ID, bundle $DEV_BUNDLE_ID)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  BASE_BUNDLE_ID="$DEV_BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  build

APP_PATH="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "✗ Build succeeded but app not found at $APP_PATH" >&2
  exit 1
fi

# --- install + launch --------------------------------------------------------
echo "▸ Installing onto device…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "▸ Launching…"
xcrun devicectl device process launch --device "$DEVICE_ID" "$DEV_BUNDLE_ID" >/dev/null 2>&1 || true

echo "✓ Done. IronLog (dev) is on your iPhone. Re-run within 7 days to keep it alive."
