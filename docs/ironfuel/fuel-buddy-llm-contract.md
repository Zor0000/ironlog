# Fuel Buddy LLM contract v1

Provider-neutral request/response schemas for the optional LLM layer described
in `llm-variety-layer.md`. Tracks #35. Swift types live in
`IronLog/IronFuel/FuelBuddyLLMContract.swift` and round-trip these examples in
`IronLogTests/FuelBuddyLLMContractTests.swift`.

Two stages, one version:

| stage | request | response | the model may return |
|---|---|---|---|
| intent | `FuelBuddyIntentRequest` | `FuelBuddyIntentResponse` | enums + tags from the request's allowlists |
| presentation | `FuelBuddyPresentationRequest` | `FuelBuddyPresentationResponse` | caption copy + *pointers* to facts it was given |

Versioning: `schemaVersion` is an integer on every request and response. A
client only accepts responses whose `schemaVersion` equals the version it
sent. `policyVersion` identifies the deterministic safety policy that
pre-screened the request so evaluation runs can be compared over time.

Design constraints:

- **No response field can introduce a food, ingredient, nutrient value, food
  property or calorie target.** Foods are referenced by catalog ID; rationale
  and trade-offs are references to catalog *fact tokens* the request supplied;
  the single free-text field is screened caption copy.
- **The model cannot reorder.** Presentation `foods` must be exactly the first
  *N* request candidates in the request's order.
- **A model decline is a fallback.** `declined` is representable so a gateway
  can report it, but the client never shows model refusal copy — safety was
  decided by `FuelBuddySafetyPolicy` before the call.
- **User text is redacted before it can be sent.** `userText` is a
  `FuelBuddyRedactedText`, constructible only via `FuelBuddyRequestRedactor`
  (emails, URLs, phone numbers and body measurements → placeholders; truncated
  to 500 characters). The gate refuses text that is not in redacted form.

## Intent stage

### Request

```json
{
  "schemaVersion": 1,
  "policyVersion": "2026-09",
  "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10",
  "userText": "Suggest an Indian vegetarian dinner under 20 minutes",
  "knownCuisines": ["indian", "mexican", "italian", "thai"],
  "knownMealTags": ["quick", "high-protein", "comfort", "light"],
  "limits": { "timeoutMilliseconds": 4000, "maxResponseBytes": 2048, "maxFoods": 3, "maxOutputTokens": 120 }
}
```

### Response

```json
{
  "schemaVersion": 1,
  "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10",
  "status": "ok",
  "mealContext": {
    "mealType": "dinner",
    "cuisines": ["indian"],
    "mealTags": ["quick"],
    "maxPrepMinutes": 20,
    "budget": "any",
    "varietyIntent": "none"
  }
}
```

| field | rule |
|---|---|
| `mealContext.mealType` / `budget` / `varietyIntent` | closed enums |
| `mealContext.cuisines` | ⊆ `knownCuisines` |
| `mealContext.mealTags` | ⊆ `knownMealTags` |
| `mealContext.maxPrepMinutes` | int ≥ 0 or null |
| `status: "declined"` | client uses the local keyword intent |

There is no free text in the intent response.

## Presentation stage

### Request

```json
{
  "schemaVersion": 1,
  "policyVersion": "2026-09",
  "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10",
  "userText": "Suggest an Indian vegetarian dinner under 20 minutes",
  "mealContext": { "mealType": "dinner", "cuisines": ["indian"], "mealTags": ["quick"], "maxPrepMinutes": 20, "budget": "any", "varietyIntent": "differentFromRecent" },
  "profileContext": { "ruleTags": ["vegetarian", "no-peanut"], "recentFoodIDs": ["dal-tadka", "paneer-bhurji"] },
  "candidates": [
    { "foodID": "chana-masala",    "displayName": "Chana Masala",    "facts": ["cuisine:indian", "diet:vegetarian", "prep:15-min", "budget:low", "variety:not-served-recently"] },
    { "foodID": "vegetable-pulao", "displayName": "Vegetable Pulao", "facts": ["cuisine:indian", "diet:vegetarian", "prep:20-min", "budget:low", "variety:new-cuisine-this-week"] },
    { "foodID": "palak-paneer",    "displayName": "Palak Paneer",    "facts": ["cuisine:indian", "diet:vegetarian", "prep:25-min", "budget:moderate"] }
  ],
  "limits": { "timeoutMilliseconds": 4000, "maxResponseBytes": 8192, "maxFoods": 2, "maxOutputTokens": 400 }
}
```

| field | type | notes |
|---|---|---|
| `userText` | redacted string ≤ 500 | after `FuelBuddyRequestRedactor` and `FuelBuddySafetyPolicy` |
| `mealContext` | see above | from intent extraction or the local keyword intent |
| `profileContext.ruleTags` | [string] | resolved deterministic rule tags — never raw conditions |
| `profileContext.recentFoodIDs` | [string] | what the rotation moved away from |
| `candidates[]` | ≤ `maxCandidates` (12) | **the output of `FoodRuleEngine` → `EnergyFirewall` → `MealVarietyRotation`, in that order** |
| `candidates[].facts` | ≤ 12 `namespace:value` tokens | derived from the curated catalog + rotation factors; the only facts the model may cite |
| `limits.maxOutputTokens` | int | forwarded to the provider by the gateway |

Explicitly **not** present: email, account/user id, name, body metrics,
clinical details, free-text health history, the full food catalog.

### Response

```json
{
  "schemaVersion": 1,
  "requestID": "8C7E1A3E-6B0B-4C7C-9C3B-1B9B5B3E2F10",
  "status": "ok",
  "foods": [
    { "foodID": "chana-masala",    "rationaleFacts": ["prep:15-min", "variety:not-served-recently"] },
    { "foodID": "vegetable-pulao", "rationaleFacts": ["variety:new-cuisine-this-week"] }
  ],
  "explanation": "Two quick Indian dinners that steer away from what you had this week.",
  "tradeOffs": [ { "foodID": "vegetable-pulao", "fact": "prep:20-min" } ],
  "declineReason": null
}
```

| field | rule |
|---|---|
| `foods` | exactly `candidates[0..<N]` in order, `1 ≤ N ≤ maxFoods`, when `status == ok` |
| `foods[].rationaleFacts` | ⊆ that candidate's `facts`; may be empty |
| `tradeOffs[].foodID` | one of `foods[].foodID` |
| `tradeOffs[].fact` | ∈ that candidate's `facts` |
| `explanation` | ≤ 400 chars; must pass the free-text screen below |
| `status: "declined"` + `declineReason` | accepted as a well-formed *fallback*; foods must be empty |
| `status: "ok"` + `declineReason` | rejected (contradictory) |

#### Free-text screen (`explanation`)

Rejected if it contains any of:

- a number with a nutrient/energy unit — `\d+\s?(kcal|cal|calories|kj|g|grams|mg|mcg|percent)` or `\d+\s?%`;
- medical / treatment language — `diagnos*`, `treat`, `treats`, `treated`, `treating`, `treatment`, `prescri*`, `medication`, `cure*`, `dose`, `dosage`, `heal*`;
- supplement language — `supplement*`, `steroid*`, `creatine`, `whey`, `protein powder`, `fat burner`, …;
- **ingredient / allergen vocabulary** — the 14 major allergens and their common forms (peanut, nut, almond, cashew, milk, dairy, cheese, butter, egg, wheat, gluten, soy, sesame, fish, shellfish, prawn, shrimp, mustard, celery, lupin, sulphite) plus common proteins (chicken, beef, pork, lamb, tofu, …);
- **property-claim phrasing** — `contains`, `free of`, `-free`, `without`, `no <ingredient>`, `rich in`, `high in`, `low in`, `source of`, `packed with`, `reduces`, `boosts`, `improves`, `helps with`, `good for`, `bad for`, `healthy`, `unhealthy`, `safe for`.

The explanation can say *why this order* ("steers away from what you had this
week", "keeps to your twenty-minute window"); it cannot say *what a food is*.
Every food property the UI shows comes from `facts`.

## Examples

### Valid

The presentation response above.

### Invalid — reordered or partial

```json
{ "status": "ok", "foods": [{ "foodID": "vegetable-pulao", "rationaleFacts": [] }, { "foodID": "chana-masala", "rationaleFacts": [] }], "explanation": "…", "tradeOffs": [] }
```
Rejected (`order_mismatch`): the model doesn't get to decide which meal leads.

### Invalid — unknown food ID

```json
{ "status": "ok", "foods": [{ "foodID": "butter-chicken", "rationaleFacts": [] }], "explanation": "Try this.", "tradeOffs": [] }
```
Rejected (`unknown_food_id`). Local fallback.

### Invalid — fact not in the request

```json
{ "status": "ok", "foods": [{ "foodID": "chana-masala", "rationaleFacts": ["nutrition:high-protein"] }], "explanation": "…", "tradeOffs": [] }
```
Rejected (`unapproved_fact`): the model cannot mint a fact.

### Invalid — invented property in free text

```json
{ "status": "ok", "foods": [{ "foodID": "chana-masala", "rationaleFacts": [] }], "explanation": "Peanut-free and about 320 kcal.", "tradeOffs": [] }
```
Rejected (`forbidden_language`): allergen vocabulary, a claim, and a number with a unit.

### Invalid — wrong version / malformed

```json
{ "schemaVersion": 2, "requestID": "…", "status": "ok", "foods": [] }
```
Rejected before validation (`schema_version_mismatch`).

### Declined (well-formed fallback)

```json
{ "schemaVersion": 1, "requestID": "…", "status": "declined", "foods": [], "explanation": "", "tradeOffs": [], "declineReason": "outOfScope" }
```
Accepted as a shape; the client shows the local answer (`model_declined`).

### Empty candidates

When the deterministic pipeline yields no candidates the client never calls
the model; it shows its own "nothing fits right now" state. `noCandidates`
exists only so a gateway can report a malformed empty request.

## Secrets

None. The contract is plain JSON over the authenticated edge function; the
provider key lives only in the function's secrets.
