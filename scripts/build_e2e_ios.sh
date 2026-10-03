#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
setzo_device="${SETZO_E2E_DEVICE:-}"
if [[ -z "$setzo_device" ]]; then
  setzo_device="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next((d["udid"] for devices in json.load(sys.stdin)["devices"].values() for d in devices if d["name"] == "Setzo E2E"), ""))')"
fi
if [[ -z "$setzo_device" ]]; then
  setzo_runtime="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in reversed(json.load(sys.stdin)["runtimes"]) if r.get("isAvailable") and r["name"].startswith("iOS")))')"
  setzo_type="$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; print(next(d["identifier"] for d in reversed(json.load(sys.stdin)["devicetypes"]) if d["name"].startswith("iPhone") and "Max" not in d["name"]))')"
  setzo_device="$(xcrun simctl create 'Setzo E2E' "$setzo_type" "$setzo_runtime")"
fi
# A named/UDID simulator is explicit. Never select an arbitrary booted device.
xcrun simctl boot "$setzo_device" 2>/dev/null || true
xcrun simctl bootstatus "$setzo_device" -b
setzo_derived="${SETZO_E2E_DERIVED_DATA:-$PWD/build/e2e/DerivedData}"
xcodebuild -project Setzo.xcodeproj -scheme Setzo -configuration Debug \
  -destination "platform=iOS Simulator,id=$setzo_device" -derivedDataPath "$setzo_derived" \
  CODE_SIGNING_ALLOWED=NO build-for-testing
printf '\nSETZO_E2E_DEVICE=%s\nSETZO_E2E_DERIVED_DATA=%s\n' "$setzo_device" "$setzo_derived"
