# IronFuel: optional LLM-assisted variety layer

Status: **design** — no model calls ship with this document. Tracks #34.

## Why

Fuel Buddy answers plain-language meal requests ("quick high-protein lunch",
"something different from yesterday", "Indian vegetarian dinner under 20
minutes"). A language model can understand those requests and phrase the
answer better than a rule table can. It must not be allowed to make any
decision that affects safety or nutrition.

## The one rule

> The model may **interpret** and **present**. Deterministic code **decides**.

Everything below follows from that. If a future change lets the model choose a
food, state a nutrient value, or set a target, it violates this design.

## What the model never does

- Override allergies, intolerances, religious rules or user exclusions.
- Invent food facts: calories, protein, fibre, ingredients, health claims.
- Produce supplement, steroid, diagnosis or treatment advice.
- Create or validate calorie targets.
- Recommend anything outside the approved curated catalog.
- Replace `FoodRuleEngine` (hard filters) or `EnergyFirewall` (energy limits).

## Pipeline

```
user text
   │
   ▼
1. FuelBuddySafetyPolicy (deterministic)      blocked? → refusal / routing copy, stop
   │
   ▼
2. Intent extraction (LLM, optional)          fails?  → local keyword intent
   │  request JSON  →  intent JSON
   ▼
3. FoodRuleEngine (deterministic)             hard filters: allergy, intolerance,
   │                                          religious/ethical rules, exclusions
   ▼
4. EnergyFirewall (deterministic)             energy/portion bounds
   │
   ▼
5. MealVarietyRotation (deterministic)        recency/frequency penalty, cuisine
   │  ordered approved food IDs               and meal-tag rotation, stable tie-break
   ▼
6. Presentation (LLM, optional)               explanation + ordering rationale,
   │  response JSON                           referencing approved IDs only
   ▼
7. FuelBuddyResponseValidator (deterministic) unknown ID / invented fact /
   │                                          medical language / size / schema
   ▼
8. Local fallback if 2, 6 or 7 fail           existing deterministic Fuel Buddy
   │                                          response (never empty-handed when
   ▼                                          a safe local answer exists)
rendered answer
```

Steps 1, 3, 4, 5, 7 and 8 are pure Swift, run on device, and have no network
dependency. Steps 2 and 6 are the only places a model is consulted, and both
are optional: the pipeline produces a correct answer with them switched off.

## Data contracts

Defined in `docs/ironfuel/fuel-buddy-llm-contract.md` (#35) and mirrored in
`IronLog/IronFuel/FuelBuddyLLMContract.swift`.

- **Request** — the user's text, meal context (meal type, cuisine, prep time,
  budget, variety intent), the *approved* profile context the deterministic
  filter needs (already-resolved rule tags, not raw clinical data), the
  candidate food IDs that survived steps 3–5, schema + policy version, request
  id, timeout/fallback metadata. No email, account id, or free-text health
  history ever leaves the device.
- **Response** — approved food IDs in presentation order, a rationale per
  food, user-facing explanation, verified trade-offs, and a safety status
  (`ok`, `refused(reason)`, `empty`). There is no field in which the model can
  express a new food, a nutrient number, an ingredient or a calorie target;
  the validator rejects any of those if they leak into free text.

## Where it runs

```
iOS app ──HTTPS + user JWT──▶ Supabase Edge Function `fuel-buddy` ──▶ model provider
   ▲                                   │
   └──── response JSON (validated again on device) ◀──┘
```

- The iOS client never holds a provider secret. It calls the edge function
  with the user's Supabase session token, exactly like `delete-account`.
- The edge function holds the provider key as a function secret, applies the
  same schema validation server-side, enforces the timeout and a per-user
  rate limit, and strips anything that is not the response contract.
- Deploying the function and rotating its secrets stays maintainer-controlled
  (see `README.md` § Supabase source of truth). Contributors run the local
  fallback path without any credentials.

## Privacy

- Send only what step 2/6 needs: the request text, meal context, resolved rule
  *tags* (e.g. `no-peanut`, `vegetarian`, `halal`) and candidate food IDs.
- Never send: email, user id, weight/height, medical notes, full history.
- Do not log raw request text or profile data by default; log the
  non-sensitive diagnostic state (`FuelBuddyDiagnostic`) from #37.
- Users can turn the layer off; the local path is the default until they
  opt in.

## Latency and cost

- One round-trip per request for step 2 and one for step 6; both run under a
  hard timeout (default 4 s each) after which the local path answers.
- Cache the intent JSON for identical (text, context) pairs for the session.
- Cost is bounded by the rate limit in the edge function and by the maximum
  response size (`maxResponseBytes`, #37).

## Fallback

The deterministic Fuel Buddy response is always computed first (it is cheap)
and returned whenever the model is unavailable, times out, returns malformed
JSON, fails schema validation, references an unknown food, or trips the
language filter. The client surfaces which happened via `FuelBuddyDiagnostic`
for metrics; the user just sees a good answer.

## Testing

- Unit tests for every deterministic step run without a provider (#36, #37).
- `IronFuelSafetyEvaluationTests` (#38) replays fixture requests and
  fixture model outputs — including adversarial ones — through the full
  client pipeline and asserts the safety contract holds.
- Provider changes are evaluated by re-running the fixtures; they need no
  production credentials.

## Follow-ups

| Issue | Delivers |
|---|---|
| #35 | Versioned, provider-neutral request/response contract + Codable types |
| #36 | `MealVarietyRotation` — deterministic variety over the safety-filtered pool |
| #37 | `FuelBuddyResponseValidator` + `FuelBuddyGate` (timeout, fallback, diagnostics) |
| #38 | Safety / hallucination evaluation suite with documented fixtures |

## Repository note

At the time of writing there is no IronFuel code in this repository —
`FoodRuleEngine`, `EnergyFirewall`, `FoodFactsProvider` and the local Fuel
Buddy are referenced by the issues but not yet committed. The follow-up PRs
therefore add an isolated `IronLog/IronFuel/` module built against small
protocol seams (`FoodCatalog`, `FoodRuleCheck`, `FuelBuddyLocalResponder`) so
that the real engines can be dropped in without changing the guardrails.
