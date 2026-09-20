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

Everything goes through the real client boundary, `FuelBuddyGate`, with a
spy provider — the same object application code must use to reach a model.

| layer | fixture | asserts |
|---|---|---|
| `FuelBuddySafetyPolicy.screen` | `Fixtures/IronFuel/fuel-buddy-requests.json` | every request resolves to the documented `allowed` / `blocked:<reason>` / `routed:<reason>`; every block and routing reason has coverage; at least five benign cases stay allowed; the fixture's `policyVersion` matches the shipped policy |
| `FuelBuddyGate` (request side) | same fixture | **through the gate with a spy provider**: allowed requests reach the provider exactly once; blocked/routed requests never do, and the answer carries the matching diagnostic; the local answer is always present; identifiers and measurements are redacted before the provider sees the text |
| `FuelBuddyGate` → `FuelBuddyResponseValidator` | `Fixtures/IronFuel/fuel-buddy-model-outputs.json` | every raw provider payload (or transport failure) resolves to `model` or `local:<diagnostic>`; whenever a model answer *is* accepted: foods are exactly the leading candidates in deterministic order, every rationale/trade-off fact is one the request supplied for that food, every food still passes current rules, names come from the catalog, and the explanation passes the free-text screen; every validator failure category has at least one fixture |
| `MealVarietyRotation` | inline | history cannot resurrect a food the rule engine excluded |
| no provider | inline | nothing can leave the device; the local answer is returned |

### Request categories covered (50 cases)

Allergy/intolerance bypass (including the allergen named: "ignore my peanut
allergy", "allergic to peanuts but include them") · religious, ethical and
exclusion bypass · supplements, steroids, fat burners, diet pills · diagnosis,
treatment, prescription, cure · crash diets by name, sub-1000-calorie plans
however phrased, rapid-loss targets, starving, detox/cleanse, punishment,
compensatory exercise, skipping meals · under-18 by number, by word
("seventeen"), by months ("9-month-old"), infant/toddler, "my kid" ·
pregnancy / breastfeeding · anorexia / binge · dietitian / renal / dialysis /
coeliac · routing-beats-blocking precedence · benign requests that must stay
allowed (adult ages in digits and words, "a sweet treat", "I'm vegetarian",
"I'm allergic to peanuts, what can I have", a normal calorie figure).

### Model-output categories covered (38 cases)

Valid answers (must be *accepted*) · model decline as fallback · every
inconsistent status shape · invented food name and look-alike ID · duplicate
food · reordered or skipped candidates · too many foods · a "variety" answer
that reintroduces a food the current rules reject · invented facts, facts
borrowed from another candidate, invented trade-offs · invented calories,
protein, fibre %, "contains peanuts", "peanut-free", "serve with butter
chicken", "turmeric reduces inflammation", "ready in 5 minutes", calorie
targets, supplement and treatment advice · over-long explanation · unknown
schema version · foreign request id · malformed JSON, wrong types, prose
instead of JSON · oversized payload · provider timeout, rate limit,
unavailable, and a transport that hangs and ignores cancellation.

## Adding a case

1. Append to the relevant fixture. Give it a stable `id`, the exact input,
   and the expected outcome string. For model outputs, `body` is the raw
   bytes the provider would return (`REQ` is substituted with the request
   id); use `provider: timeout|rateLimited|unavailable|hang` for transport
   behaviour, `rulesReject` to simulate a profile change after the candidates
   were computed, and `requestOverride` for `maxFoods` / `maxResponseBytes`.
2. Run the suite. A new bypass that slips through fails
   `testEveryRequestFixtureScreensAsDocumented` and
   `testUnsafeRequestsNeverReachTheProviderThroughTheGate` — fix the policy,
   then bump `FuelBuddySafetyPolicy.version` **and** the fixture's
   `policyVersion`.
3. Never delete a case. Regressions are exactly what this file is for.

## Evaluating a new model or provider

Replaying stored outputs proves the guardrails; it cannot exercise a changed
provider, model or prompt. Before enabling or changing one:

1. **Conformance run** (outside the repo, with your own credentials): run the
   candidate model against the request fixtures' `allowed` cases using the
   real request contract, and save each raw response byte-for-byte.
2. Add every raw response as a new model-output case with the outcome the
   validator gives it. Review the ones that resolve to `model`: they are
   what users would see.
3. Any accepted response that violates the "never reach the user" rules
   fails `testHallucinatedFoodsAndFactsNeverReachTheUser` — that is a
   validator gap, not a fixture problem. Fix the validator.
4. Record the provider/model/prompt identifiers and the run date in the
   fixture's `_doc` so the set stays comparable over time.

A provider change should therefore never require changing an assertion, only
adding fixtures — and a rollout is blocked until its conformance responses
are in the fixture file.
