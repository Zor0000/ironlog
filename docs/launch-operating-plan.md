# Setzo — basic operating plan

Approved by Neeraj · 1 October 2026. Ownership confirmed. This records the agreed operating routine; it does not itself create automations or paid services.

## Ownership and tools

Neeraj owns app fixes, the website, backend operation, and the support inbox (`neerajchormale39@gmail.com`). Parth owns the Apple developer/distribution account and App Store release actions. This ownership split is confirmed; a backup contact still needs to be designated before launch.

Use the tools already present: App Store Connect / Xcode Organizer for crashes and feedback, Supabase for Auth/database/function logs, GitHub Actions for release and keep-alive jobs, and the current hosting dashboard for website deployments. Keep a short issue list with severity, affected build, reproduction steps, and resolution. Ask users for app/iOS versions and symptoms; do not request passwords, tokens, or private Nutrition Passport details.

## Current baseline

| Item | Verified on 1 October | Implication |
| --- | --- | --- |
| Supabase project | `Setzo`, `dvqevdydldxjqjrpkkjc`, `ACTIVE_HEALTHY`, Free plan | Check quotas and recovery explicitly before public launch. |
| Keep-alive | Scheduled every 6 hours; latest five runs succeeded. Latest run returned HTTP 200 for exercises, sessions and routines. | This checks reachability, not account sign-in, sync correctness, or backups. Scheduled jobs can be delayed. |
| Edge Functions | `delete-account` v7 and `fuel-buddy` v3 ACTIVE, JWT verification enabled | Use their logs when investigating account or food-request failures. |
| Support/legal | Existing public pages and mailbox | Monitor the current inbox. |
| App distribution | 1.0 in Prepare for Submission; latest uploaded build 36708492844 | Public download remains disabled until the app is available. |
| Latest release workflow | [Run 36860880606](https://github.com/Zor0000/setzo/actions/runs/36860880606) stopped before tests/build because Apple reported a missing or expired agreement | Parth, as Account Holder, must accept the required agreement in App Store Connect before another upload can proceed. |
| Coming-soon website | Neeraj authorised publication; portfolio commit `7ce1ee6` deployed successfully and the live `/setzo/` page was verified | Current screenshots are public; the App Store button remains disabled with no download destination. |
| First-use source check | Local onboarding, workout/run saves, Google sign-in/sync/returning user and live Fuel Buddy passed after authentication UI fixes; 27 automated checks passed | Include the fixes in a new distribution build and verify that exact build on a physical iPhone. See [first-use report](first-use-check.md). |
| Recovery | No backup schedule or restore drill verified in this session | Close this gap before relying on cloud storage for public users. |

## Before launch

- Record the exact approved build, source commit, database migrations and deployed function versions. Preserve its signed archive and symbols beyond the CI artifact's expiry.
- Complete the final first-use smoke test on that TestFlight build and a physical iPhone. The simulator source check is useful additional evidence, not verification of the signed uploaded binary.
- Choose a cloud backup method and verify one restore into an isolated environment. On the current Free plan, Supabase recommends regular exports and off-site backups. Proposed minimum: daily encrypted exports, seven-day retention, access limited to the operator, and a monthly restore check. Confirm how Auth and application data are included, and how deleted accounts are kept deleted after recovery. Backups containing user data must stay out of the public repository and CI logs.
- Record current Supabase/Groq/hosting quotas, billing owners, and a monthly spending ceiling. This draft authorizes no plan upgrade or paid add-on. Decide before launch what to do at quota exhaustion; local workout logging should remain available.
- The coming-soon website is now published with Neeraj's approval. Keep its download button disabled until the app is publicly available in the selected regions. Then verify the real App Store URL, enable the download link, and publish that update. Verify download, support, privacy and Terms navigation on an iPhone.

## Routine

| Cadence | Check | Action if unhealthy |
| --- | --- | --- |
| Daily for the first launch week; then every working day | Support inbox and recent App Store reviews | Acknowledge within one working day; reproduce and record actionable reports. Treat data loss or inability to save as urgent. |
| Daily during launch week; then weekly and after changes | Supabase health, Auth failures, sync/function errors, latest keep-alive run | Investigate repeated failures; a green keep-alive is not sufficient proof. |
| Daily during launch week; then weekly | Xcode Organizer/App Store crash and hang reports | Group by build and affected flow; prioritise launch/sign-in/save crashes. Reports may arrive late and depend on sharing settings. |
| Weekly; daily if traffic grows quickly | Database/egress/Auth/function usage, Groq quota and hosting usage | At 80% of an included quota, estimate time to exhaustion and decide on spending or traffic limits before hitting it. The 80% threshold is proposed. |
| Daily backup result; monthly restore check | Most recent successful backup and restoration evidence | Investigate missed exports. A saved file is not a verified recovery path until a restore succeeds. |
| Before and after every release/backend change | Open → sign in → log/save → reopen → sync; sample run and Fuel Buddy; support/legal links | Stop the rollout or repair the affected service if core flows fail. Repeat only the checks affected by subsequent changes. |

## If something breaks

1. Record time, build, scope and a reproducible symptom. Check crash reports, service status, and only the relevant backend logs. Keep account identifiers and credentials out of public issues.
2. For save/data-loss failures, prioritise preserving users' local data. Do not recommend deleting or reinstalling the app to fix sync. Reproduce with the dedicated test account and compare local versus cloud records.
3. For sign-in or sync outages, check Supabase/Auth and provider configuration. Keep local logging available; confirm queued changes upload after recovery without duplicates.
4. For Fuel Buddy outages or rate limits, investigate function/Groq responses. The current source has per-worker burst protection, a request timeout and upstream quota handling; this is not a global spending cap. Repair or communicate the food-feature issue without interrupting workout logging.
5. Revert a faulty website deployment or compatible backend function version when appropriate. Database restores and destructive rollbacks require a recovery plan and explicit approval. An iOS fix normally needs a new build and App Review; do not assume an installed App Store binary can be instantly rolled back.
6. When an incident affects users, Neeraj prepares a concise support update describing the affected feature and workaround. Publish/send it only through an explicitly authorised channel. Validate the repaired flow and record what changed.

## Decisions for review

- Confirm owner/backup-contact availability and the one-working-day support target.
- Choose and implement the backup/export method, retention and restore drill.
- Set the spending ceiling and accept or adjust the proposed quota threshold.

First-user outreach remains deferred. Demo video, GitHub Pages and custom analytics remain deferred.

## References

- [Supabase database backups](https://supabase.com/docs/guides/platform/backups): paid-plan daily backup availability and the Free-plan export recommendation.
- [Apple crash reports and diagnostic logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs): existing crash investigation tools.
- [Latest verified keep-alive run](https://github.com/Zor0000/setzo/actions/runs/36822043869).
