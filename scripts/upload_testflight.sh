#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IPA_PATH="${IPA_PATH:-$ROOT_DIR/build/export/IronLog.ipa}"
APP_ID="${ASC_APP_ID:-}"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "Missing IPA at $IPA_PATH"
  echo "Run from repo root:"
  echo "  xcodebuild -project IronLog.xcodeproj -scheme IronLog -destination 'generic/platform=iOS' -archivePath build/IronLog.xcarchive archive"
  echo "  xcodebuild -exportArchive -archivePath build/IronLog.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates"
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

unzip -q "$IPA_PATH" -d "$tmp_dir"
app_info_plist="$(find "$tmp_dir/Payload" -maxdepth 2 -name Info.plist -print -quit)"
if [[ -z "$app_info_plist" ]]; then
  echo "Could not find Info.plist inside $IPA_PATH"
  exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_info_plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_info_plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_info_plist")"

if command -v asc >/dev/null 2>&1 && [[ -n "$APP_ID" ]]; then
  if [[ -n "${ASC_API_KEY_ID:-}" && -n "${ASC_API_ISSUER_ID:-}" && -n "${ASC_API_PRIVATE_KEY_PATH:-}" ]]; then
    asc auth login \
      --name ironlog \
      --key-id "$ASC_API_KEY_ID" \
      --issuer-id "$ASC_API_ISSUER_ID" \
      --private-key "$ASC_API_PRIVATE_KEY_PATH"
  fi

  asc builds upload \
    --app "$APP_ID" \
    --ipa "$IPA_PATH" \
    --version "$version" \
    --build-number "$build_number" \
    --platform IOS \
    --wait
elif [[ -n "${ASC_API_KEY_ID:-}" && -n "${ASC_API_ISSUER_ID:-}" ]]; then
  xcrun altool --upload-package "$IPA_PATH" \
    --api-key "$ASC_API_KEY_ID" \
    --api-issuer "$ASC_API_ISSUER_ID"
elif [[ -n "${ASC_USERNAME:-}" && -n "${ASC_APP_PASSWORD:-}" && -n "${ASC_PROVIDER_PUBLIC_ID:-}" ]]; then
  xcrun altool --upload-package "$IPA_PATH" \
    --username "$ASC_USERNAME" \
    --app-password "$ASC_APP_PASSWORD" \
    --provider-public-id "$ASC_PROVIDER_PUBLIC_ID"
else
  cat <<'MSG'
Missing App Store Connect upload credentials.

Preferred asc CLI upload:
  asc auth login --name ironlog --key-id <KEY_ID> --issuer-id <ISSUER_ID> --private-key-path /path/to/AuthKey_<KEY_ID>.p8
  ASC_APP_ID=<app-store-connect-app-id> scripts/upload_testflight.sh

One-shot asc CLI auth + upload:
  ASC_APP_ID=<app-store-connect-app-id> \
  ASC_API_KEY_ID=<KEY_ID> \
  ASC_API_ISSUER_ID=<ISSUER_ID> \
  ASC_API_PRIVATE_KEY_PATH=/path/to/AuthKey_<KEY_ID>.p8 \
  scripts/upload_testflight.sh

altool API key fallback:
  mkdir -p ~/.appstoreconnect/private_keys
  cp AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
  ASC_API_KEY_ID=<KEY_ID> ASC_API_ISSUER_ID=<ISSUER_ID> scripts/upload_testflight.sh

Or app-specific password auth:
  ASC_USERNAME=<apple-id-email> ASC_APP_PASSWORD=<app-password> ASC_PROVIDER_PUBLIC_ID=<provider-id> scripts/upload_testflight.sh

The App Store Connect app record for this IPA must exist before upload.
MSG
  echo
  echo "Detected IPA:"
  echo "  Bundle ID: $bundle_id"
  echo "  Version:   $version"
  echo "  Build:     $build_number"
  exit 2
fi
