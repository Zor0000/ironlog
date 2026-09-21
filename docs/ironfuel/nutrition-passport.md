# Nutrition Passport and IronFuel UI

IronFuel is a top-level app section. It begins with a private Nutrition Passport and keeps personalized Fuel Buddy suggestions locked until the required context, goal, and safety review are complete.

## State model

- **Empty:** explains the Passport, privacy, deletion, and gating before any form is shown.
- **Incomplete:** saves work locally and offers a clear route back to the guided flow. Fuel Buddy remains unavailable.
- **Ready:** shows the Energy Firewall status, readable Passport summary, edit/delete controls, ordered goal stack, and Fuel Buddy.
- **No compatible result:** keeps every hard rule intact and asks for a broader request instead of silently relaxing rules.
- **Safety routed:** pauses suggestions and points minors, pregnancy/breastfeeding, eating-disorder concerns, and professionally managed diets toward qualified support.
- **Offline:** uses the same deterministic approved on-device catalog and labels the fallback.
- **Error:** preserves the Passport and offers retry/local fallback copy without fabricating a result.

## Boundaries

Allergies, intolerances, dietary identity, religious or ethical exclusions, and never-suggest entries are hard rules. `FuelBuddyRecommendationEngine` filters the curated catalog against these rules before presentation; user or model text cannot override the result. The existing `FuelBuddySafetyPolicy` screens requests for medical treatment, supplements/steroids, punitive restriction, rule bypasses, and professional-routing triggers.

The app never calculates, prescribes, or silently changes an energy target. A target can only be recorded with its source. Explanations come from approved catalog facts such as cuisine, preparation time, budget, and cooking requirements.

## Persistence and privacy

The Passport lives in the same owner-scoped local snapshot as the rest of the app. Guest data migrates into a newly signed-in account, while signed-in snapshots remain isolated by account ID. Deleting a Passport removes only IronFuel profile data; workout and run history are unchanged.

The selected Progress subview is intentionally session-only. It defaults to Stats on a fresh launch and remembers Stats or History while the app remains open.
