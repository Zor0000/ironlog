#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

xcodebuild -project IronLog.xcodeproj \
  -scheme IronLog \
  -destination 'generic/platform=iOS Simulator' \
  build

rm -rf build/IronLog.xcarchive build/export

xcodebuild -project IronLog.xcodeproj \
  -scheme IronLog \
  -destination 'generic/platform=iOS' \
  -archivePath build/IronLog.xcarchive \
  -allowProvisioningUpdates \
  archive

xcodebuild -exportArchive \
  -archivePath build/IronLog.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates

echo "Exported build/export/IronLog.ipa"
