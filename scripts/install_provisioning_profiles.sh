#!/usr/bin/env bash
# Put the App Store provisioning profiles on this machine, ready for an archive.
#
# Release signing is manual precisely so that nothing can be minted mid-build.
# The archive names this certificate and these two profiles; if any of them is
# missing the build stops, rather than quietly asking Apple for a new signing
# certificate and filling the account's limit — which is how CI broke in August
# after a dozen unattended builds each left one behind.
#
# Safe to run on every build: an existing profile is reused, and only a profile
# Apple has marked unusable is replaced.
set -euo pipefail

APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.parthjadhav.ironlog}"
WIDGET_BUNDLE_ID="${WIDGET_BUNDLE_ID:-com.parthjadhav.ironlog.IronLogWidget}"
# These names are also in the Xcode project and ExportOptions.plist; changing one
# means changing all three.
APP_PROFILE_NAME="${APP_PROFILE_NAME:-IronLog App Store}"
WIDGET_PROFILE_NAME="${WIDGET_PROFILE_NAME:-IronLog Widget App Store}"

for required in ASC_API_KEY_ID ASC_API_ISSUER_ID ASC_API_PRIVATE_KEY_PATH; do
  if [[ -z "${!required:-}" ]]; then
    echo "$required must be set"
    exit 1
  fi
done

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

asc auth login \
  --name ironlog \
  --key-id "$ASC_API_KEY_ID" \
  --issuer-id "$ASC_API_ISSUER_ID" \
  --private-key "$ASC_API_PRIVATE_KEY_PATH" > /dev/null

# Pull ids by searching the response rather than indexing a fixed path, so a
# change in how the CLI wraps its output does not quietly break this.
certificate_ids="$(asc certificates list --certificate-type DISTRIBUTION --paginate --output json \
  | jq -r '[.. | objects | select(.type? == "certificates") | .id] | unique | .[]')"
certificate_count="$(printf '%s\n' "$certificate_ids" | grep -c . || true)"

if [[ "$certificate_count" -eq 0 ]]; then
  echo "No distribution certificate on the account."
  echo "Create one with scripts/new_signing_certificate.sh."
  exit 1
fi
if [[ "$certificate_count" -gt 1 ]]; then
  echo "Expected one distribution certificate, found $certificate_count:"
  printf '  %s\n' $certificate_ids
  echo
  echo "Signing would be a coin toss between them. Revoke the ones that are not"
  echo "CI's, or pin the right id here."
  exit 1
fi
certificate_id="$certificate_ids"

bundle_resource_id() {
  asc bundle-ids list --paginate --output json \
    | jq -r --arg identifier "$1" \
      '[.. | objects | select(.attributes?.identifier == $identifier) | .id] | first // empty'
}

find_profile() {
  asc profiles list --profile-type IOS_APP_STORE --paginate --output json \
    | jq -r --arg name "$1" --arg state "$2" \
      '[.. | objects | select(.attributes?.name == $name and .attributes?.profileState == $state) | .id] | first // empty'
}

install_profile() {
  local name="$1" bundle_id="$2"
  local bundle_resource profile_id stale

  bundle_resource="$(bundle_resource_id "$bundle_id")"
  if [[ -z "$bundle_resource" ]]; then
    echo "No bundle ID registered for $bundle_id"
    exit 1
  fi

  profile_id="$(find_profile "$name" ACTIVE)"
  if [[ -z "$profile_id" ]]; then
    # A profile Apple has invalidated keeps its name, and the name has to be
    # free before a replacement can take it.
    stale="$(find_profile "$name" INVALID)"
    if [[ -n "$stale" ]]; then
      echo "Replacing invalidated profile $name ($stale)"
      asc profiles delete --id "$stale" --confirm > /dev/null
    fi

    echo "Creating profile $name for $bundle_id"
    profile_id="$(asc profiles create \
      --name "$name" \
      --profile-type IOS_APP_STORE \
      --bundle "$bundle_resource" \
      --certificate "$certificate_id" \
      --output json \
      | jq -r '[.. | objects | select(.type? == "profiles") | .id] | first // empty')"
    if [[ -z "$profile_id" ]]; then
      echo "Apple accepted the request but returned no profile id."
      exit 1
    fi
  else
    echo "Reusing profile $name ($profile_id)"
  fi

  asc profiles download --id "$profile_id" --output "$work_dir/profile.mobileprovision" > /dev/null
  asc profiles local install --path "$work_dir/profile.mobileprovision"
}

install_profile "$APP_PROFILE_NAME" "$APP_BUNDLE_ID"
install_profile "$WIDGET_PROFILE_NAME" "$WIDGET_BUNDLE_ID"
