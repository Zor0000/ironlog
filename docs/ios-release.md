# Setzo iOS Release

Native iOS bundle:

- Project: `Setzo.xcodeproj`
- Scheme: `Setzo`
- Bundle ID: `com.parthjadhav.ironlog`
- App Store Connect app name: `Setzo`
- App Store Connect app ID: `6771258872`
- Team ID: `75LRT8TRQY`
- Version: `1.0`
- Build: GitHub Actions run ID for CI releases

## Setzo rename

September 29 verification: 252 unit tests passed on iOS 26.5 / iPhone 17, and the website production build passed. The TestFlight workflow synchronizes the app name, listing and beta metadata, privacy URLs, and bundle display names before uploading a new build.

The source project, schemes, targets, release artifacts, website, and GitHub repository use Setzo. Apple keeps the existing app ID `6771258872`, bundle ID `com.parthjadhav.ironlog`, and widget bundle ID `com.parthjadhav.ironlog.IronLogWidget`. These identifiers are intentionally stable for updates and signing.

The existing local data directory, authentication storage keys, Live Activity storage keys, and `ironlog:v1:` set metadata remain stable to preserve saved workouts and sessions. New authentication links use `setzo://`; legacy links are still accepted. Existing build history and historical evidence retain the branding used when they were produced.

## September 27 readiness follow-up

The five follow-up blockers are addressed: free-text dietary restrictions fail closed with a Passport prompt; gluten excludes oats; deletion retries continue at a capped 120-second interval and resume on foreground; failed snapshot writes can be retried without discarding the pending snapshot; and cleared session notes encode explicit nulls while rejected edits keep the sheet open.

The Precise Location declaration was removed. Session uploads no longer send route coordinates, including any legacy route data. The widget privacy manifest is included in the release sources and built extension.

The public policy was deployed on September 27 and compared byte-for-byte with `privacy.html`; its current location after the rename is https://zor0000.github.io/setzo/privacy.html. Policy-only hosting commit: `d2e938c223ecd8abaa414f6975c93d0101c99b82`. Its `[skip actions]` message suppresses the repository's TestFlight push workflow; only GitHub Pages was deployed.

Local verification: 233 unit tests passed on iOS 26.5 / iPhone 17. Static analysis and an unsigned generic iOS Release build passed. App and widget manifests passed plist validation in the source and built bundles. All 20 UI tests passed; four screenshot-capture tests were intentionally skipped. The UI run still emitted the previously observed nonfatal SwiftUI frame-dimension warnings.

Before submission, create a fresh signed archive, export its privacy report, and complete the physical-device checks below. No app upload or submission was performed. The commands and upload details later in this document describe an earlier build 3 release.

## App Store privacy checklist

- [x] Source manifest declares Email Address, Name, User ID, Fitness, Other User Content, Health, and Sensitive Info for app functionality with no tracking. Health, Sensitive Info, and Other User Content also declare Product Personalization for tailored meal suggestions. Health covers allergies/intolerances sent to Groq. Sensitive Info covers dietary identity and restrictions that may reveal beliefs or health information. The meal request is Other User Content. All are conservatively marked linked because requests use a signed-in or anonymous Supabase user ID.
- [x] Source policy discloses Supabase, Groq, the request fields, anonymous guest accounts, local-only Passport/safety answers, and deletion behavior. The auth screen links to the policy and Terms before account creation and social sign-in. The app and public pages identify Parth Jadhav as the App Store seller and Neeraj Chormale as developer/support contact and use `neerajcwork@gmail.com` as the support and privacy contact.
- [x] Source still omits Precise Location: no GPS/location data is uploaded. The full Nutrition Passport, body weight, water log, and draft remain on-device; a derived cardio calorie value may sync with a saved activity.
- [ ] **App Store Connect → App Privacy:** select Yes, data is collected; add and publish Contact Info → Email Address and Name, Identifiers → User ID, Fitness, Other User Content, Health, and Sensitive Info. For each, answer App Functionality, linked to user, no tracking. Also select Product Personalization for Health, Sensitive Info, and Other User Content. Review third-party processor practices and any technical data category before publishing. Capture the published product-page preview and date. A source manifest does **not** set these answers.
- [x] **App Store Connect URL read-back (run `36611336392`):** verified the en-US Privacy Policy URL is `https://zor0000.github.io/setzo/privacy.html`. The current Support URL is `https://zor0000.github.io/setzo/support.html`, and both return the updated September 29 content. The successful workflow audit artifact contains both live API values.
- [ ] **Google Auth Platform:** verify External audience, switch from Testing to In production, and complete branding/scope verification if Google requires it. Test a fresh non-test-user Google account through Supabase on a release build. Record the published branding, scopes, support email, authorized domain, and verification state.
- [ ] **Apple sign-in:** the Supabase Apple provider was enabled September 29 with native Client ID `com.parthjadhav.ironlog`, and public Auth settings read back `apple: true`. Workflow `36611336392` confirms `APPLE_ID_AUTH` with primary-app configuration for the App ID. Regenerate the distribution provisioning profile, and test both a first sign-in and a repeat sign-in on a physical device. Apple guideline 4.8 requires an equivalent privacy-preserving login option while Google sign-in is offered.
- [ ] **App Store Connect → App Information → Age Ratings:** answer Health or Wellness Topics according to IronFuel and workout tracking; review Medical or Treatment Information with the actual shipped content. Confirm the calculated rating and regional results. The app is not in the Kids category; account creation and Google sign-in require an 18+ self-declaration, while minors are limited to local workouts and cannot use Fuel Buddy.
- [ ] Export the Xcode privacy report from the final signed archive. Confirm the app and widget manifests and bundled dependency manifests/reasons. Inspect App Store Connect validation notices before submission.
- [ ] Check signed-in account deletion, expired-session reauthentication, anonymous guest deletion, offline local deletion, and bulk workout deletion on two physical devices against the production Supabase project. Verify that a second device cannot rehydrate deleted data, and check backups/operational log retention separately.
- [ ] Confirm that `neerajcwork@gmail.com` receives support and privacy requests and is used in App Review contact metadata, Supabase email templates, and Google support/developer contacts. GitHub Pages is currently hosted under a personal account. No Setzo-controlled domain is available; record page ownership and continuity procedures before submission, then migrate when a domain is provisioned.

### Live verification progress (September 29)

- GitHub Pages serves updated privacy, support, and Terms pages with HTTP 200 and the supplied name/mailbox. The Privacy Policy URL was read back in App Store Connect as `https://zor0000.github.io/setzo/privacy.html`.
- App Store Connect has all seven data types selected. Name, Email Address, Health, and Fitness are configured. Sensitive Info, Other User Content, and User ID still require their setup steps. The declarations are **not published**.
- Supabase email branding was updated and read back. Mailbox delivery itself has not been tested.
- Apple metadata workflow run `36610273223` passed the capability and URL-update steps, then failed at the age-rating request because required content-frequency fields were omitted. Run `36611135018` passed the age-rating update with existing answers preserved and Health or Wellness Topics enabled. It then stopped because Apple requires an App Review contact phone number; that value has been requested. Workflow `36611336392` completed successfully and its downloaded audit confirms both URLs, `healthOrWellnessTopics: true`, and the Apple capability. App Review details are absent pending the required phone number.
- The signed-in App Store Connect team is **Parth Jadhav**. Neeraj confirmed that the app should remain in Parth’s account with permission. Public pages identify Parth as App Store distributor and Neeraj as developer/support contact.
- **Additional Apple deletion gate:** implement server-side Sign in with Apple token exchange/revocation using an Apple Sign in key, and verify revocation during account deletion. Deleting the Supabase Auth user alone does not satisfy Apple's token-revocation guidance. Do not treat the new Apple sign-in button as production-ready until this is complete.
- Browser automation lost click/scroll access (`noWindowsAvailable`) while completing privacy setup; no publication or Google production-status change was made.

### September 29 implementation and external gates

The source now adds the missing Health and Sensitive Info manifest rows, pre-signup policy and Terms links, an adult account-creation declaration, native Sign in with Apple, AI/medical notices, a Terms page, guest account deletion retry, and cleanup of old local account/guest backups. The delete-account Edge Function now relies on the database's `ON DELETE CASCADE` chain, so account removal does not depend on a capped session ID lookup or a series of partial HTTP deletes. The changed function was deployed to the production project on September 29. A disposable production account with session, set, personal-record, and routine rows returned HTTP 204 on deletion; every row and the Auth user were absent afterward. A stale second-device token returned Auth HTTP 403 `user_not_found`. Physical two-device client behavior remains a release check.

The live App Store Connect privacy answers, Google production status, Apple capability/profile and physical sign-in test, age rating, contact metadata, two-device deletion behavior, and hosted-page ownership are separate release gates. Do not mark them complete from source changes or from a TestFlight upload. The Gmail address and publisher name were supplied by Neeraj Chormale; no project domain was supplied.

References: [Apple App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy), [Apple privacy manifest data types](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype), [Apple account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app), [Apple age ratings](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating), [Apple login-services guideline](https://developer.apple.com/app-store/review/guidelines/uk/), [Google audience and publishing](https://support.google.com/cloud/answer/15549945), [Supabase Apple sign-in](https://supabase.com/docs/guides/auth/social-login/auth-apple), [Supabase user deletion](https://supabase.com/docs/guides/auth/managing-user-data).

The current native app has been verified with:

```bash
xcodebuild test -project Setzo.xcodeproj -scheme Setzo -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
xcodebuild -project Setzo.xcodeproj -scheme Setzo -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Setzo.xcodeproj -scheme Setzo -destination 'generic/platform=iOS' -archivePath build/Setzo.xcarchive archive
xcodebuild -exportArchive -archivePath build/Setzo.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```

The exported IPA is `build/export/Setzo.ipa`.

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

- App name: `Setzo`
- App ID: `6771258872`
- Bundle ID: `com.parthjadhav.ironlog`
- SKU: `ironlog-ios` (immutable existing Apple record)
- Primary language: `English (U.S.)`

The product is renamed to `Setzo`. The existing Apple app record, bundle IDs, and SKU are retained so TestFlight users receive an update to the same app.

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
  --name setzo \
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
