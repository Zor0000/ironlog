# Apple account deletion — September 30, 2026

The app and production `delete-account` function previously deleted the Supabase user without revoking Apple's authorization. The function now requests a fresh native Apple authorization code, exchanges it for tokens on the server, checks Apple's returned subject against the caller's linked Apple identity, and revokes the refresh token before deleting the Supabase user. Existing database cascades and local cleanup remain responsible for removing workout records. No Apple refresh tokens or signing keys are sent back to the app, stored, or logged.

Fresh authorization at deletion also supports accounts created before this change and deletion from another signed-in device. Cancelling Apple authorization leaves the signed-in account, its records, and the AI guest account intact. Configured Apple exchange/revocation failures preserve the account for retry; manual fallback is available only when signing credentials are missing. If Apple credentials are unavailable, the app offers account/data deletion followed by instructions for removing Setzo under Settings → your name → Sign in with Apple. The instruction survives an app restart. Native credential-revocation notifications trigger a remote-deletion check or sign-out.

## Verification

- The original four focused backend tests passed: revocation/deletion order and caller identity; wrong Apple account and failed revocation; email deletion, authenticated access and explicit fallback; cryptographic verification of the generated ES256 client secret.
- The iOS Simulator app build passed.
- Production version 7 is ACTIVE with JWT verification enabled. All three downloaded source files match the reviewed code; an unauthenticated POST returned HTTP 401. The backend preserves existing request/error names and strengthens Apple signature verification and fallback rules.
- All four production Apple signing secrets are present. The client/team/key ID digests match the documented values; Parth reports also matching the private-key digest.
- A real Apple exchange/revocation has **not** been verified. No real user accounts were deleted during this review.

Review verification: 27 focused iOS tests and 12 backend tests passed; Deno type checking, lint and formatting passed.

## Configured credentials and remaining live verification

Parth completed the key/secret setup below, using key `N452YUC48V` and team `75LRT8TRQY`. The physical-device deletion check remains pending.

1. Sign into [Apple Developer](https://developer.apple.com/account/resources/identifiers/list) using Parth's developer team. Verify the App ID `com.parthjadhav.ironlog` has Sign in with Apple enabled and is the primary App ID for the key.
2. Open Certificates, Identifiers & Profiles → Keys → +. Create a dedicated key, enable **Sign in with Apple**, click **Configure**, and choose the Setzo primary App ID. Register it, record the Key ID, and download the `.p8` file. This must be a Sign in with Apple key, **not** an App Store Connect API key.
3. In [Supabase Edge Function secrets](https://supabase.com/dashboard/project/dvqevdydldxjqjrpkkjc/functions/secrets), add:

   | Secret | Value |
   | --- | --- |
   | `APPLE_CLIENT_ID` | `com.parthjadhav.ironlog` |
   | `APPLE_TEAM_ID` | Parth's verified Apple Developer Team ID; the Xcode project currently uses `75LRT8TRQY` |
   | `APPLE_KEY_ID` | The Sign in with Apple Key ID from step 2 |
   | `APPLE_PRIVATE_KEY` | The entire downloaded `.p8` contents, including BEGIN/END lines |

   Supabase makes secrets available to the already deployed function; no signing key belongs in the app or Git.

4. Install a build containing these client changes on an iPhone. Use one disposable Apple account to sign into Setzo, create one workout, and choose **Delete Account & Data**. Complete the Apple confirmation. Confirm the function log contains `Apple authorization revoked`, the Supabase Auth user and associated records are gone, and Setzo no longer appears as authorized under iPhone Settings → your name → Sign in with Apple. That one check is sufficient to finish this feature's live verification.

References: [Apple TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple), [Apple token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens), [Apple manual revocation instructions](https://support.apple.com/102571).

## Reviewed TestFlight build

PR #58 was approved and merged on September 30 (`b8ca9b9`), followed by the verified draft-restore fix `aafd916`. Install TestFlight **1.0 (36708492844)** for the physical Apple check in issue #57. The release workflow passed 257 unit tests, archived/exported/uploaded successfully, waited for Apple processing, and assigned the build to Internal Testers. Production deletion backend remains reviewed version 7. No real Apple-account revocation has been verified by this release workflow.
