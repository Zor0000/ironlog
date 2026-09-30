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

## Current release checklist — September 30, 2026

Neeraj confirmed completion of the App Store Connect settings on September 30. The September 29 console notes below are historical and no longer describe unfinished privacy, age-rating, or review-contact setup. This confirmation is not evidence of App Review approval.

Canonical public pages are hosted in `/Users/neerajchormale/Projects/portfolio`, repository `Zor0000/portfolio`, deployed through Vercel: [homepage](https://www.neeraj.works/setzo/), [privacy](https://www.neeraj.works/setzo/privacy.html), [Terms](https://www.neeraj.works/setzo/terms.html), and [support](https://www.neeraj.works/setzo/support.html). Parth Jadhav is the Apple/App Store seller; Neeraj Chormale is the developer and support/privacy contact. Contact: `neerajchormale39@gmail.com`. Neeraj confirmed this mailbox works and chose it for support/privacy and Google OAuth on September 30; it supersedes the earlier `neerajcwork@gmail.com` choice.

### Completed work

- [x] Source manifest declares Email Address, Name, User ID, Fitness, Other User Content, Health, and Sensitive Info for app functionality with no tracking. Health, Sensitive Info, and Other User Content also declare Product Personalization for tailored meal suggestions. Health covers allergies/intolerances sent to Groq. Sensitive Info covers dietary identity and restrictions that may reveal beliefs or health information. The meal request is Other User Content. All are conservatively marked linked because requests use a signed-in or anonymous Supabase user ID.
- [x] Source policy discloses Supabase, Groq, the request fields, anonymous guest accounts, local-only Passport/safety answers, and deletion behavior. The auth screen links to the policy and Terms before account creation and social sign-in. The app and public pages identify Parth Jadhav as the App Store seller and Neeraj Chormale as developer/support contact and use `neerajchormale39@gmail.com` as the support and privacy contact.
- [x] Source still omits Precise Location: no GPS/location data is uploaded. The full Nutrition Passport, body weight, water log, and draft remain on-device; a derived cardio calorie value may sync with a saved activity.
- [x] **App Store Connect settings:** App Privacy declarations, age-rating answers, and review/contact settings are complete per Neeraj's September 30 confirmation. Do not reopen the stale September 29 checklist as unfinished work.
- [x] **Public pages and ownership:** homepage, privacy, Terms, support, stylesheet, and favicon returned HTTP 200 over HTTPS on September 30 and matched portfolio source byte-for-byte. All four pages have the agreed seller/developer/contact details and working navigation. Portfolio deployment commit: `591bf3c04948157282a665eedeef2f52df6070fe` (working-mailbox update; Vercel Production deployment `6752713187` succeeded). Search Console confirms `neeraj.works` is verified via Domain name provider; its DNS verification TXT record is present. Search indexing reports are still processing; that is separate from successful ownership verification.
- [x] **App and backend URLs:** pre-signup and Settings links, local Supabase `site_url`, all 13 email-template footers, website canonical metadata, README/legal canonical URLs, and future Apple metadata synchronization now use `https://www.neeraj.works/setzo/`. Production Supabase auth config was patched and all 28 requested fields were read back successfully. Native callback/reset URLs and OAuth credentials were preserved. Existing App Store GitHub Pages links remain historical known-good URLs; this session did not read or change live Apple metadata because local `asc` authentication is unavailable.
- [x] **Google audience/publishing:** project `gymbuddy-498919` (display name GymBuddy), with Setzo app branding, is External and In production. No publishing change was needed.
- [x] **Google links/developer contact:** homepage, privacy and Terms URLs already point to the canonical portfolio pages. Both Google user-support email and developer contact are `neerajchormale39@gmail.com`; the developer-contact change was saved and read back. Authorized domains read back as `dvqevdydldxjqjrpkkjc.supabase.co`, `zor0000.github.io` (legacy hosting), and `neeraj.works`.
- [x] **Google scopes:** saved only `https://www.googleapis.com/auth/userinfo.email` and `https://www.googleapis.com/auth/userinfo.profile`. Sensitive/restricted scope tables are empty. The production Supabase authorize endpoint returns HTTP 302 to the same OAuth client with `scope=email profile` and callback `https://dvqevdydldxjqjrpkkjc.supabase.co/auth/v1/callback`. The iOS client requests no additional scopes. The active OAuth client's callback was also read back in Google. Its internal console label remains `IronLog Supabase OAuth`: an optional rename attempt returned Google's “Save failed” error and the unchanged label was confirmed in the client list. This label is not shown to end users; public app name/logo are Setzo.
- [x] **Google verification:** Verification Center explicitly says branding has been verified and is being shown to users; data-access verification is not required because no sensitive/restricted scopes are requested. No Google approval queue or mandatory wait was shown. Routine OAuth configuration propagation can take five minutes to a few hours according to the client editor.
- [x] **Email-account deletion:** verified against production Supabase. The Auth user and associated records were removed, as confirmed by Neeraj and the recorded disposable-account verification below. This does not prove every physical-device/offline scenario.
- [x] **Support/privacy configuration:** app links, public pages, future Apple metadata synchronization, Google support/developer contacts, and all 13 production Supabase email templates use `neerajchormale39@gmail.com`; sender display name is Setzo. Existing Gmail SMTP configuration was preserved. The sender address and support/privacy destination now match.
- [x] **Mailbox operation:** Neeraj confirmed that `neerajchormale39@gmail.com` works. No additional mailbox test is requested. This is user-confirmed operation, not an agent-observed test delivery.
- [x] **Apple revocation implementation/deployment:** client reauthorization and backend revocation/fallback code are implemented and the backend is deployed. This does not imply signing credentials or live Apple revocation have been verified.

### Apple setup complete; live verification pending

- [x] **Supabase access:** Parth (`jadhavparth99@gmail.com`) is an active Administrator, independently read back from organization membership during PR #58 review. The Free plan uses organization-wide roles; Setzo is currently the organization's only project. [Original invitation evidence](release-evidence/2026-09-30/parth-supabase-invite-sent.png).
- [x] **Apple signing configuration:** Parth reports registering the dedicated key and verifying all four saved secret digests. Review independently confirmed all four production secrets are present and the client/team/key ID digests match the documented values. The private key was not retrieved.
- [ ] **One live iPhone check:** [issue #57](https://github.com/Zor0000/setzo/issues/57) remains OPEN for the disposable Apple-account deletion check. Verify actual Apple revocation, removal of the Auth user and associated records, and removal of Setzo in iPhone Settings. See [Apple deletion setup](apple-account-deletion.md).

### Apple account-deletion credentials

Create a dedicated **Sign in with Apple** key under team `75LRT8TRQY`, configured for primary App ID `com.parthjadhav.ironlog` (Setzo). An App Store Connect API key cannot sign Apple authorization requests.

Store these values in the production project's [Edge Function secrets](https://supabase.com/dashboard/project/dvqevdydldxjqjrpkkjc/functions/secrets):

| Secret | Value |
| --- | --- |
| `APPLE_CLIENT_ID` | `com.parthjadhav.ironlog` |
| `APPLE_TEAM_ID` | `75LRT8TRQY` |
| `APPLE_KEY_ID` | `N452YUC48V` (Setzo Account Deletion) |
| `APPLE_PRIVATE_KEY` | Complete downloaded `.p8` contents, with real newlines and BEGIN/END lines |

Keep the private key out of Git, screenshots, issue comments, and logs. Supabase exposes secret updates to the deployed function without another deployment.

September 30 production setup: Parth registered the dedicated key under his team and reports matching the saved SHA-256 digests for all four secrets, including the complete private key. Review independently confirmed secret presence and the client/team/key ID digests. A real Apple exchange and revocation remain unverified. Production was version 6 at review time, still using the earlier implementation; production now runs reviewed version 7, ACTIVE with JWT verification enabled. All three deployed source files match this PR exactly and an unauthenticated POST returned 401. [Deployment evidence](release-evidence/2026-09-30/pr58-backend-deployment.json).

Source changes to the function require deployment:

```bash
npx supabase functions deploy delete-account --project-ref dvqevdydldxjqjrpkkjc
```

The client recognizes the deployed `apple_reauthorization_required` and `apple_revocation_unavailable` error codes. An Apple account needs a fresh authorization code, whose verified subject must match its Auth identity before revocation and database deletion. The source permits manual revocation only when signing credentials are absent; configured exchange/revocation failures keep the account intact. Email, Google, and anonymous accounts do not require Apple confirmation.

September 30 source verification: Parth reports 253 iOS unit tests and the Simulator build passed. Review independently reran the 12 backend tests covering authorization, manual fallback, deletion ordering, signed Apple claims, mismatched identities, and upstream failures; type checking, lint and formatting passed. Parth downloaded version 5 for protocol comparison; review read back version 6. These checks do not establish a successful live Apple revocation.

Before closing #57, install a build containing this client flow on a physical iPhone, use a disposable Apple account, create a workout, and delete the account through Apple confirmation. Verify `Apple authorization revoked` in function logs, removal of the Auth user and owned records, and removal of Setzo under iPhone Settings → your name → Sign in with Apple. Record the tested build and date in the issue. A signed Debug build from source commit `473bd72`, version `1.0` build `3`, was subsequently installed on the paired iPhone 15 Pro on September 30. Its signed entitlements include Sign in with Apple and team `75LRT8TRQY`. The user chose to perform the live deletion test later; no Apple sign-in or account deletion was attempted.

PR #58 review: fixed guest deletion before cancelled Apple confirmation, persistent manual-revocation instructions, and account-scoped fallback confirmation. Restored native Apple revocation handling and consolidated the canonical URLs/contact changes. All 27 focused iOS tests passed; 12 backend tests, type checking, lint and formatting passed. The first local Xcode test launch stalled before XCTest loaded; disabling the debug dylib for the focused retry resolved it. CI will run its required full unit suite.

### Final build checks retained from the release checklist

These were not repeated during this focused configuration pass and are not covered by the confirmed email-account deletion test:

- [ ] Export the Xcode privacy report from the final signed archive; review app/widget/dependency reasons and validation notices before submission.
- [ ] Complete the release-build fresh non-test-user Google sign-in check and remaining physical-device deletion/offline/reauthentication scenarios. The server OAuth redirect and production email-account deletion checks above do not replace client-device verification. Inspect backup/log retention separately if needed.

September 30 contact follow-up: app/source links and future Apple metadata contact were updated; the portfolio change was committed and deployed, and all four live pages matched the new source. Production Supabase's 27 email-branding fields were updated and verified. Live App Store contact metadata was not edited in this session; the source synchronization script will apply the chosen mailbox on its next run.

Evidence: [working-mailbox live pages](release-evidence/2026-09-30/working-mailbox-pages.json), [working-mailbox Google contacts](release-evidence/2026-09-30/google-working-mailbox.png), [public-page HTTP/source comparison](release-evidence/2026-09-30/public-pages.json), [sanitized live Supabase configuration](release-evidence/2026-09-30/supabase-contact-config.json), [domain verification](release-evidence/2026-09-30/domain-ownership.png), [saved scopes](release-evidence/2026-09-30/google-scopes.png), and [Google verification status](release-evidence/2026-09-30/google-verification.png), and [current name/logo/support email](release-evidence/2026-09-30/google-branding.png). No broad regression suite was repeated for URL-only changes.

### Historical live verification progress (September 29)

The App Store incompletion statements in this historical record were superseded by Neeraj's September 30 confirmation above.

- GitHub Pages serves updated privacy, support, and Terms pages with HTTP 200 and the supplied name/mailbox. The Privacy Policy URL was read back in App Store Connect as `https://zor0000.github.io/setzo/privacy.html`.
- App Store Connect has all seven data types selected. Name, Email Address, Health, and Fitness are configured. Sensitive Info, Other User Content, and User ID still require their setup steps. The declarations are **not published**.
- Supabase email branding was updated and read back. Mailbox delivery itself has not been tested.
- Apple metadata workflow run `36610273223` passed the capability and URL-update steps, then failed at the age-rating request because required content-frequency fields were omitted. Run `36611135018` passed the age-rating update with existing answers preserved and Health or Wellness Topics enabled. It then stopped because Apple requires an App Review contact phone number; that value has been requested. Workflow `36611336392` completed successfully and its downloaded audit confirms both URLs, `healthOrWellnessTopics: true`, and the Apple capability. App Review details are absent pending the required phone number.
- The signed-in App Store Connect team is **Parth Jadhav**. Neeraj confirmed that the app should remain in Parth’s account with permission. Public pages identify Parth as App Store distributor and Neeraj as developer/support contact.
- **Apple deletion update (September 30):** native reauthorization, server-side code exchange/identity checks/token revocation, and an explicit manual fallback are implemented. Production `delete-account` version 5 is ACTIVE. Four focused backend tests and the iOS Simulator build passed; unauthenticated production requests return 401. Automatic Apple revocation still needs the four Apple signing secrets and one disposable Apple-account check on an iPhone. See [setup and verification](apple-account-deletion.md).
- Browser automation lost click/scroll access (`noWindowsAvailable`) while completing privacy setup; no publication or Google production-status change was made.

### September 29 implementation and external gates

The source now adds the missing Health and Sensitive Info manifest rows, pre-signup policy and Terms links, an adult account-creation declaration, native Sign in with Apple, AI/medical notices, a Terms page, guest account deletion retry, and cleanup of old local account/guest backups. The delete-account Edge Function now relies on the database's `ON DELETE CASCADE` chain, so account removal does not depend on a capped session ID lookup or a series of partial HTTP deletes. The changed function was deployed to the production project on September 29. A disposable production account with session, set, personal-record, and routine rows returned HTTP 204 on deletion; every row and the Auth user were absent afterward. A stale second-device token returned Auth HTTP 403 `user_not_found`. Physical two-device client behavior remains a release check.

At the time of the September 29 checks, console setup and hosted-page ownership were separate release gates. The September 30 checklist above supersedes their stale completion status using Neeraj's App Store confirmation and fresh Google/public-page evidence. Physical-device checks still require their own evidence.

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
