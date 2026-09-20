# Fuel Buddy LLM contract v1

Provider-neutral request/response schema for the optional LLM layer described
in `llm-variety-layer.md`. Tracks #35. Swift types live in
`IronLog/IronFuel/FuelBuddyLLMContract.swift` and round-trip these examples in
`IronLogTests/FuelBuddyLLMContractTests.swift`.

Versioning: `schemaVersion` is an integer on both request and response. A
client only accepts responses whose `schemaVersion` equals the version it
sent. `policyVersion` identifies the deterministic safety policy that
pre-screened the request so evaluation runs can be compared over time.

Design constraint: **the response has no field in which a food, nutrient,
ingredient or calorie target can be introduced.** Foods are referenced by
catalog ID only; the validator (#37) rejects IDs that are not in the request's
`candidateFoodIDs`, and free-text fields are checked for numbers-with-units
and medical language.

## Request

```json
{
  "schemaVersion": 1,
  "policyVersion": "2026-09",
  "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10",
  "stage": "presentation",
  "userText": "Suggest an Indian vegetarian dinner under 20 minutes",
  "mealContext": {
    "mealType": "dinner",
    "cuisines": ["indian"],
    "maxPrepMinutes": 20,
    "budget": "moderate",
    "varietyIntent": "differentFromRecent"
  },
  "profileContext": {
    "ruleTags": ["vegetarian", "no-peanut"],
    "recentFoodIDs": ["dal-tadka", "paneer-bhurji"]
  },
  "candidateFoodIDs": ["chana-masala", "vegetable-pulao", "palak-paneer", "masala-oats"],
  "limits": {
    "timeoutMilliseconds": 4000,
    "maxResponseBytes": 8192,
    "maxFoods": 3
  }
}
```

| field | type | notes |
|---|---|---|
| `schemaVersion` | int | must be `1` |
| `policyVersion` | string | version of `FuelBuddySafetyPolicy` that screened `userText` |
| `requestID` | UUID string | correlates logs and the fallback diagnostic; not a user identifier |
| `stage` | `"intent"` \| `"presentation"` | which optional step this call serves |
| `userText` | string ≤ 500 chars | the request after the safety policy passed it |
| `mealContext.mealType` | `breakfast` \| `lunch` \| `dinner` \| `snack` \| `any` | |
| `mealContext.cuisines` | [string] | lowercase tags from the curated catalog |
| `mealContext.maxPrepMinutes` | int? | |
| `mealContext.budget` | `low` \| `moderate` \| `any` | |
| `mealContext.varietyIntent` | `none` \| `differentFromRecent` \| `surpriseMe` | |
| `profileContext.ruleTags` | [string] | resolved deterministic rule tags — never raw conditions |
| `profileContext.recentFoodIDs` | [string] | what to rotate away from (IDs only) |
| `candidateFoodIDs` | [string] | the **only** foods the model may reference; output of `FoodRuleEngine` → `EnergyFirewall` → `MealVarietyRotation` |
| `limits.timeoutMilliseconds` | int | client-enforced |
| `limits.maxResponseBytes` | int | client- and gateway-enforced |
| `limits.maxFoods` | int | max entries in `foods` |

Explicitly **not** present: email, account/user id, name, body metrics,
clinical details, free-text health history, the full food catalog.

## Response

```json
{
  "schemaVersion": 1,
  "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10",
  "status": "ok",
  "foods": [
    { "foodID": "chana-masala", "rationale": "fits vegetarian, ready in 20 minutes" },
    { "foodID": "vegetable-pulao", "rationale": "different from the dal you had recently" }
  ],
  "explanation": "Two quick Indian vegetarian dinners that avoid what you ate this week.",
  "tradeOffs": ["Vegetable pulao takes the full 20 minutes."],
  "refusalReason": null
}
```

| field | type | notes |
|---|---|---|
| `schemaVersion` | int | must equal the request's |
| `requestID` | UUID string | must equal the request's |
| `status` | `ok` \| `refused` \| `empty` | |
| `foods[].foodID` | string | must be in `candidateFoodIDs`; no duplicates; ≤ `maxFoods` |
| `foods[].rationale` | string ≤ 140 chars | ordering/variety rationale; no numbers-with-units, no medical language |
| `explanation` | string ≤ 400 chars | user-facing; same text rules |
| `tradeOffs` | [string ≤ 140] | verified trade-offs only (prep time, cost, variety) |
| `refusalReason` | `unsafeRequest` \| `outOfScope` \| `noCandidates` \| null | required when `status` ≠ `ok` |

Rules the validator enforces (see #37):

- `status == "ok"` requires ≥ 1 food; `"empty"` requires 0 foods and
  `refusalReason == "noCandidates"`; `"refused"` requires 0 foods and a reason.
- Unknown keys are ignored on decode but the raw body must be ≤ `maxResponseBytes`.
- Free-text fields may not contain: `\d+\s?(kcal|cal|calories|g|grams|mg|%)`,
  or the words `diagnos*`, `treat*`, `prescri*`, `supplement*`, `steroid*`,
  `dose`, `medication`, `cure`.

## Examples

### Valid

The response above.

### Invalid — unknown food ID

```json
{ "schemaVersion": 1, "requestID": "…", "status": "ok",
  "foods": [{ "foodID": "butter-chicken", "rationale": "high protein" }],
  "explanation": "Try this.", "tradeOffs": [], "refusalReason": null }
```
Rejected: `butter-chicken` is not in `candidateFoodIDs`. Local fallback.

### Invalid — invented fact

```json
{ "schemaVersion": 1, "requestID": "…", "status": "ok",
  "foods": [{ "foodID": "chana-masala", "rationale": "about 320 kcal and 18 g protein" }],
  "explanation": "A balanced choice.", "tradeOffs": [], "refusalReason": null }
```
Rejected: nutrient values in free text. Local fallback.

### Invalid — wrong version / malformed

```json
{ "schemaVersion": 2, "requestID": "…", "status": "ok", "foods": [] }
```
Rejected before validation: version mismatch (and missing required keys).

### Blocked

```json
{ "schemaVersion": 1, "requestID": "…", "status": "refused",
  "foods": [], "explanation": "", "tradeOffs": [],
  "refusalReason": "unsafeRequest" }
```
Accepted as a refusal; the client shows its own routing copy, never the model's.

### Empty

```json
{ "schemaVersion": 1, "requestID": "…", "status": "empty",
  "foods": [], "explanation": "", "tradeOffs": [],
  "refusalReason": "noCandidates" }
```
Accepted; the client shows the local "nothing fits right now" state.

## Secrets

None. The contract is plain JSON over the authenticated edge function; the
provider key lives only in the function's secrets.
