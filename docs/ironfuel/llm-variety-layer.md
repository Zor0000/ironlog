# IronFuel: optional LLM-assisted variety layer

Status: **design** — no model calls ship with this document. Tracks #34.

## Why

Fuel Buddy answers plain-language meal requests ("quick high-protein lunch",
"something different from yesterday", "Indian vegetarian dinner under 20
minutes"). A language model can understand those requests and phrase the
answer better than a rule table can. It must not be allowed to make any
decision that affects safety or nutrition.

## The one rule

> The model may **interpret** and **phrase**. Deterministic code **decides**
> — and owns every fact.

Everything below follows from that. If a future change lets the model choose a
food, order foods, state a food property, or set a target, it violates this
design.

## What the model never does

- Override allergies, intolerances, religious rules or user exclusions.
- Invent food facts: calories, protein, fibre, ingredients, allergens, prep
  time, cost, health claims.
- Produce supplement, steroid, diagnosis or treatment advice.
- Create or validate calorie targets.
- Recommend, mention or rank anything outside the approved candidate list.
- Suppress a safe answer: a model refusal is a *fallback*, never a decision.
- Replace `FoodRuleEngine` (hard filters) or `EnergyFirewall` (energy limits).

## Pipeline

```
user text
   │
   ▼
0. FuelBuddyRequestRedactor (deterministic)   emails, phone numbers, body
   │                                          measurements → placeholders;
   │                                          truncate to the contract limit
   ▼
1. FuelBuddyConstraintResolver (deterministic) profile rules + recognised
   │                                          explicit text restrictions →
   │                                          canonical required-rule tags;
   │                                          ambiguous safety text → clarify, stop
   ▼
2. FuelBuddySafetyPolicy (deterministic)      blocked? → refusal / routing copy, stop
   │
   ▼
3. Intent extraction (LLM, optional)          FuelBuddyIntentRequest → preferences only
   │  enums + allowlisted tags only            cannot add, remove or weaken rules;
   │                                          fails? → local keyword intent
   ▼
4. FoodRuleEngine (deterministic)             hard filters: allergy, intolerance,
   │                                          religious/ethical rules, exclusions
   ▼
5. EnergyFirewall (deterministic)             energy/portion bounds
   │
   ▼
6. MealVarietyRotation (deterministic)        recency/frequency penalty, cuisine
   │  ordered candidates + catalog facts       and meal-tag rotation, stable tie-break
   ▼
7. Presentation (LLM, optional)               FuelBuddyPresentationRequest →
   │  an allowlisted presentation key +         per-food rationale facts,
   │  which approved facts to highlight         trade-off facts
   ▼
8. FuelBuddyResponseValidator (deterministic) order must match step 6 / facts
   │                                          must be from the request / key,
   │                                          size and schema validated
   ▼
9. Local fallback if 3, 7 or 8 fail,          existing deterministic Fuel Buddy
   │  or if the model declines                  response (never empty-handed when
   ▼                                            a safe local answer exists)
rendered answer
```

Steps 0, 1, 2, 4, 5, 6, 8 and 9 are pure Swift, run on device, and have no
network dependency. Steps 3 and 7 are the only places a model is consulted,
and both are optional: the pipeline produces a correct answer with them
switched off.

### Safety constraints are fixed before the model sees the request

`FuelBuddyConstraintResolver` starts from the user's profile rules and merges
recognised explicit restrictions in the request, such as "no peanuts" or
"vegetarian". It produces the canonical tags that `FoodRuleEngine` must use;
the intent model receives them as read-only context and cannot add, remove, or
weaken them. If text appears to state an allergy, intolerance, exclusion, or
religious rule but cannot be mapped deterministically, the app asks for
clarification and does not call a model or make a recommendation from that
request. A local keyword intent is only a preference fallback; it never
replaces constraint resolution.

### Grounding: the model only chooses from facts it was given

The presentation request carries, for each candidate, its catalog **display
name** and a list of catalog-derived **fact tokens** (`prep:15-min`,
`cuisine:indian`, `diet:vegetarian`, `budget:low`, `tag:high-protein`,
`variety:not-served-recently`). The response can only *point at* those
tokens — a rationale is a subset of the candidate's facts, a trade-off is one
of the candidate's facts. The UI renders facts from the catalog, never from
model text. There is no free-text `explanation` field: the response selects an
allowlisted presentation key and fact references, and the app fills a fixed,
localised template from those catalog facts. Catalogs with opaque IDs therefore
still work: the model never needs to know what an ID is beyond the name and
facts it was handed.

### Ordering is not the model's

`candidates` arrive in the order `MealVarietyRotation` produced. Deterministic
code fixes `N = min(candidates.count, maxFoods)` before presentation. The
response's `foods` must be exactly the first `N` candidates in that sequence;
any omission, reordering or addition is rejected and the local answer is
shown.

### Two request shapes, one version

Intent extraction happens before candidates exist, so it has its own contract
(`FuelBuddyIntentRequest` / `FuelBuddyIntentResponse`: preference enums and
tags from an allowlist the client supplies, never safety constraints).
Presentation has `FuelBuddyPresentationRequest` / `FuelBuddyPresentationResponse`.
Both share `schemaVersion` and
`policyVersion`. Full schema: `docs/ironfuel/fuel-buddy-llm-contract.md` (#35),
mirrored in `IronLog/IronFuel/FuelBuddyLLMContract.swift`.

## Data flow rules

- **Request** — the *redacted* user text, meal context, the resolved rule
  *tags* (`vegetarian`, `no-peanut`) that the deterministic constraint resolver
  and filter fixed, recent
  food IDs, the ordered candidates with names and facts, schema + policy
  version, request id, limits. No email, account id, body metrics, or free-text
  health history leaves the device: `FuelBuddyRequestRedactor` replaces
  emails, phone numbers and measurements before the request can be built, and
  the gate refuses to send text that isn't in redacted form or exceeds
  `maxUserTextLength`.
- **Response** — status, foods (ID + rationale facts) in the required order,
  an allowlisted presentation key, and trade-off facts. `declined` is
  representable so the gateway can report a provider-side refusal, but the
  client always treats it as a fallback: safety was decided in step 2.

## Where it runs

```
iOS app ──HTTPS + user JWT──▶ Supabase Edge Function `fuel-buddy` ──▶ model provider
   ▲                                   │
   └──── response JSON (validated again on device) ◀──┘
```

- The iOS client never holds a provider secret. It calls the edge function
  with the user's Supabase session token, exactly like `delete-account`.
- The edge function holds the provider key as a function secret, applies the
  same schema validation server-side, enforces the timeout, a per-user rate
  limit, a **request byte limit** and a **provider-side maximum output
  tokens** (from `limits.maxOutputTokens`), and strips anything that is not
  the response contract.
- Deploying the function and rotating its secrets stays maintainer-controlled
  (see `README.md` § Supabase source of truth). Contributors run the local
  fallback path without any credentials.

## Privacy

- Send only what steps 3/7 need: redacted request text, meal context, rule
  *tags*, recent food IDs, candidate names + facts.
- Never send: email, user id, weight/height, medical notes, full history.
- Do not log raw request text or profile data by default; log the
  non-sensitive `FuelBuddyDiagnostic` code from #37 (it carries no strings
  from the model or the user).
- Users can turn the layer off; the local path is the default until they
  opt in.

## Latency and cost

- One round-trip per request for step 3 and one for step 7; both run under a
  hard timeout (default 4 s each) after which the local path answers, and the
  timeout does not depend on the transport cooperating with cancellation.
- Input is bounded on device (`maxUserTextLength`, `maxCandidates`,
  `maxFactsPerCandidate`) and again at the gateway (request bytes). Output is
  bounded at the provider (`maxOutputTokens`) so a rejected oversized response
  is a defence in depth, not the cost control.
- Cache the intent JSON for identical (text, context) pairs for the session.
- Cost is further bounded by the gateway's per-user rate limit.

## Fallback

The deterministic Fuel Buddy response is always computed first (it is cheap)
and returned whenever the model is switched off, unavailable, rate limited,
times out, returns malformed JSON, fails schema validation, reorders or
omits candidates, references an unknown food or fact, or declines a request
the policy already allowed. The client surfaces
which happened via `FuelBuddyDiagnostic` for metrics; the user just sees a
good answer.

## Testing

- Unit tests for every deterministic step run without a provider (#36, #37).
- `IronFuelSafetyEvaluationTests` (#38) replays fixture requests and
  fixture model outputs — including adversarial ones — through the full
  client pipeline (policy → gate → validator, with a spy provider) and asserts
  the safety contract holds.
- **Provider conformance run** (before enabling or changing a provider,
  model or prompt): run the *allowed* request fixtures against the real
  provider outside the repo with your own credentials, capture the raw
  responses, add them to the model-output fixtures with the outcome the
  validator gives, and review any that were accepted. Replaying stored
  outputs proves the guardrails; the conformance run is what exercises the
  changed component. Neither requires production credentials in CI.

## Follow-ups

| Issue | Delivers |
|---|---|
| #35 | Versioned, provider-neutral intent + presentation contracts, Codable types, redactor |
| #36 | `MealVarietyRotation` — deterministic variety over the safety-filtered pool |
| #37 | `FuelBuddyResponseValidator`, `FuelBuddySafetyPolicy`, `FuelBuddyGate` (screen, sanitise, timeout, fallback, diagnostics) |
| #38 | Safety / hallucination evaluation suite with documented fixtures and the conformance procedure |

## Repository note

At the time of writing there is no IronFuel code in this repository —
`FoodRuleEngine`, `EnergyFirewall`, `FoodFactsProvider` and the local Fuel
Buddy are referenced by the issues but not yet committed. The follow-up PRs
therefore add an isolated `IronLog/IronFuel/` module built against small
protocol seams (`ApprovedFood`, `FuelBuddyCandidate`, `passesCurrentRules`,
`FuelBuddyLLMProvider`) so that the real engines can be dropped in without
changing the guardrails.
