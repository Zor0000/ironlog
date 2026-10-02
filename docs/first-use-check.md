# Setzo first-use check — 1 October 2026

Result: the source build passes the exercised first-use flows after correcting the authentication loading UI. This is simulator evidence, not clearance of the uploaded TestFlight/App Store build.

## Environment

- iPhone 17 Pro simulator, iOS 26.5, dedicated device named `Setzo First Use`.
- Debug source based on commit `e18202f58b40f29cda411b451fd8abdb768500b2`, with the fixes below in the working tree. Normal simulator code signing; no demo seed in the first-use account.
- The Google account the owner signed in with has the `test0110` alias. The separately created email/password account uses `test1110`. They are distinct accounts. Account identifiers, tokens and credentials are omitted from this report.
- All workouts and Passport choices entered during this check are synthetic test inputs, not the owner's training or health profile.

## Flows exercised

| Flow | Result and evidence |
| --- | --- |
| First launch | Three onboarding cards worked; Continue locally reached Workouts without requiring an account. |
| First workout | Exercise-library search found Push-Ups; one bodyweight set of 12 reps could be completed; rest countdown started with notifications declined. |
| Interrupted local workout | Terminate/relaunch restored the unsaved exercise and set inputs. Finish & Save created a History item with `BW x 12`. |
| Run logging | A 20-minute, 2.5 km run showed 8:00/km and 7.5 km/h and saved beside the workout. |
| Local-to-cloud migration | When the owner created the email account, the local workout and run reached that account's cloud store. Backend inspection confirmed both records. |
| Google sign-in | Google callback and app-session exchange succeeded after installing the normally signed simulator build. Settings showed the Google account and Synced with Supabase. |
| Account isolation | The new Google account began with empty training history; the email account's two sessions remained under that account. |
| Google cloud save | Saved one Push-Ups workout and the routine `Launch check — Push-Ups`. Backend inspection confirmed one session and one routine. |
| Returning user | Reopening preserved authentication and the routine. Sign-out returned to local mode; Google sign-in restored the routine, one session, one set and the `BW x 12` record. Cloud counts remained one session/one routine after these transitions. |
| Cancel Google login | Cancelling the system sign-in sheet returned to the normal form with Google enabled and no raw AuthenticationServices error. Retry succeeded. |
| IronFuel | Initially gated on a Nutrition Passport. Completed its four steps using neutral synthetic defaults and no energy target or restrictions. A live `quick Indian dinner` request returned five dish names; loading finished and the request button became available again. This checks the request flow, not dietary suitability. |

## Glitches found and fixed

1. **The sign-in form expanded into a training dashboard while busy.** `RootView.swift` used an unqualified `ProgressView()` in two loading labels. Setzo also declares a view with that name for training statistics, so Swift resolved the wrong view. Both authentication/reset-password labels now explicitly use `SwiftUI.ProgressView()`.
2. **Cancelling Google displayed a technical error.** Google login now handles `ASWebAuthenticationSessionError.canceledLogin` as a normal cancellation and clears the previous error before a retry. Other failures still display an error.
3. **The initial simulator could not exchange the Google login code.** The initial screenshot-style build disabled code signing; backend Auth logged HTTP 400 because the PKCE verifier was empty. Rebuilding the same source with normal simulator signing immediately made login succeed. This identifies the local test setup as the cause of that failure; it does not establish a signing problem in the uploaded build. Keep code signing enabled when testing OAuth/Keychain. An unsigned screenshot build is unsuitable for authenticated first-use checks.

## Automated validation

- 25 unit tests passed: two new Google cancellation/failure tests and all 23 existing ReleaseReadinessTests covering local recovery, interrupted drafts, offline sync/deletion retries, lost responses and account isolation. Destructive cases used isolated mock stores, not these live accounts.
- Two authentication UI tests passed, including a new busy-layout regression that checks button bounds, compact height and absence of the training dashboard. The existing legal-link assertions were corrected to use their actual iOS button accessibility role.
- Native build succeeded with normal simulator signing. Website production build and lint passed.
- Local website at `/setzo/` checked at 1440 and 393 pixels wide: all four current captures loaded, no horizontal overflow, disabled download button with no destination, no TestFlight link.

## Evidence and remaining release checks

Private simulator captures and the busy-layout test attachment are in the ignored local folder `evidence/launch-check-2026-10-01/`. Marketing captures use a separate DEBUG demo seed and are catalogued in `docs/screenshot-assets.json`; no test-account capture was copied to public marketing assets.

The Google test account remains signed in on the dedicated simulator with one synthetic workout, one routine and a local synthetic Passport. The email test account's two cloud sessions remain intact. No live account or stored workout was deleted.

Before public launch, repeat open → Google sign-in → save → reopen → sync on the new TestFlight build recorded below and a physical iPhone. Physical Lock Screen Live Activities, notification delivery, GPS, Apple sign-in, password reset completion, and cross-device restoration were not validated in this simulator pass. Backups and a restore drill remain a separate operating-plan decision.

After this check, Neeraj authorised publication of the coming-soon website. Portfolio commit `7ce1ee6` deployed successfully; the live `/setzo/` page loaded all four refreshed captures and retained a disabled download button with no destination or TestFlight link. Enable the real App Store URL after public availability. First-user outreach, demo video, GitHub Pages and custom analytics remain deferred.

The main-branch push of app commit `7744899` triggered [TestFlight run 36860880606](https://github.com/Zor0000/setzo/actions/runs/36860880606). Apple rejected its metadata API access because a required agreement was missing or expired; tests, archive and upload did not run.

On 2 October, after Neeraj reported that Parth had completed the agreement action, [run 36986706508](https://github.com/Zor0000/setzo/actions/runs/36986706508) successfully accessed Apple, passed all 259 existing unit tests, created the signed archive and uploaded version 1.0, build **36986706508**. Apple processing completed and the existing internal testing group was assigned. This build includes the authentication fixes; [release receipt](release-evidence/2026-10-02/testflight-release.json). The downloaded archive signature, exported build identity and four privacy manifests were verified. The short first-use check on this exact build and a physical iPhone remains outstanding; no App Review submission or App Store availability is claimed.
