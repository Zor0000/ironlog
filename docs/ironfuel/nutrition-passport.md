# Nutrition Passport and IronFuel

IronFuel begins with a private Nutrition Passport. Pregnancy/breastfeeding is shown only when Female is selected. Switching to another sex context clears that answer; legacy snapshots are normalized on load and edit so hidden answers cannot trigger routing.

## AI dish suggestions

Every eligible Fuel Buddy request uses Groq through the Supabase `fuel-buddy` Edge Function. The production path does not select or rank a fixed recipe catalog. It returns 1–5 specific dish names based on the requested meal, cuisine, ingredients, and saved food preferences. The screen displays names only, without recipes, quantities or cooking instructions. Editing the request or Passport cancels pending work and clears previous results.

The default model is `openai/gpt-oss-120b`, selected after live quality checks. `GROQ_MODEL` can override it with a model supporting strict JSON schema. The Groq key remains a Supabase server secret and is never included in the iOS app. Guests use a separate persisted anonymous Auth session with its own storage key; this does not sign the user into the workout account or change workout ownership.

Provider errors, timeouts, missing credentials and invalid responses produce an explicit retry message. There is no catalog fallback. A valid `no_match` response produces the no-compatible-result state. The legacy local matcher remains available for regression tests but is not called by `FuelBuddyService`.

## Version 2 JSON contract

`FuelBuddyGenerationContract.swift` and `supabase/functions/fuel-buddy/contract.ts` define the client and server contracts. Each request includes `schemaVersion: 2`, a `requestID`, `policyVersion`, redacted `userText`, `maxOptions` (1–5), and food preferences. Preferences contain dietary identity, excluded ingredients, dislikes, preferred cuisines, available foods, cooking time/ability and budget. Age, sex, body measurements, medical context, recorded energy targets and account identity are not sent to Groq.

The response uses the same request ID and version:

```json
{
  "schemaVersion": 2,
  "requestID": "12345678-1234-1234-1234-123456789abc",
  "status": "ok",
  "options": [{
    "name": "Paneer Bhurji with Toast",
    "mealType": "breakfast",
    "cuisine": "Indian",
    "prepMinutes": 20,
    "ingredients": ["paneer", "tomato", "onion", "oil", "whole wheat bread"],
    "proteinSources": ["paneer"],
    "dietaryTags": ["vegetarian"],
    "cookingAbility": "Basic cooking",
    "budget": "Value"
  }]
}
```

Metadata is hidden from the UI and used to check meal/cuisine, explicit ingredients, time, budget, cooking ability, dietary restrictions and protein-focused requests. Equivalent protein labels such as `tofu` and `firm tofu` are normalized to the listed ingredient. Invalid or duplicate candidates are removed; a response with no valid candidates gets one corrective model attempt, then fails explicitly. The iOS client verifies the request ID, shape, count and Passport rules again before rendering.

Allergy checks use model-declared ingredients; they cannot verify actual preparation or cross-contact. The UI says to check ingredients when allergies are saved. The safety policy continues to block unsafe dieting/supplement/treatment requests and routes contexts requiring professional guidance. The app does not calculate or prescribe energy targets.

## Deployment and verification

```sh
supabase secrets set --env-file supabase/functions/.env --project-ref <project-ref>
supabase functions deploy fuel-buddy --project-ref <project-ref> --use-api
node --test supabase/functions/fuel-buddy/handler.test.ts
```

The ignored `.env` contains the provider credential. Auth anonymous sign-ins must be enabled for guest requests. Apply `20260927182958_restrict_fuel_guest_data_access.sql` first: anonymous users cannot insert into the shared exercise library; workout tables keep their ownership policies. The function verifies Auth users, rejects the public key alone, and applies per-worker burst protection (10 requests/user/minute). This is not a global distributed quota; provider quotas and Auth signup limits also apply.

The backend contract tests cover generated dishes absent from the catalog, guest authentication, strict schema, exclusions, meal relevance, count, deduplication and provider failure. iOS unit tests cover request privacy, response validation, no-fallback behavior and Passport state. Deterministic UI tests cover names-only rendering and stale results. `testIronFuelLiveGuestGeneration` is opt-in with `TEST_RUNNER_IRONFUEL_LIVE_TESTS=1` when running xcodebuild and checks the deployed service from the Simulator using the screenshot prompts.

A rebuilt iOS app is required; installing the server function alone does not update an older app's local matching implementation.
