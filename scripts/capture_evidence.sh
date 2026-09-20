#!/usr/bin/env bash
#
# capture_evidence.sh — deterministic screenshots of IronLog for PR evidence.
#
# Runs the scenarios in IronLogUITests/EvidenceCaptureTests.swift across a
# device × Dynamic Type matrix on the iOS Simulator, exports every screenshot
# with a stable name, and (optionally) publishes them to the `pr-evidence`
# orphan branch and prints a Markdown table you can paste into a PR.
#
#     scripts/capture_evidence.sh AddExercise                 # one scenario
#     scripts/capture_evidence.sh AddExercise ExerciseFinder  # several
#     scripts/capture_evidence.sh --all                       # every scenario
#
# Options
#     --devices compact,standard,large   which simulator classes (default: all)
#     --sizes default,ax                 Dynamic Type sizes (default: both)
#     --reduce-motion                    also capture with Reduce Motion on
#     --seed N                           seed for randomised features (default 7)
#     --out DIR                          output directory (default evidence/<UTC stamp>)
#     --publish LABEL                    push to pr-evidence/<LABEL>/ and print Markdown
#     --skip-build                       reuse the last build-for-testing products
#
# Output files: DIR/<device>-<size>[-reduce-motion]-<scenario>-<n>-<step>.png
#
# Determinism: clean store (UITest_ResetStore), fixed status bar (9:41, full
# battery), fixed content-size categories, UITest_Seed, and each screenshot
# waits on the element that marks its state. Re-running with the same inputs
# on the same simulator runtime should give pixel-identical output.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICES="compact,standard,large"
SIZES="default,ax"
REDUCE_MOTION=0
SEED=7
OUT=""
PUBLISH=""
SKIP_BUILD=0
ALL=0
SCENARIOS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --devices) DEVICES="$2"; shift 2 ;;
    --sizes) SIZES="$2"; shift 2 ;;
    --reduce-motion) REDUCE_MOTION=1; shift ;;
    --seed) SEED="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --publish) PUBLISH="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --all) ALL=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) SCENARIOS+=("$1"); shift ;;
  esac
done

if [[ $ALL -eq 1 ]]; then
  SCENARIOS=()
  while IFS= read -r line; do
    SCENARIOS+=("$line")
  done < <(grep -o 'func testScenario[A-Za-z0-9]*' IronLogUITests/EvidenceCaptureTests.swift | sed 's/func testScenario//')
fi
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  echo "usage: $0 [options] <Scenario>... | --all   (see --help)" >&2
  exit 2
fi

OUT="${OUT:-evidence/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# ── Simulator matrix ─────────────────────────────────────────────────────────
# Each class lists device names in order of preference; the first one that
# exists on this machine wins, so the script works on any recent Xcode.
device_candidates() {
  case "$1" in
    compact)  echo "iPhone SE (3rd generation)|iPhone 17e|iPhone 16e|iPhone 16|iPhone 17" ;;
    standard) echo "iPhone 17 Pro|iPhone 17|iPhone 16 Pro|iPhone 16|iPhone 18 Pro" ;;
    large)    echo "iPhone 18 Pro Max|iPhone 17 Pro Max|iPhone 16 Pro Max|iPhone 18 Pro" ;;
    *) echo "unknown device class: $1" >&2; exit 2 ;;
  esac
}

# Prefer a simulator whose runtime matches the newest available iOS.
resolve_udid() {
  local candidates="$1"
  xcrun simctl list -j devices available | python3 -c '
import json, sys
candidates = sys.argv[1].split("|")
devices = json.load(sys.stdin)["devices"]
found = {}
for runtime, items in devices.items():
    for d in items:
        if d.get("isAvailable", True) and d["name"] in candidates:
            found.setdefault(d["name"], []).append((runtime, d["udid"]))
for name in candidates:
    if name in found:
        runtime, udid = sorted(found[name])[-1]
        print("\t".join([udid, name, runtime.rsplit(".", 1)[-1]]))
        break
' "$candidates"
}

content_size_for() {
  case "$1" in
    default) echo "" ;;
    ax) echo "UICTContentSizeCategoryAccessibilityL" ;;
    ax-xxxl) echo "UICTContentSizeCategoryAccessibilityXXXL" ;;
    xl) echo "UICTContentSizeCategoryExtraLarge" ;;
    *) echo "unknown size: $1" >&2; exit 2 ;;
  esac
}

IFS=',' read -r -a DEVICE_CLASSES <<< "$DEVICES"
IFS=',' read -r -a SIZE_KEYS <<< "$SIZES"

declare -a UDIDS NAMES
for class in "${DEVICE_CLASSES[@]}"; do
  IFS=$'\t' read -r udid name runtime < <(resolve_udid "$(device_candidates "$class")")
  if [[ -z "${udid:-}" ]]; then
    echo "no simulator available for class '$class'" >&2
    exit 1
  fi
  echo "▸ $class → $name ($runtime) $udid"
  UDIDS+=("$udid"); NAMES+=("$name")
done

# ── Build once ───────────────────────────────────────────────────────────────
BUILD_DEST="id=${UDIDS[0]}"
if [[ $SKIP_BUILD -eq 0 ]]; then
  echo "▸ build-for-testing"
  xcodebuild build-for-testing \
    -project IronLog.xcodeproj -scheme IronLog \
    -destination "$BUILD_DEST" \
    CODE_SIGNING_ALLOWED=NO -quiet
fi

# ── Run the matrix ───────────────────────────────────────────────────────────
ONLY_TESTING=()
for s in "${SCENARIOS[@]}"; do
  ONLY_TESTING+=("-only-testing:IronLogUITests/EvidenceCaptureTests/testScenario${s}")
done

set_reduce_motion() {
  xcrun simctl spawn "$1" defaults write com.apple.Accessibility ReduceMotionEnabled -bool "$2" >/dev/null
}

# Copy every attachment out of a result bundle as
# <label>-<scenario>-<n>-<step>.png and echo how many there were.
export_screenshots() {
  local bundle="$1" label="$2"
  local export_dir="$OUT/.export/$label"
  rm -r -f "$export_dir"; mkdir -p "$export_dir"
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$export_dir" >/dev/null 2>&1 || true
  python3 - "$export_dir" "$OUT" "$label" <<'PY'
import json, os, re, shutil, sys
export_dir, out, label = sys.argv[1:4]
path = os.path.join(export_dir, "manifest.json")
count = 0
if os.path.exists(path):
    for test in json.load(open(path)):
        for att in test.get("attachments", []):
            name = re.sub(r"_\d+_[0-9A-F-]+", "", att["suggestedHumanReadableName"])
            if not name.endswith(".png"):
                name += ".png"
            shutil.copy(os.path.join(export_dir, att["exportedFileName"]), os.path.join(out, f"{label}-{name}"))
            count += 1
print(count)
PY
}

FAILED_LABELS=()

run_one() {
  local udid="$1" class="$2" size="$3" motion="$4"
  local label="$class-$size"
  [[ "$motion" == "1" ]] && label="$label-reduce-motion"
  local bundle="$OUT/.xcresult/$label.xcresult"
  local log="$OUT/.logs/$label.log"
  local category
  category="$(content_size_for "$size")"
  mkdir -p "$OUT/.logs"

  echo "▸ capture $label"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override \
    --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null
  set_reduce_motion "$udid" "$([[ "$motion" == "1" ]] && echo true || echo false)"

  local attempt count=0
  # A simulator still tearing down the previous session can make xcodebuild
  # bail before any test runs; one retry covers that.
  for attempt in 1 2; do
    rm -r -f "$bundle"
    TEST_RUNNER_EVIDENCE_CAPTURE=1 \
    TEST_RUNNER_EVIDENCE_CONTENT_SIZE="$category" \
    TEST_RUNNER_EVIDENCE_SEED="$SEED" \
    xcodebuild test-without-building \
      -project IronLog.xcodeproj -scheme IronLog \
      -destination "id=$udid" \
      "${ONLY_TESTING[@]}" \
      -resultBundlePath "$bundle" \
      CODE_SIGNING_ALLOWED=NO > "$log" 2>&1 || true
    count="$(export_screenshots "$bundle" "$label")"
    [[ "$count" -gt 0 ]] && break
    echo "  attempt $attempt produced no screenshots; see $log"
    sleep 5
  done

  set_reduce_motion "$udid" false
  xcrun simctl status_bar "$udid" clear >/dev/null

  grep -E "Test Case .* failed|error:" "$log" | sed 's/^/  /' || true
  echo "  $count screenshots"
  [[ "$count" -gt 0 ]] || FAILED_LABELS+=("$label")
}

for i in "${!UDIDS[@]}"; do
  for size in "${SIZE_KEYS[@]}"; do
    run_one "${UDIDS[$i]}" "${DEVICE_CLASSES[$i]}" "$size" 0
  done
  if [[ $REDUCE_MOTION -eq 1 ]]; then
    run_one "${UDIDS[$i]}" "${DEVICE_CLASSES[$i]}" default 1
  fi
done

# Manifest of what was captured with what, so the evidence is reproducible.
{
  echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "commit: $(git rev-parse --short HEAD)"
  echo "seed: $SEED"
  echo "scenarios: ${SCENARIOS[*]}"
  for i in "${!UDIDS[@]}"; do echo "device ${DEVICE_CLASSES[$i]}: ${NAMES[$i]} (${UDIDS[$i]})"; done
  echo "sizes: $SIZES  reduce-motion: $REDUCE_MOTION"
  echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
} > "$OUT/MANIFEST.txt"

echo "▸ done: $(/bin/ls "$OUT"/*.png | wc -l | tr -d ' ') screenshots in $OUT"
if [[ ${#FAILED_LABELS[@]} -gt 0 ]]; then
  echo "▸ FAILED: ${FAILED_LABELS[*]} (logs in $OUT/.logs)" >&2
  exit 1
fi

# ── Publish ──────────────────────────────────────────────────────────────────
# Images go to an orphan branch so nothing binary ever lands in main. The
# Markdown printed at the end links to raw.githubusercontent.com.
if [[ -n "$PUBLISH" ]]; then
  remote_url="$(git config --get remote.origin.url)"
  slug="$(echo "$remote_url" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
  commit="$(git rev-parse --short HEAD)"
  work="$(mktemp -d)"
  git clone -q --no-checkout "$remote_url" "$work"
  (
    cd "$work"
    if git fetch -q origin pr-evidence 2>/dev/null; then
      git checkout -q pr-evidence
    else
      git checkout -q --orphan pr-evidence
      git read-tree --empty
      printf '# PR evidence\n\nScreenshots referenced from pull requests. Not merged into main.\n' > README.md
    fi
    mkdir -p "$PUBLISH"
    for f in "$OUT"/*.png; do
      # Downscale for the PR page; the full-resolution originals stay in $OUT.
      sips -Z 1200 "$f" --out "$PUBLISH/$(basename "$f")" >/dev/null
    done
    cp "$OUT/MANIFEST.txt" "$PUBLISH/"
    git add -A
    git commit -qm "Evidence: $PUBLISH ($commit)" || true
    git push -q origin pr-evidence
  )
  echo
  echo "## Evidence"
  echo
  echo "Captured with \`scripts/capture_evidence.sh ${SCENARIOS[*]} --seed $SEED --publish $PUBLISH\` at $commit (see \`$PUBLISH/MANIFEST.txt\` on the \`pr-evidence\` branch)."
  echo
  for s in "${SCENARIOS[@]}"; do
    scen="$(echo "$s" | tr '[:upper:]' '[:lower:]')"
    echo "### $s"
    echo
    for i in "${!UDIDS[@]}"; do
      labels=()
      for size in "${SIZE_KEYS[@]}"; do labels+=("${DEVICE_CLASSES[$i]}-$size"); done
      [[ $REDUCE_MOTION -eq 1 ]] && labels+=("${DEVICE_CLASSES[$i]}-default-reduce-motion")
      for label in "${labels[@]}"; do
        files=("$OUT"/"$label"-"$scen"-*.png)
        [[ -e "${files[0]}" ]] || continue
        echo "**${NAMES[$i]} · ${label#${DEVICE_CLASSES[$i]}-}**"
        echo
        header=""; sep=""; row=""
        for f in "${files[@]}"; do
          b="$(basename "$f" .png)"
          rest="${b##*-$scen-}"   # "<n>-<step>"
          step="${rest#*-}"
          header+="| $step "; sep+="|---"; row+="| ![]($(printf 'https://raw.githubusercontent.com/%s/pr-evidence/%s/%s.png' "$slug" "$PUBLISH" "$b")) "
        done
        echo "$header|"; echo "$sep|"; echo "$row|"; echo
      done
    done
  done
fi
