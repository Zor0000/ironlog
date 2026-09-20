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
#     --clean                            empty an existing --out DIR first
#     --publish LABEL                    push to pr-evidence/<LABEL>/ and print Markdown
#     --allow-dirty                      publish even with uncommitted changes
#     --skip-build                       reuse the last build-for-testing products
#
# Output files: DIR/<device>-<size>[-reduce-motion]-<scenario>-<nn>-<step>.png
#
# Determinism: clean store (UITest_ResetStore), fixed status bar (9:41, full
# battery), en_US + UTC, an explicit content-size category, UITest_Seed, and
# each screenshot waits on the element that marks its state. Re-running with
# the same inputs on the same simulator runtime should give identical output.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICES="compact,standard,large"
SIZES="default,ax"
REDUCE_MOTION=0
SEED=7
OUT=""
CLEAN=0
PUBLISH=""
ALLOW_DIRTY=0
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
    --clean) CLEAN=1; shift ;;
    --publish) PUBLISH="$2"; shift 2 ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --all) ALL=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) SCENARIOS+=("$1"); shift ;;
  esac
done

# `--publish` names one directory on the pr-evidence branch.  Keep it a
# single, ordinary path component: the publish cleanup runs from a clone, but
# an absolute path or traversal component would make it operate outside it.
if [[ -n "$PUBLISH" ]]; then
  if [[ ! "$PUBLISH" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "invalid --publish label '$PUBLISH': use a single label containing only letters, digits, dots, underscores, or hyphens" >&2
    exit 2
  fi
fi

if [[ $ALL -eq 1 ]]; then
  SCENARIOS=()
  while IFS= read -r line; do
    SCENARIOS+=("$line")
  done < <(grep -oE 'func testScenario[A-Za-z0-9]+\(' IronLogUITests/EvidenceCaptureTests.swift | sed -E 's/func testScenario([A-Za-z0-9]+)\(/\1/')
fi
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  echo "usage: $0 [options] <Scenario>... | --all   (see --help)" >&2
  exit 2
fi

# ── Output directory ─────────────────────────────────────────────────────────
# A reused directory must not mix runs: the manifest describes exactly what is
# in it, so refuse leftovers unless asked to clear them.
OUT="${OUT:-evidence/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
if [[ -n "$(/bin/ls -A "$OUT")" ]]; then
  if [[ $CLEAN -eq 1 ]]; then
    find "$OUT" -mindepth 1 -maxdepth 1 -exec rm -r -f {} +
  else
    echo "output directory is not empty: $OUT (pass --clean to empty it)" >&2
    exit 2
  fi
fi

# ── Source state ─────────────────────────────────────────────────────────────
COMMIT="$(git rev-parse --short HEAD)"
DIRTY=0
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  DIRTY=1
  echo "▸ warning: worktree has uncommitted changes; evidence will be stamped $COMMIT+dirty"
fi
if [[ -n "$PUBLISH" && $DIRTY -eq 1 && $ALLOW_DIRTY -eq 0 ]]; then
  echo "refusing to publish from a dirty worktree (commit first, or pass --allow-dirty)" >&2
  exit 2
fi
STAMP="$COMMIT"; [[ $DIRTY -eq 1 ]] && STAMP="$COMMIT+dirty"

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

# The "default" entry is passed explicitly (Large), never inherited from the
# simulator, so a hand-changed Dynamic Type setting can't leak into a capture.
content_size_for() {
  case "$1" in
    default) echo "UICTContentSizeCategoryL" ;;
    xl) echo "UICTContentSizeCategoryExtraLarge" ;;
    ax) echo "UICTContentSizeCategoryAccessibilityL" ;;
    ax-xxxl) echo "UICTContentSizeCategoryAccessibilityXXXL" ;;
    *) echo "unknown size: $1" >&2; exit 2 ;;
  esac
}

IFS=',' read -r -a DEVICE_CLASSES <<< "$DEVICES"
IFS=',' read -r -a SIZE_KEYS <<< "$SIZES"

declare -a UDIDS NAMES RUNTIMES
for class in "${DEVICE_CLASSES[@]}"; do
  IFS=$'\t' read -r udid name runtime < <(resolve_udid "$(device_candidates "$class")")
  if [[ -z "${udid:-}" ]]; then
    echo "no simulator available for class '$class'" >&2
    exit 1
  fi
  echo "▸ $class → $name ($runtime) $udid"
  UDIDS+=("$udid"); NAMES+=("$name"); RUNTIMES+=("$runtime")
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

read_reduce_motion() {
  xcrun simctl spawn "$1" defaults read com.apple.Accessibility ReduceMotionEnabled 2>/dev/null || echo 0
}

set_reduce_motion() {
  xcrun simctl spawn "$1" defaults write com.apple.Accessibility ReduceMotionEnabled -bool "$2" >/dev/null
}

# Copy every attachment out of a result bundle as
# <label>-<scenario>-<nn>-<step>.png and echo how many there were.
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
  # Remember the developer's own Reduce Motion preference and put it back.
  local previous_motion
  previous_motion="$(read_reduce_motion "$udid")"
  set_reduce_motion "$udid" "$([[ "$motion" == "1" ]] && echo true || echo false)"

  local attempt status=0 count=0
  # A simulator still tearing down the previous session can make xcodebuild
  # bail before any test runs (non-zero exit, no attachments); one retry covers
  # that. A genuine test failure (non-zero exit *with* attachments) is not
  # retried and fails the run.
  for attempt in 1 2; do
    rm -r -f "$bundle"
    status=0
    TEST_RUNNER_EVIDENCE_CAPTURE=1 \
    TEST_RUNNER_EVIDENCE_CONTENT_SIZE="$category" \
    TEST_RUNNER_EVIDENCE_SEED="$SEED" \
    xcodebuild test-without-building \
      -project IronLog.xcodeproj -scheme IronLog \
      -destination "id=$udid" \
      "${ONLY_TESTING[@]}" \
      -resultBundlePath "$bundle" \
      CODE_SIGNING_ALLOWED=NO > "$log" 2>&1 || status=$?
    count="$(export_screenshots "$bundle" "$label")"
    [[ $status -eq 0 || $count -gt 0 ]] && break
    echo "  attempt $attempt: xcodebuild exited $status before any test ran; retrying (see $log)"
    sleep 5
  done

  set_reduce_motion "$udid" "$([[ "$previous_motion" == "1" ]] && echo true || echo false)"
  xcrun simctl status_bar "$udid" clear >/dev/null

  grep -E "Test Case .* failed|error:" "$log" | sed 's/^/  /' || true
  if [[ $status -ne 0 ]]; then
    echo "  FAILED (xcodebuild exit $status, $count screenshots) — see $log"
    FAILED_LABELS+=("$label")
  else
    echo "  $count screenshots"
  fi
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
  echo "commit: $STAMP"
  echo "seed: $SEED"
  echo "scenarios: ${SCENARIOS[*]}"
  for i in "${!UDIDS[@]}"; do echo "device ${DEVICE_CLASSES[$i]}: ${NAMES[$i]} · ${RUNTIMES[$i]} (${UDIDS[$i]})"; done
  echo "sizes: $SIZES  reduce-motion: $REDUCE_MOTION  locale: en_US  tz: UTC"
  echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
} > "$OUT/MANIFEST.txt"

echo "▸ done: $(/bin/ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') screenshots in $OUT"
if [[ ${#FAILED_LABELS[@]} -gt 0 ]]; then
  echo "▸ FAILED: ${FAILED_LABELS[*]} — not publishing incomplete evidence (logs in $OUT/.logs)" >&2
  exit 1
fi

# ── Publish ──────────────────────────────────────────────────────────────────
# Images go to an orphan branch so nothing binary ever lands in main. The
# Markdown printed at the end links to raw.githubusercontent.com.
if [[ -n "$PUBLISH" ]]; then
  remote_url="$(git config --get remote.origin.url)"
  slug="$(echo "$remote_url" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
  work="$(mktemp -d)"
  trap 'rm -r -f "$work"' EXIT
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
    rm -r -f "$PUBLISH"; mkdir -p "$PUBLISH"
    for f in "$OUT"/*.png; do
      # Downscale for the PR page; the full-resolution originals stay in $OUT.
      sips -Z 1200 "$f" --out "$PUBLISH/$(basename "$f")" >/dev/null
    done
    cp "$OUT/MANIFEST.txt" "$PUBLISH/"
    git add -A
    if git diff --cached --quiet; then
      echo "▸ pr-evidence/$PUBLISH already up to date"
    else
      git commit -qm "Evidence: $PUBLISH ($STAMP)"
      git push -q origin pr-evidence
    fi
  )
  echo
  echo "## Evidence"
  echo
  echo "Captured with \`scripts/capture_evidence.sh ${SCENARIOS[*]} --seed $SEED --publish $PUBLISH\` at $STAMP (see \`$PUBLISH/MANIFEST.txt\` on the \`pr-evidence\` branch)."
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
        # Step numbers are zero-padded, but sort numerically anyway so an
        # older, unpadded capture still comes out in order.
        while IFS= read -r f; do
          b="$(basename "$f" .png)"
          rest="${b##*-$scen-}"   # "<nn>-<step>"
          step="${rest#*-}"
          header+="| $step "; sep+="|---"; row+="| ![]($(printf 'https://raw.githubusercontent.com/%s/pr-evidence/%s/%s.png' "$slug" "$PUBLISH" "$b")) "
        done < <(printf '%s\n' "${files[@]}" | awk -v scen="$scen" '{ n=$0; sub(".*-" scen "-", "", n); sub("-.*", "", n); print n+0 "\t" $0 }' | sort -n | cut -f2-)
        echo "$header|"; echo "$sep|"; echo "$row|"; echo
      done
    done
  done
fi
