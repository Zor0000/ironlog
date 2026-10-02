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

## Current release checklist — October 1, 2026

Neeraj confirmed completion of the App Store Connect settings on September 30. Privacy and age-rating completion remain recorded on that basis. September 30 API evidence found no App Review contact record; the October 2 release synchronization now found an existing record, verified the chosen contact email and preserved its phone and reviewer instructions. This newer evidence supersedes the absent-record status. No App Review approval is claimed.

Canonical public pages are hosted in `/Users/neerajchormale/Projects/portfolio`, repository `Zor0000/portfolio`, deployed through Vercel: [homepage](https://www.neeraj.works/setzo/), [privacy](https://www.neeraj.works/setzo/privacy.html), [Terms](https://www.neeraj.works/setzo/terms.html), and [support](https://www.neeraj.works/setzo/support.html). Parth Jadhav is the Apple/App Store seller; Neeraj Chormale is the developer and support/privacy contact. Contact: `neerajchormale39@gmail.com`. Neeraj confirmed this mailbox works and chose it for support/privacy and Google OAuth on September 30; it supersedes the earlier `neerajcwork@gmail.com` choice.

### Completed work

- [x] Source manifest declares Email Address, Name, User ID, Fitness, Other User Content, Health, and Sensitive Info for app functionality with no tracking. Health, Sensitive Info, and Other User Content also declare Product Personalization for tailored meal suggestions. Health covers allergies/intolerances sent to Groq. Sensitive Info covers dietary identity and restrictions that may reveal beliefs or health information. The meal request is Other User Content. All are conservatively marked linked because requests use a signed-in or anonymous Supabase user ID.
- [x] Source policy discloses Supabase, Groq, the request fields, anonymous guest accounts, local-only Passport/safety answers, and deletion behavior. The auth screen links to the policy and Terms before account creation and social sign-in. The app and public pages identify Parth Jadhav as the App Store seller and Neeraj Chormale as developer/support contact and use `neerajchormale39@gmail.com` as the support and privacy contact.
- [x] Source still omits Precise Location: no GPS/location data is uploaded. The full Nutrition Passport, body weight, water log, and draft remain on-device; a derived cardio calorie value may sync with a saved activity.
- [x] **App Store Connect settings:** App Privacy declarations and age-rating answers are complete per Neeraj's September 30 confirmation; release metadata synchronization also successfully updated branding, canonical URLs, and the existing age-rating declaration. App Review contact is tracked separately below using fresh API evidence.
- [x] **Public pages and ownership:** homepage, privacy, Terms, support, stylesheet, and favicon returned HTTP 200 over HTTPS on September 30 and matched portfolio source byte-for-byte. All four pages have the agreed seller/developer/contact details and working navigation. Portfolio deployment commit: `591bf3c04948157282a665eedeef2f52df6070fe` (working-mailbox update; Vercel Production deployment `6752713187` succeeded). Search Console confirms `neeraj.works` is verified via Domain name provider; its DNS verification TXT record is present. Search indexing reports are still processing; that is separate from successful ownership verification.
- [x] **App and backend URLs:** pre-signup and Settings links, local Supabase `site_url`, all 13 email-template footers, website canonical metadata, README/legal canonical URLs, and future Apple metadata synchronization now use `https://www.neeraj.works/setzo/`. Production Supabase auth config was patched and all 28 requested fields were read back successfully. Native callback/reset URLs and OAuth credentials were preserved. Existing App Store GitHub Pages links remain historical URLs. CI used its configured Apple credentials to synchronize the canonical homepage, support and privacy URLs successfully on September 30; local `asc` authentication remains unavailable.
- [x] **Google audience/publishing:** project `gymbuddy-498919` (display name GymBuddy), with Setzo app branding, is External and In production. No publishing change was needed.
- [x] **Google links/developer contact:** homepage, privacy and Terms URLs already point to the canonical portfolio pages. Both Google user-support email and developer contact are `neerajchormale39@gmail.com`; the developer-contact change was saved and read back. Authorized domains read back as `dvqevdydldxjqjrpkkjc.supabase.co`, `zor0000.github.io` (legacy hosting), and `neeraj.works`.
- [x] **Google scopes:** saved only `https://www.googleapis.com/auth/userinfo.email` and `https://www.googleapis.com/auth/userinfo.profile`. Sensitive/restricted scope tables are empty. The production Supabase authorize endpoint returns HTTP 302 to the same OAuth client with `scope=email profile` and callback `https://dvqevdydldxjqjrpkkjc.supabase.co/auth/v1/callback`. The iOS client requests no additional scopes. The active OAuth client's callback was also read back in Google. Its internal console label remains `IronLog Supabase OAuth`: an optional rename attempt returned Google's “Save failed” error and the unchanged label was confirmed in the client list. This label is not shown to end users; public app name/logo are Setzo.
- [x] **Google verification:** Verification Center explicitly says branding has been verified and is being shown to users; data-access verification is not required because no sensitive/restricted scopes are requested. No Google approval queue or mandatory wait was shown. Routine OAuth configuration propagation can take five minutes to a few hours according to the client editor.
- [x] **Email-account deletion:** verified against production Supabase. The Auth user and associated records were removed, as confirmed by Neeraj and the recorded disposable-account verification below. This does not prove every physical-device/offline scenario.
- [x] **Support/privacy configuration:** app links, public pages, future Apple metadata synchronization, Google support/developer contacts, and all 13 production Supabase email templates use `neerajchormale39@gmail.com`; sender display name is Setzo. Existing Gmail SMTP configuration was preserved. The sender address and support/privacy destination now match.
- [x] **Mailbox operation:** Neeraj confirmed that `neerajchormale39@gmail.com` works. No additional mailbox test is requested. This is user-confirmed operation, not an agent-observed test delivery.
- [x] **Apple revocation implementation/deployment:** client reauthorization and backend revocation/fallback code are implemented and the backend is deployed. Signing configuration was independently inspected during review; the later live Apple deletion check is complete per Neeraj's October 1 confirmation below.

### Apple setup and live verification complete

- [x] **Supabase access:** Parth (`jadhavparth99@gmail.com`) is an active Administrator, independently read back from organization membership during PR #58 review. The Free plan uses organization-wide roles; Setzo is currently the organization's only project. [Original invitation evidence](release-evidence/2026-09-30/parth-supabase-invite-sent.png).
- [x] **Apple signing configuration:** Parth reports registering the dedicated key and verifying all four saved secret digests. Review independently confirmed all four production secrets are present and the client/team/key ID digests match the documented values. The private key was not retrieved.
- [x] **One live iPhone check:** Neeraj confirmed on October 1 that Parth performed the Apple deletion check and considers it complete. [Issue #57](https://github.com/Zor0000/setzo/issues/57) is completed on that basis. No additional backend logs or tested build number were supplied with this confirmation; this is user-confirmed verification. See [Apple deletion setup](apple-account-deletion.md).
- [x] **Google sign-in checks:** Neeraj confirmed on October 1 that these are complete. This is user-confirmed device verification, additional to the recorded production OAuth/console checks.

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

September 30 production setup: Parth registered the dedicated key under his team and reports matching the saved SHA-256 digests for all four secrets, including the complete private key. Review independently confirmed secret presence and the client/team/key ID digests. A real Apple exchange/revocation was unverified during that September 30 review; Neeraj subsequently confirmed Parth completed the live deletion check on October 1. Production was version 6 at review time, still using the earlier implementation; production now runs reviewed version 7, ACTIVE with JWT verification enabled. All three deployed source files match this PR exactly and an unauthenticated POST returned 401. [Deployment evidence](release-evidence/2026-09-30/pr58-backend-deployment.json).

Source changes to the function require deployment:

```bash
npx supabase functions deploy delete-account --project-ref dvqevdydldxjqjrpkkjc
```

The client recognizes the deployed `apple_reauthorization_required` and `apple_revocation_unavailable` error codes. An Apple account needs a fresh authorization code, whose verified subject must match its Auth identity before revocation and database deletion. The source permits manual revocation only when signing credentials are absent; configured exchange/revocation failures keep the account intact. Email, Google, and anonymous accounts do not require Apple confirmation.

September 30 source verification: Parth reports 253 iOS unit tests and the Simulator build passed. Review independently reran the 12 backend tests covering authorization, manual fallback, deletion ordering, signed Apple claims, mismatched identities, and upstream failures; type checking, lint and formatting passed. Parth downloaded version 5 for protocol comparison; review read back version 6. These checks do not establish a successful live Apple revocation.

The original live-check procedure was to install a build containing this client flow on a physical iPhone, use a disposable Apple account, create a workout, and delete the account through Apple confirmation. Verify `Apple authorization revoked` in function logs, removal of the Auth user and owned records, and removal of Setzo under iPhone Settings → your name → Sign in with Apple. Record the tested build and date in the issue. A signed Debug build from source commit `473bd72`, version `1.0` build `3`, was subsequently installed on the paired iPhone 15 Pro on September 30. Its signed entitlements include Sign in with Apple and team `75LRT8TRQY`. At that installation session, the user chose to perform the live deletion test later; no Apple sign-in or account deletion was attempted then. Neeraj confirmed completion by Parth on October 1.

PR #58 review: fixed guest deletion before cancelled Apple confirmation, persistent manual-revocation instructions, and account-scoped fallback confirmation. Restored native Apple revocation handling and consolidated the canonical URLs/contact changes. All 27 focused iOS tests passed; 12 backend tests, type checking, lint and formatting passed. The first local Xcode test launch stalled before XCTest loaded; disabling the debug dylib for the focused retry resolved it. PR #58 was approved and merged as `b8ca9b9`. Its first release run (`36706838972`) stopped before signing/upload on four assertions in one draft-restore test. Investigation found a real Live Activity queue race: boot published the disk draft before reading newer Lock Screen edits. Follow-up `aafd916` drains prior updates and reconciles the loaded draft before publishing. The previously failing test and two related restore/Lock Screen checks passed locally (3 tests, zero failures); the corrected release run is `36708492844`.

### Reviewed release — September 30

- [x] PR #58 approved and merged (`b8ca9b9`); draft-restoration follow-up `aafd916` included in the release.
- [x] Required CI suite: **257 iOS unit tests, zero failures**. Focused backend suite: **12 tests, zero failures**; type checking, lint and formatting passed.
- [x] Signed archive and App Store IPA export succeeded. Version **1.0**, build **36708492844**, build ID `5c1e8ef2-e2fb-469e-b809-c62f72bc0959`. Apple upload and `asc --wait` processing completed successfully; the build was assigned to internal group `6497c060-a90c-4255-ace4-7ce105aff763`. This is TestFlight delivery, not App Review approval or an App Store release.
- [x] Downloaded archive passed `codesign --verify --deep --strict`. The distributed IPA contains the expected version/bundle ID and app/widget manifests. The final archive includes four valid manifests (app, widget, Crypto, Liveline), all with tracking false and no tracking domains. App required API reasons are FileTimestamp `C617.1` and UserDefaults `CA92.1`; widget uses UserDefaults `CA92.1`. All seven declared data categories are present.

[Successful workflow](https://github.com/Zor0000/setzo/actions/runs/36708492844), [release receipt](release-evidence/2026-09-30/testflight-release.json), [Apple metadata log](release-evidence/2026-09-30/apple-metadata-sync.txt), [focused log evidence](release-evidence/2026-09-30/testflight-release.txt), and [final archive manifests](release-evidence/2026-09-30/final-archive-manifests.json).

The archive and IPA are also preserved locally at `build/release-36708492844/`. GitHub's signed-archive artifact expires after 14 days. Xcode Organizer opened the correct archive and offered Generate Privacy Report, but its Save dialog kept Export disabled; pointer control of that dialog reported `noWindowsAvailable`. Keyboard filename/destination changes did not enable Export. No PDF was exported and no privacy-report/validation approval is claimed. Retry manually by opening `build/release-36708492844/Setzo.xcarchive`, then control-clicking its Organizer row → Generate Privacy Report. Inspect the report before submission.

### Agreement cleared and new TestFlight build — October 2

After Neeraj reported that Parth completed the agreement action, [run 36986706508](https://github.com/Zor0000/setzo/actions/runs/36986706508) succeeded from source commit `ff4c696233f469d4a803e1e8b6ae757578aa6785`, including the October 1 authentication fixes. The existing CI suite passed **259 unit tests with zero failures**. The workflow created and exported the signed archive, uploaded version **1.0**, build **36986706508** (build ID `5b5f5502-242a-42d6-a6b7-1cc3591c2309`), completed Apple's processing wait and assigned the existing internal TestFlight group. Apple API access confirms that the earlier agreement block is cleared.

The archive, IPA and symbols are preserved locally at `build/release-36986706508/`. The downloaded archive passed strict signature verification; archive and IPA identities matched Setzo 1.0 (36986706508), and the widget build matched. Four final archive privacy manifests were inspected, with tracking disabled and all seven app data categories present. [Release receipt](release-evidence/2026-10-02/testflight-release.json), [focused workflow evidence](release-evidence/2026-10-02/testflight-release.txt), [Apple metadata evidence](release-evidence/2026-10-02/apple-metadata-sync.txt), and [final manifests](release-evidence/2026-10-02/final-archive-manifests.json).

No additional test cases were added for this retry. The exact-build physical iPhone smoke test and privacy-report export remain outstanding. TestFlight delivery does not establish App Review approval or App Store availability.

### Final build checks retained from the release checklist

Remaining submission checks are tracked independently of the confirmed email-account deletion test:

- [x] **App Review contact record:** October 2 synchronization found an existing record and verified `neerajchormale39@gmail.com`; the phone and reviewer instructions were preserved. Review their accuracy with the remaining submission fields before submitting. [Apple field reference](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).
- [ ] Export the Xcode privacy report from the final signed archive; review app/widget/dependency reasons and validation notices before submission.
- [x] Release Google sign-in and the live Apple deletion check are complete per Neeraj's October 1 confirmation.
- [ ] Other physical-device offline/reauthentication/two-device scenarios retain their previous evidence status; the sign-in/deletion confirmation does not independently verify all of them. Inspect backup/log retention separately if needed.

September 30 contact follow-up: app/source links and future Apple metadata contact were updated; the portfolio change was committed and deployed, and all four live pages matched the new source. Production Supabase's 27 email-branding fields were updated and verified. Live Apple URL/branding synchronization succeeded in CI. The review-contact record is absent according to that run; its email cannot be applied until the required phone number is supplied.

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

Historical build 3 verification used the following commands (the September 30 reviewed release above is current):

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

## Historical build 3 upload

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

Current CI releases use the GitHub Actions run ID for `CFBundleVersion`. For a manual future upload, first bump `CFBundleVersion`, rebuild the IPA, then run:

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

## October 2 public App Store review preparation

Neeraj selected public App Store review for version **1.0**, Free pricing in all supported countries and regions, and **2026 Neeraj Chormale** copyright. Neeraj confirmed permissions for all included content and artwork. The version now has its description, subtitle, keywords, Health & Fitness category, content-rights declaration and build **36986706508** attached. Free prices and `available=true` were verified in all **175** supported territories.

Five refreshed Setzo marketing screenshots were exported from the existing screenshot editor at **1284 × 2778**, checked for dimensions, opaque pixels and readable captions, and uploaded to the en-US iPhone 6.5-inch set. Apple reports all five as **COMPLETE**. The meal slide uses “Meal ideas for your preferences” without an absolute food-safety promise.

[Validation and upload run](https://github.com/Zor0000/setzo/actions/runs/36995431015) passed: **0 blocking issues, 0 errors and 0 warnings**. App Privacy publication is not verifiable through the public API; the earlier user confirmation remains the publication evidence. Existing review contact and credentials were preserved. [Sanitized readiness receipt](release-evidence/2026-10-02/app-store-review-readiness.json), [listing copy](app-store-listing.json), and [screenshot files](../images/app-store/en-US/iphone65/).

Neeraj confirmed **manual release** on October 2. The first submission attempt saved `MANUAL` but revealed a missing regulated medical-device declaration that the CLI readiness check did not detect. That declaration was saved as **No** for Setzo's general fitness tracking and verified in App Store Connect. [Declaration evidence](release-evidence/2026-10-02/medical-device-declaration.jpg) and [Apple declaration instructions](https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status).

**Public App Store review submission was accepted** on October 2 at **12:16:12 UTC (17:46:12 IST)**. [Submission run](https://github.com/Zor0000/setzo/actions/runs/37005631504) safely reused draft `0e81f794-c622-43a1-a581-ed0bf5759a2e` and submitted version **1.0**, build **36986706508**. Both the review status and version record report `WAITING_FOR_REVIEW`; release type is `MANUAL`. [App Store Connect confirmation](release-evidence/2026-10-02/waiting-for-review.jpg). [Sanitized submission receipt](release-evidence/2026-10-02/app-store-review-submission.json).

Immediately before submission, validation passed with **0 errors, 0 warnings and 0 blocking issues**. The later readiness audit flags `version.state.editable` because a submitted version is locked in `WAITING_FOR_REVIEW`. That expected state does not indicate rejection. Apple review approval and public availability remain pending.

The exact-build physical iPhone check remains outstanding before public launch; device access did not establish a passing check. After Apple approves the manual-release version, complete that check before releasing it and enabling the public website's App Store button. No new test cases were added. The screenshot editor's existing export now retains a download link for retry when the automatic download is suppressed.
