#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_NUMBER="${BUILD_NUMBER:-}"

if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "BUILD_NUMBER must contain only digits: $BUILD_NUMBER"
  exit 1
fi

build_settings=()
if [[ -n "$BUILD_NUMBER" ]]; then
  build_settings+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi

authentication_args=()
if [[ -n "${ASC_API_PRIVATE_KEY_PATH:-}" || -n "${ASC_API_KEY_ID:-}" || -n "${ASC_API_ISSUER_ID:-}" ]]; then
  if [[ -z "${ASC_API_PRIVATE_KEY_PATH:-}" || -z "${ASC_API_KEY_ID:-}" || -z "${ASC_API_ISSUER_ID:-}" ]]; then
    echo "ASC_API_PRIVATE_KEY_PATH, ASC_API_KEY_ID, and ASC_API_ISSUER_ID must be set together"
    exit 1
  fi

  if [[ ! -f "$ASC_API_PRIVATE_KEY_PATH" ]]; then
    echo "Missing App Store Connect API key at $ASC_API_PRIVATE_KEY_PATH"
    exit 1
  fi

  authentication_args=(
    -authenticationKeyPath "$ASC_API_PRIVATE_KEY_PATH"
    -authenticationKeyID "$ASC_API_KEY_ID"
    -authenticationKeyIssuerID "$ASC_API_ISSUER_ID"
  )
fi

cd "$ROOT_DIR"

simulator_build=(
  xcodebuild
  -project IronLog.xcodeproj
  -scheme IronLog
  -destination 'generic/platform=iOS Simulator'
)
if (( ${#build_settings[@]} > 0 )); then
  simulator_build+=("${build_settings[@]}")
fi
simulator_build+=(build)
"${simulator_build[@]}"

rm -rf build/IronLog.xcarchive build/export

archive_build=(
  xcodebuild
  -project IronLog.xcodeproj
  -scheme IronLog
  -destination 'generic/platform=iOS'
  -archivePath build/IronLog.xcarchive
  -allowProvisioningUpdates
)
if (( ${#authentication_args[@]} > 0 )); then
  archive_build+=("${authentication_args[@]}")
fi
if (( ${#build_settings[@]} > 0 )); then
  archive_build+=("${build_settings[@]}")
fi
archive_build+=(archive)
"${archive_build[@]}"

export_build=(
  xcodebuild
  -exportArchive
  -archivePath build/IronLog.xcarchive
  -exportPath build/export
  -exportOptionsPlist ExportOptions.plist
  -allowProvisioningUpdates
)
if (( ${#authentication_args[@]} > 0 )); then
  export_build+=("${authentication_args[@]}")
fi
"${export_build[@]}"

echo "Exported build/export/IronLog.ipa"
