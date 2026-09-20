# IronFuel safety & hallucination evaluation

Tracks #38. The suite lives in `IronLogTests/IronFuelSafetyEvaluationTests.swift`
and runs as part of the normal unit tests — no model, no network, no
credentials. It proves that adding a model cannot weaken the safety contract
described in `llm-variety-layer.md`.

```bash
xcodebuild test -project IronLog.xcodeproj -scheme IronLog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:IronLogTests/IronFuelSafetyEvaluationTests CODE_SIGNING_ALLOWED=NO
```

## What is evaluated

| layer | fixture | asserts |
|---|---|---|
| `FuelBuddySafetyPolicy.screen` | `Fixtures/IronFuel/fuel-buddy-requests.json` | every request resolves to the documented `allowed` / `blocked:<reason>` / `routed:<reason>`; every block and routing reason has at least one case; nothing unsafe is `allowed` |
| `FuelBuddyGate` → `FuelBuddyResponseValidator` | `Fixtures/IronFuel/fuel-buddy-model-outputs.json` | every raw provider payload (or provider failure) resolves to `model` or `local:<diagnostic>`; whenever a model answer *is* accepted, every food is an approved candidate that still passes current rules and no free text contains a nutrient figure or medical/supplement language; the local answer is always present |
| `MealVarietyRotation` | inline | history cannot resurrect a food the rule engine excluded |

### Request categories covered

Allergy/intolerance bypass · religious/ethical rule bypass · exclusion bypass ·
supplements/steroids/fat burners · diagnosis/treatment/prescription ·
crash-diet, punishment and compensatory-exercise language · under-18 ·
pregnancy/breastfeeding · disordered eating · clinician-managed diets ·
routing-beats-blocking precedence · benign requests that must stay allowed
(including adult ages, so the under-18 detector isn't over-eager).

### Model-output categories covered

Invented food names and look-alike IDs · invented calories, protein, fibre
percentages, ingredient health claims · calorie targets · supplement and
medical advice · a "variety" answer that reintroduces a food the current
rules reject · unknown schema version · malformed JSON, wrong types, prose
instead of JSON · inconsistent status shapes · too many foods · provider
timeout, rate limit, unavailable · valid answers and valid refusals (which
must be accepted, so the guardrails aren't just "reject everything").

## Adding a case

1. Append to the relevant fixture. Give it a stable `id`, the exact input,
   and the expected outcome string. For model outputs, `body` is the raw
   bytes the provider would return (`REQ` is substituted with the request
   id); use `provider: timeout|rateLimited|unavailable` for transport
   failures and `rulesReject` to simulate a profile change after the
   candidates were computed.
2. Run the suite. A new bypass that slips through fails
   `testEveryRequestFixtureScreensAsDocumented` — fix the policy, then bump
   `FuelBuddySafetyPolicy.version` **and** the fixture's `policyVersion`.
3. Never delete a case. Regressions are exactly what this file is for.

## Evaluating a new model or provider

The fixtures are provider-neutral: they are what a model *might* return, not
what a specific one did. To evaluate a real provider:

1. Run the candidate model against the request fixtures' `allowed` cases
   (outside this repo, with your own credentials) and save each raw response.
2. Add the raw responses as new model-output cases with the outcome you
   observed from the validator.
3. Any case that resolves to `model` but violates the "never reach the user"
   rules will fail `testHallucinatedFoodsAndFactsNeverReachTheUser` — that
   is a validator gap, not a fixture problem. Fix the validator.

A provider change should therefore never require changing an assertion, only
adding fixtures.
