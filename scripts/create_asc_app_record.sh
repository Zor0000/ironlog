#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-IronLog}"
BUNDLE_ID="${BUNDLE_ID:-com.parthjadhav.ironlog}"
SKU="${SKU:-ironlog-ios}"
PRIMARY_LOCALE="${PRIMARY_LOCALE:-en-US}"
VERSION="${VERSION:-1.0}"

if ! command -v asc >/dev/null 2>&1; then
  cat <<'MSG'
Missing asc CLI.

Install it with:
  brew install tddworks/tap/asccli
MSG
  exit 1
fi

cat <<MSG
Creating App Store Connect app record with asc iris:
  Name:           $APP_NAME
  Bundle ID:      $BUNDLE_ID
  SKU:            $SKU
  Primary locale: $PRIMARY_LOCALE
  Version:        $VERSION

This requires an active asc iris web session. If needed, run:
  asc iris auth login
  asc iris auth verify-code
MSG

asc iris apps create \
  --name "$APP_NAME" \
  --bundle-id "$BUNDLE_ID" \
  --sku "$SKU" \
  --primary-locale "$PRIMARY_LOCALE" \
  --platforms IOS \
  --version "$VERSION" \
  --pretty
