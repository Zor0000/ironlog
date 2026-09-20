# IronLog iOS Release

Native iOS bundle:

- Project: `IronLog.xcodeproj`
- Scheme: `IronLog`
- Bundle ID: `com.parthjadhav.ironlog`
- App Store Connect app name: `IronLog Strength Journal`
- App Store Connect app ID: `6771258872`
- Team ID: `75LRT8TRQY`
- Version: `1.0`
- Build: `3`

## Verified Locally

The current native app has been verified with:

```bash
xcodebuild test -project IronLog.xcodeproj -scheme IronLog -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
xcodebuild -project IronLog.xcodeproj -scheme IronLog -destination 'generic/platform=iOS Simulator' build
xcodebuild -project IronLog.xcodeproj -scheme IronLog -destination 'generic/platform=iOS' -archivePath build/IronLog.xcarchive archive
xcodebuild -exportArchive -archivePath build/IronLog.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```

The exported IPA is `build/export/IronLog.ipa`.

The IPA contains:

- `CFBundleIdentifier = com.parthjadhav.ironlog`
- `CFBundleShortVersionString = 1.0`
- `CFBundleVersion = 3`
- `ITSAppUsesNonExemptEncryption = false`
- `PrivacyInfo.xcprivacy`
- `workouts.json`

The export summary shows an App Store distribution profile and `beta-reports-active = true`.

## App Store Connect

The App Store Connect record has been created:

- App name: `IronLog Strength Journal`
- App ID: `6771258872`
- Bundle ID: `com.parthjadhav.ironlog`
- SKU: `ironlog-ios`
- Primary language: `English (U.S.)`

The exact `IronLog` App Store name was unavailable, so the App Store Connect listing uses `IronLog Strength Journal`; the native bundle and in-app identity remain `IronLog`.

If this app record ever needs to be recreated, the public App Store Connect API cannot create new app records. This repo includes an `asc iris` helper for the private web-session flow:

```bash
asc iris auth login
asc iris auth verify-code
scripts/create_asc_app_record.sh
```

If App Store Connect is already open in a browser, creating the app record through the web UI is also fine.

## Upload

The build was uploaded with the installed `asc` CLI.

Uploaded/TestFlight state:

- Upload ID / Build ID: `b254395a-b44a-4cfb-875b-37ef7f6168bc`
- Version: `1.0`
- Build: `3`
- Platform: `iOS`
- Processing state: `VALID`
- TestFlight internal state: `IN_BETA_TESTING`
- TestFlight external state: `READY_FOR_BETA_SUBMISSION`
- Internal group: `Internal Testers`
- Internal group ID: `6497c060-a90c-4255-ace4-7ce105aff763`
- Tester invite: `jadhavparth99@gmail.com`

To re-upload a future build, first bump `CFBundleVersion`, rebuild the IPA, then run:

```bash
scripts/build_ios_release.sh
ASC_APP_ID=6771258872 scripts/upload_testflight.sh
```

Credential setup, if needed again:

Persistent `asc` API key auth:

```bash
asc auth login \
  --name ironlog \
  --key-id <KEY_ID> \
  --issuer-id <ISSUER_ID> \
  --private-key-path /path/to/AuthKey_<KEY_ID>.p8

ASC_APP_ID=<app-store-connect-app-id> scripts/upload_testflight.sh
```

One-shot `asc` API key auth:

```bash
ASC_APP_ID=<app-store-connect-app-id> \
ASC_API_KEY_ID=<KEY_ID> \
ASC_API_ISSUER_ID=<ISSUER_ID> \
ASC_API_PRIVATE_KEY_PATH=/path/to/AuthKey_<KEY_ID>.p8 \
scripts/upload_testflight.sh
```

`altool` API key fallback:

```bash
mkdir -p ~/.appstoreconnect/private_keys
cp AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
ASC_API_KEY_ID=<KEY_ID> ASC_API_ISSUER_ID=<ISSUER_ID> scripts/upload_testflight.sh
```

Apple ID app-specific password:

```bash
ASC_USERNAME=<apple-id-email> \
ASC_APP_PASSWORD=<app-password> \
ASC_PROVIDER_PUBLIC_ID=<provider-id> \
scripts/upload_testflight.sh
```

Then confirm processing in App Store Connect > TestFlight.
