# End-to-end verification

Setzo uses the actual [tester-army/e2e](https://github.com/tester-army/e2e) runner, with pinned `e2e@0.16.0`, `@e2e-dev/mobile@0.9.1`, and a separate website project using `@e2e-dev/web@0.11.2` / `playwright@1.63.0`. These suites use deterministic device/browser operations without a model, API key, or paid generation. Published package declarations and README documents define the integration; repository HEAD documents can describe newer APIs.

## Install and run

Use Node 24+, npm, Xcode, and an available iOS Simulator runtime. The committed Xcode project is authoritative; do not regenerate it from `project.yml` just to test.

```sh
npm ci
npm run typecheck
npm run test:e2e:ios:build
npm run test:e2e:list
npm run test:e2e
npm --prefix website ci
npm --prefix website exec playwright install chrome
npm --prefix website run lint
npm --prefix website run typecheck
npm --prefix website run test:e2e
```

`build_e2e_ios.sh` creates/reuses only the dedicated **Setzo E2E** simulator. It builds the app, widget extension, unit tests and UI tests without signing in `build/e2e/DerivedData`. Override `SETZO_E2E_DEVICE` with that dedicated simulator UDID and `SETZO_E2E_DERIVED_DATA` with a separate build directory when needed. Never select a real phone or somebody else's simulator. The runner session is `setzo-e2e-0`; coordinate other agent-device tasks before running because the local daemon is shared. One worker serializes native flows. Each scenario launches DEBUG `UITest_ResetStore` against this isolated guest store. Persistence scenarios explicitly relaunch without that reset argument and complete the real guest onboarding when first shown. The native suite uses bounded edge gestures to reveal controls inside SwiftUI ScrollViews; a TabView can otherwise cause the backend to select its outer collection view.

The website runner starts the production server on `127.0.0.1:4313` and uses installed **Google Chrome**, through `website/e2e/chrome-provider.ts`'s supported BrowserProvider contract. There is no bundled Chromium fallback. Set `SETZO_E2E_HEADED=1` to see it. Each context is isolated. The provider closes its leased Chrome process after the run.

Retain the broad existing XCTest/XCUITest suites:

```sh
xcodebuild -project Setzo.xcodeproj -scheme Setzo -configuration Debug \
  -destination 'platform=iOS Simulator,id=YOUR_DEDICATED_SIMULATOR_UDID' \
  -derivedDataPath build/e2e/DerivedData -parallel-testing-enabled NO \
  -only-testing:SetzoTests -only-testing:SetzoUITests/SetzoUITests \
  -collect-test-diagnostics never \
  -resultBundlePath build/e2e/Native.xcresult CODE_SIGNING_ALLOWED=NO test-without-building
```

`.github/workflows/e2e.yml` runs both projects, installs Chrome explicitly, and retains native results and runner evidence. The existing live Groq test is opt-in and skipped; leave `IRONFUEL_LIVE_TESTS` unset for fixture verification. Screenshot-studio demos are outside this product gate. The separate opt-in `EvidenceCaptureTests` Dynamic Type/device matrix is retained, not included in the normal assertion suite.

## Flow matrix

| Flow | Evidence | Boundary |
|---|---|---|
| Free workout, custom exercise, set completion, save, history edit, relaunch | Native army saved-workout flow + existing free-workout and history-validation XCUITests | Isolated local store |
| Exercise library search, shorthand, muscle previews, browser close, split picker, PPL wizard, exercise finder, try another | Existing XCUITests | Seed 7 / fixture exercise catalog |
| Exercise/set removal, confirmations, routine create/delete, custom set remarks | Native army deletion flow + existing XCUITests | Empty sets delete immediately; entered work prompts |
| Draft persistence/relaunch/discard | Native army draft flow + AppStateTests | Relaunch omits reset |
| Set types, timed sets, bodyweight/weight conversion, reorder, workout CRUD, PRs, references, undo/reducers | AppStateTests + LiveWorkoutReducerTests | Deterministic unit state transitions; not every variant driven in army UI |
| Rest start/pause/reset, presets/background notification lifecycle | Native army timer + AppStateTests/reducer tests | Actual Lock Screen/background notification delivery requires device validation |
| Runs/walks, duration/distance bounds, terrain toggles, bodyweight calorie estimates, history save | Native army run flow + existing XCUITests + AppStateTests | Manual cardio, no real GPS route capture |
| Progress Stats/History selection, calendar filtering/navigation, empty month | Existing XCUITests + native army saved-history/water flows | Seeded calendar data |
| Water input/persistence, local-delete confirmation | Native army water flow + AppStateTests | Guest-only, no cloud deletion |
| IronFuel passport first-use/wizard/delete, pregnancy clearing, energy/safety/diet/allergy constraints | Existing XCUITests + IronFuelFeatureTests/SafetyEvaluationTests/ResponseValidatorTests | No real medical or paid provider actions |
| IronFuel submit generated/offline/error/no compatible result, stale output clearing | Four native army fixture flows + existing generated-result XCUITests | DEBUG injected outcomes; offline outcome is a UI seam, not a network toggle |
| Auth age gate, Apple/Google presence, privacy/terms reachability, forgot-password screen | Native army auth flow + existing XCUITest + AppStateTests | No provider submission, credential, MFA, real account creation/reset/delete |
| Account logout/deletion/revocation fallback, guest migration, sync/offline retry, cross-account isolation, tombstones | AppStateTests + SupabaseWireFormatTests mocked service contracts | Real Supabase/RLS, provider callbacks and network deletion unverified |
| Units/body weight preferences, relaunch | Native army preference flow + Settings XCUITest | No production credentials |
| Theme, accessibility labels, voiceover-oriented controls | Native accessibility queries + existing evidence hooks; website semantic/responsive tests | Full VoiceOver/Dynamic Type/native light-mode matrix not claimed |
| Widget extension and Live Activity intents | App/widget build + LiveWorkoutReducerTests | Real Lock Screen/Dynamic Island delivery and App Group integration unverified on hardware |
| Website nav/anchors/home, source/support/privacy destinations, images, compact 320/375/768 layouts, semantic document, 404/back | Seven Chrome army tests | External links inspected, not navigated/signed in |

## Current-main landing verification (2026-10-03)

The rollout was first verified on `codex/issue-57-apple-revocation` at `9179040`. It is now landed in an isolated worktree on `codex/tester-army-e2e`, based on `origin/main` at `1a25b13`. The newer main's App Store coming-soon controls, release copy, `www.neeraj.works` support/privacy/terms destinations, busy authentication layout, Apple deletion safeguards and workout-draft restoration are preserved. Website tests exercise the current navigation, source link, and three disabled App Store controls; the native privacy and terms links retain individual accessible identifiers.

| Current-base check | Result/evidence |
|---|---|
| Locked root and website dependency install | `npm ci` passed for both projects |
| Root and website types; website lint | Passed; `/tmp/setzo-landing-{root-types,web-types,web-lint}.log` |
| Website production build + full Chrome suite | **7/7 passed**, zero failures/skips/flaky cases, exit 0; Google Chrome 154.0.8037.97, run `01a1009a-5abc-7efc-b146-5cdc9e637584`; `/tmp/setzo-landing-web-e2e.log`, `website/.e2e/report.json`. Chrome and server port 4313 released |
| Current app, widget and XCTest bundles | Build-for-testing passed, `/tmp/setzo-landing-native-build.log`; derived data `/tmp/setzo-landing-derived` |
| Current unit suite and affected native UI | **259 unit + 6 UI passed**, zero failures/skips, process exit 0; finalized result-bundle summary **Passed, 265 tests**. UI coverage: auth privacy/terms and reset, busy auth layout, workout/IronFuel keyboard dismissal, history edits, Run saving and body-weight settings. `/tmp/setzo-landing-native-tests.log`, `/tmp/setzo-landing-native.xcresult`. This is a focused UI rerun on the newer base, separate from the original complete UI gate below |
| Current dependency audits | Root audit **0**; website production audit (`npm audit --omit=dev`) **0**. Full website audit reports **5 high entries from one unpatched advisory** in the lint dependency chain; see below |

The current full website audit reports `eslint-config-next@16.3.8 → @next/eslint-plugin-next@16.3.8 → fast-glob@3.3.1 → micromatch@4.0.8 → braces@3.0.3`. [GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm), reviewed October 2, covers stack exhaustion with deeply nested brace patterns and lists no patched version; the registry's latest `braces` remains 3.0.3. These are development lint dependencies, excluded from the clean production audit. No major Next.js downgrade or vendor patch is included. Evidence: `/tmp/setzo-landing-{root,web,web-production}-audit.json`. The earlier zero-vulnerability full audit recorded below is historical and does not supersede this current result.

The current focused native run records four of the previously observed SwiftUI negative/non-finite frame warnings, with no failing assertions. The originating expression remains unidentified; this warning is not claimed fixed. Xcode's automatic simulator diagnostic collection took ten minutes after the tests; the command then exited zero normally and finalized its valid result bundle. The collector also exited without being interrupted.

The first current-base independent mobile repeat passed 11/12 (run `01a100a6-c0e3-73b0-a131-d5856ae87d3b`), exposing an unreliable double-tap assumption in the history-edit driver: typing `15` yielded `1512` because the existing `12` was not selected. The helper now long-presses the actual input, taps the visible **Select All** edit-menu command, and uses native digit keys. It asserts the exact replacement `15` before saving and the saved `BW x 15` afterward. No product persistence defect is inferred. The repaired focused flow passed **1/1**, exit 0, in 29.68 seconds (run `01a100b2-f878-7891-a6f3-761c279d9c5e`); `/tmp/setzo-landing-history-select-all-fixed.log` and `/tmp/setzo-landing-history-select-all-green/` retain the current green evidence. The original 11/12 red report and screenshots are preserved at `/tmp/setzo-landing-mobile-red/`. The first Select All attempt queried the SDK's menu-item role while its snapshot exposed a list-item/text command; that red attempt is preserved at `/tmp/setzo-landing-select-all-role-red/`. The final independent current-base repeat then passed **12/12**, exit 0, with no failures, skips, retries or secondary errors and complete attempt cleanup. Luna ran frozen runtime/test commit `4ef0164e2335c4f9d7c018cc29244b950727f445`, run `01a100b4-e4be-7122-9bca-8b8039f6dddb`; `.e2e/report.json` and `.e2e/summary.md` retain the result. The repaired history flow passed in 31.25 seconds. The current website suite also passed an independent **7/7** repeat (run `01a100a1-b158-7a02-9866-dadd260d3fdf`). The later evidence-documentation commit changes no runtime or test behavior.

Hosted CI run `37106377885` passed the website job but failed before the native build with simulator `Incompatible device` (code 403). The old script chose a runtime and device independently from reversed inventory arrays. Creation now selects a numeric-version-ranked available iOS runtime and an iPhone from that runtime's `supportedDeviceTypes`; it fails clearly if there is no compatible pair. Existing dedicated-name reuse and explicit UDID overrides are unchanged. Three fixtures cover unordered inventories with a newer incompatible catalog device, numeric version ordering, and unavailable/missing compatible pairs. All pass, as does a local create/delete smoke check for the selected compatible pair. Run `python3 scripts/test_select_e2e_simulator.py` to repeat the fixture check. CI records its selected Xcode version, avoids assuming a specific installed Xcode path, and uses `-collect-test-diagnostics never` while retaining every unit/UI test assertion and the result bundle. Hosted iOS success is not claimed until the updated workflow completes.

## Initial rollout findings and local evidence (2026-10-03)

The first website run reproduced **99 px horizontal overflow at 320 px** in the Live Activity preview. A single-column grid with zero minimum width and compact preview padding now keeps the content inside the phone viewport. The Chrome regression asserts no page overflow at three compact widths. The preview also exposed fake, nonfunctional buttons; it is now decorative and absent from keyboard/assistive control navigation. Website claims of a shipped web PWA and no third-party SDKs were inconsistent with the native app and its Supabase dependency; copy now states native iOS and local guest mode. Dependency audit identified vulnerable Next.js 16.2.10; Next/eslint-config-next are pinned to 16.3.8 with fixed transitive dependencies, and `npm audit` reports zero vulnerabilities.

The existing auth XCUITest could not reach the privacy links. Both controls were visibly rendered in `/tmp/setzo-auth-screen.png`, but a parent-group accessibility identifier masked their individual IDs. Removing the unused parent identifier and adding explicit identifiers to the actual links restores independent access. Type-neutral hittable XCTest assertions verify the real controls across platform class changes.

The mobile flows also exposed a keyboard toolbar leaking from the Run page into workout inputs: its Done action cleared the Run focus state and could leave the actual input keyboard open. Toolbars now appear only for their own focused fields; workout numeric inputs and the IronFuel multiline request have explicit Done actions. Regression flows assert the workout and IronFuel dismissal controls disappear after tapping them, then complete save/submit through real controls. Early runner integration failures and their reports are preserved under `/tmp/setzo-mobile-{first,second,third}-report.json`; those runs are not counted as passing verification. The first keyboard-fix attempt was stopped after a duplicated SwiftUI toolbar identifier made its locator ambiguous (`/tmp/setzo-mobile-keyboard-selector-red-report.json`); unused identifiers were removed and the suite queries the actual Done button role. The explicit native keyboard regression also asserts exactly one Done button and absence of the keyboard after dismissal.

The previous 9/12 run identified three driver interaction issues: editing a centered numeric field through `fill` inserted at its cursor, a restored focused draft triggered a stale text-field probe after discard, and the Run distance field needed keyboard dismissal and an explicit reveal. The final suite selects the numeric value and taps real digit keys, asserts the exact replacement before saving, dismisses the restored draft through its actual Done action before discard, and reveals the distance input after dismissal. These are deterministic interactions with positive persisted outcomes, without swallowing backend errors. The earlier broad history XCUITest now uses the actual Select All edit-menu command and also asserts its replacement value.

SwiftUI emitted an `Invalid frame dimension (negative or non-finite)` runtime warning during keyboard presentation in native runs, including before the toolbar fix. The final independent native result bundle contains nine occurrences during keyboard and IronFuel coverage, with no test failures. No originating frame expression was identified; this warning is not claimed resolved. The website production build also emits a nonfatal workspace-root inference warning because root and website lockfiles both exist.

Local dedicated simulator: **E17B8C86-249C-4B14-A978-BBFDB1C3FAA6**, iPhone 17 Pro, iOS 26.5; derived data `/tmp/setzo-e2e-derived-data`.

| Check | Result/evidence |
|---|---|
| Debug app + widget + test bundle build | Passed, `/tmp/setzo-e2e-build.log`, incremental `/tmp/setzo-e2e-build-fixed.log`; current final UI bundle compiled in `/tmp/setzo-history-test-build3.log` |
| Native unit tests | 253 passed, `/tmp/setzo-unit-implementation.log`, `/tmp/setzo-unit-implementation.xcresult` |
| Original native UI run | 23 passed, 1 privacy-link reachability failure, 1 opt-in live Groq skip; `/tmp/setzo-ui-implementation.log` |
| Fixed native UI suite | 24 passed, 1 opt-in live Groq skip, `/tmp/setzo-ui-fixed.log`, `/tmp/setzo-ui-fixed.xcresult`; focused auth rerun 1 passed in `/tmp/setzo-auth-fixed2.log` |
| Keyboard follow-up native checks | App/widget build passed; five focused UI flows passed in `/tmp/setzo-keyboard-focused.log` / `.xcresult`; the sixth history flow passed after replacing brittle double-tap selection with the real Select All menu and exact value assertions (`/tmp/setzo-history-fixed4.log`, `.xcresult`). This includes the new keyboard-dismissal regression. |
| Implementation native tester-army | **12/12 passed**, 165.44 s, process exit 0, run `01a0fee5-f46e-72ec-910f-2a09cfd5b67f`; `/tmp/setzo-implementation-evidence/native/report.json`, `/tmp/setzo-mobile-full-fixed.log`. Zero skips, retries, failed steps or secondary errors; all attempt cleanup complete. Previous 9/12 failure report remains `/tmp/setzo-mobile-final-red-report.json` |
| Implementation website tester-army | 7 passed, `/tmp/setzo-implementation-evidence/website/report.json`, `/tmp/setzo-website-implementation-fixed.log` |
| Final independent native XCTest | **278 passed = 253 unit + 25 normal UI**, 1 opt-in live Groq skip, 0 failures; `/tmp/setzo-luna-native-final.xcresult`. Includes both current history-edit and keyboard-dismissal regressions |
| Final independent native tester-army | **12/12 passed**, 165.64 s, exit 0, run `01a0feea-5d7d-77b9-bd02-7033f0cd6e50`; `.e2e/report.json`. Zero skipped/flaky tests, zero model calls/tokens |
| Final independent website tester-army | **7/7 passed**, exit 0, run `01a0feed-3d1c-782f-a676-077ec6712a28`; `website/.e2e/report.json`. Installed Google Chrome 154.0.8037.97; production build passed, provider released Chrome and port 4313 |
| Website lint/typecheck | Passed |
| Dependency audit | Zero vulnerabilities after fixes, `/tmp/setzo-website-audit-before.json`, `/tmp/setzo-website-audit-after.json` |
| Final independent supporting checks | Root and website typechecks, website lint and production build passed; root and website npm audits each reported zero vulnerabilities |

Exact local mobile command (after the build shown above):

```sh
SETZO_E2E_DEVICE=E17B8C86-249C-4B14-A978-BBFDB1C3FAA6 \
SETZO_E2E_DERIVED_DATA=/tmp/setzo-e2e-derived-data npm run test:e2e
```

The final independent run verified all 25 current normal UI assertions together with the 253 unit tests. Its exact command was:

```sh
xcodebuild -project Setzo.xcodeproj -scheme Setzo -configuration Debug \
  -destination 'platform=iOS Simulator,id=E17B8C86-249C-4B14-A978-BBFDB1C3FAA6' \
  -derivedDataPath /tmp/setzo-e2e-derived-data -parallel-testing-enabled NO \
  -only-testing:SetzoTests -only-testing:SetzoUITests/SetzoUITests \
  -resultBundlePath /tmp/setzo-luna-native-final.xcresult \
  CODE_SIGNING_ALLOWED=NO test-without-building
```

Earlier focused follow-ups used exact XCTest method selectors and `-collect-test-diagnostics never`; the earlier broad UI bundle is `/tmp/setzo-ui-fixed.xcresult`. The dedicated keyboard regression is `SetzoUITests/testDoneDismissesTheFocusedWorkoutAndIronFuelKeyboards`; the corrected history regression is `SetzoUITests/testHistoryCardOpensEditSheetAndSavesChanges`.

Runner reports live in `.e2e/` (native) and `website/.e2e/` (web), with markdown summary, JSON, JUnit, per-attempt screenshots and failing screen snapshots/traces. They are ignored locally and uploaded by CI. Hosted CI and real hardware/provider integration are not claimed verified by local results. Final implementation runner reports and screenshots were copied to `/tmp/setzo-implementation-evidence/{native,website}` before independent verification. Earlier red reports and logs are preserved there and under the `/tmp/setzo-mobile-*` paths above; the overwritten three broad-run failure pages/screenshots were not separately retained. Focused history failure pages/screenshots remain in the focused report directories. The final [independent Luna report](/Users/parthjadhav/research/e2e-rollout-2026-10-03/setzo-luna.md) records **PASS for the documented local fixture gate**, with no actionable failures; the external and hardware boundaries in the flow matrix still apply.
