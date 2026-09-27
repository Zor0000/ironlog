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

## September 27 readiness follow-up

The five follow-up blockers are addressed: free-text dietary restrictions fail closed with a Passport prompt; gluten excludes oats; deletion retries continue at a capped 120-second interval and resume on foreground; failed snapshot writes can be retried without discarding the pending snapshot; and cleared session notes encode explicit nulls while rejected edits keep the sheet open.

The Precise Location declaration was removed. Session uploads no longer send route coordinates, including any legacy route data. The widget privacy manifest is included in the release sources and built extension.

The public policy at https://zor0000.github.io/ironlog/privacy.html was deployed on September 27 and compared byte-for-byte with `privacy.html`. Policy-only hosting commit: `d2e938c223ecd8abaa414f6975c93d0101c99b82`. Its `[skip actions]` message suppresses the repository's TestFlight push workflow; only GitHub Pages was deployed.

Local verification: 233 unit tests passed on iOS 26.5 / iPhone 17. Static analysis and an unsigned generic iOS Release build passed. App and widget manifests passed plist validation in the source and built bundles. All 20 UI tests passed; four screenshot-capture tests were intentionally skipped. The UI run still emitted the previously observed nonfatal SwiftUI frame-dimension warnings.

Before submission, create a fresh signed archive, export its privacy report, and complete the physical-device checks below. No app upload or submission was performed. The commands and upload details later in this document describe an earlier build 3 release.

## App Store privacy checklist

- [ ] In App Store Connect, review **Contact Info → Email Address** and optional **Name**, linked to the user, for account authentication.
- [ ] Review **Identifiers → User ID**, linked to the user, for the Supabase account identifier.
- [ ] Review **Fitness** for cloud-synced workouts, sets, personal records, and run/walk details, and **Other User Content** for synced free-text notes, remarks, and routines. Their purpose is app functionality; no tracking or advertising is implemented.
- [ ] Do not declare **Precise Location**: this release does not collect or upload GPS/location data.
- [ ] Do not label the Nutrition Passport, body weight, water log, IronFuel queries, or draft as collected by the app: the current implementation keeps them on-device. A derived cardio calorie value can sync as part of a saved activity.
- [ ] Confirm the Google OAuth provider and its consent screen if Google sign-in is enabled. Supabase handles authentication and cloud storage; Google handles the optional sign-in exchange. Check the provider's current data-handling terms before answering any processor or retention questions.
- [ ] Set the current public `privacy.html` URL in App Store Connect and check it against the shipped behavior. The repository has no evidence that App Store Connect privacy answers were changed.
- [ ] Export the Xcode privacy report from the final signed archive. Confirm the app and widget manifests and bundled dependency manifests/reasons. Inspect any App Store Connect validation notices before submission.
- [ ] Check account deletion, individual offline deletion, and bulk workout deletion on two physical devices against the production Supabase project, including sign-out/sign-in, a failed response, and a later sync. Review Supabase backup/log retention settings separately.

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
