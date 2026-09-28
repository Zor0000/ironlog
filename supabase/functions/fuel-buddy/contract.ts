export const schemaVersion = 2;
export const identities = ["No dietary identity", "Vegetarian", "Vegan", "Jain", "Halal", "Kosher"];
export const abilities = ["Assemble only", "Basic cooking", "Confident cook"];
export const budgets = ["Value", "Flexible"];
export const meals = ["any", "breakfast", "lunch", "dinner", "snack"];
export const tags = ["vegan", "vegetarian", "jain", "halal", "kosher"];
export type Preferences = {
  dietaryIdentity: string; excludedIngredients: string[]; dislikes: string[];
  preferredCuisines: string[]; availableFoods: string[]; budget: string;
  maxCookingMinutes: number; cookingAbility: string;
};
export type GenerationRequest = {
  schemaVersion: number; policyVersion: string; requestID: string;
  userText: string; maxOptions: number; preferences: Preferences;
};
export type Dish = {
  name: string; mealType: string; cuisine: string; prepMinutes: number;
  ingredients: string[]; proteinSources: string[]; dietaryTags: string[];
  cookingAbility: string; budget: string;
};
export type Generation = { status: "ok" | "no_match"; options: Dish[] };

const list = { type: "array", items: { type: "string" } };
export const generationSchema = {
  type: "object", additionalProperties: false, required: ["status", "options"],
  properties: {
    status: { type: "string", enum: ["ok", "no_match"] },
    options: {
      type: "array", maxItems: 5,
      items: {
        type: "object", additionalProperties: false,
        required: ["name", "mealType", "cuisine", "prepMinutes", "ingredients", "proteinSources", "dietaryTags", "cookingAbility", "budget"],
        properties: {
          name: { type: "string" }, mealType: { type: "string", enum: meals },
          cuisine: { type: "string" }, prepMinutes: { type: "integer" },
          ingredients: list, proteinSources: list,
          dietaryTags: { type: "array", items: { type: "string", enum: tags } },
          cookingAbility: { type: "string", enum: abilities }, budget: { type: "string", enum: budgets },
        },
      },
    },
  },
};

export function text(value: unknown, max: number): value is string {
  return typeof value === "string" && value.trim() === value && value.length >= 1 && value.length <= max && !/[\n\r<>]/.test(value);
}
function strings(value: unknown, max = 30): value is string[] {
  return Array.isArray(value) && value.length <= max && value.every((v) => text(v, 80));
}
function object(value: unknown): value is Record<string, unknown> { return !!value && typeof value === "object" && !Array.isArray(value); }
function exactKeys(value: Record<string, unknown>, keys: string[]) {
  return Object.keys(value).length === keys.length && keys.every((key) => key in value);
}
export function validRequest(value: unknown): value is GenerationRequest {
  if (!object(value) || !exactKeys(value, ["schemaVersion", "policyVersion", "requestID", "userText", "maxOptions", "preferences"])) return false;
  const p = value.preferences;
  return value.schemaVersion === schemaVersion && value.policyVersion === "2026-09" &&
    typeof value.requestID === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value.requestID) &&
    text(value.userText, 500) && Number.isInteger(value.maxOptions) && Number(value.maxOptions) >= 1 && Number(value.maxOptions) <= 5 &&
    object(p) && exactKeys(p, ["dietaryIdentity", "excludedIngredients", "dislikes", "preferredCuisines", "availableFoods", "budget", "maxCookingMinutes", "cookingAbility"]) &&
    identities.includes(String(p.dietaryIdentity)) && strings(p.excludedIngredients) && strings(p.dislikes) &&
    strings(p.preferredCuisines) && strings(p.availableFoods) && budgets.includes(String(p.budget)) &&
    Number.isInteger(p.maxCookingMinutes) && Number(p.maxCookingMinutes) >= 1 && Number(p.maxCookingMinutes) <= 240 && abilities.includes(String(p.cookingAbility));
}

const aliases: Record<string, string> = {
  eggs: "egg", anda: "egg", chickpeas: "chickpea", chana: "chickpea", garbanzo: "chickpea", besan: "chickpea",
  dal: "lentil", daal: "lentil", lentils: "lentil", soya: "soy", curd: "yogurt", yoghurt: "yogurt",
  potatoes: "potato", tomatoes: "tomato", onions: "onion", groundnut: "peanut", peanuts: "peanut",
  prawns: "shrimp", almonds: "almond", cashews: "cashew", walnuts: "walnut",
  rotis: "roti", chapati: "roti", chapatis: "roti", oats: "oat", nuts: "nut", beans: "bean",
};
export function words(value: string): Set<string> {
  return new Set(value.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean).map((w) => aliases[w] ?? w));
}
const families = [
  ["dairy", "milk", "lactose", "paneer", "yogurt", "cheese", "butter", "cream", "ghee"],
  ["gluten", "wheat", "roti", "bread", "semolina", "barley", "rye", "oat"],
  ["soy", "tofu", "tempeh", "edamame"], ["peanut", "groundnut"],
  ["nut", "peanut", "almond", "cashew", "walnut", "pistachio", "hazelnut", "pecan"],
  ["chickpea", "hummus"], ["sesame", "tahini"],
  ["seafood", "fish", "salmon", "tuna", "cod", "sardine", "shrimp", "prawn", "crab", "lobster", "clam", "mussel"],
  ["shellfish", "shrimp", "prawn", "crab", "lobster", "clam", "mussel"],
  ["alcohol", "wine", "beer", "rum", "vodka", "bourbon", "mirin", "sake"],
];
export function containsRule(rule: string, ingredients: string[]): boolean {
  const terms = words(ingredients.join(" "));
  const ruleTerms = words(rule);
  if ([...ruleTerms].every((w) => terms.has(w))) return true;
  // Family expansion is directional: "nuts" excludes almond, but "almond"
  // should not by itself exclude every ingredient that is a nut.
  return families.some((family) => ruleTerms.has(family[0]) && family.some((w) => terms.has(w)));
}
const proteinWords = new Set(["egg", "chicken", "turkey", "fish", "salmon", "tuna", "shrimp", "beef", "pork", "paneer", "cheese", "yogurt", "lentil", "chickpea", "bean", "tofu", "tempeh", "edamame", "soy"]);
const foodWords = new Set([...proteinWords, "rice", "oat", "potato", "tomato", "onion", "mushroom", "spinach", "quinoa", "peanut", "almond", "sesame", "milk", "wheat", "roti", "bread", "avocado", "banana"]);
const meat = ["meat", "chicken", "turkey", "beef", "pork", "bacon", "ham", "lamb", "mutton", "duck", "gelatin", "fish", "seafood"];

export function constraints(request: GenerationRequest) {
  const q = request.userText.toLowerCase();
  const terms = words(q);
  const meal = meals.find((m) => m !== "any" && terms.has(m)) ?? (terms.has("brunch") || terms.has("morning") ? "breakfast" : "any");
  const cuisines = ["indian", "italian", "mexican", "thai", "chinese", "japanese", "korean", "mediterranean", "greek", "french", "lebanese"].filter((c) => terms.has(c));
  const minutes = q.match(/\b(\d{1,3})\s*(?:min(?:ute)?s?)\b/);
  const quick = /\b(quick|fast|speedy)\b/.test(q);
  const maxPrepMinutes = Math.min(request.preferences.maxCookingMinutes, minutes ? Number(minutes[1]) : quick ? 20 : 240);
  const excluded = [...request.preferences.excludedIngredients];
  // Additional query exclusions are additive, never replacements for Passport rules.
  for (const match of q.matchAll(/\b(?:without|avoid|exclude|no|not|omit)\s+([^,.;]+)/g)) {
    for (const food of words(match[1])) if (foodWords.has(food) || ["dairy", "gluten", "nuts", "nut", "shellfish", "alcohol"].includes(food)) excluded.push(food);
  }
  for (const match of q.matchAll(/\b(dairy|gluten|nut|peanut|egg|soy|milk)[ -]free\b/g)) excluded.push(match[1]);
  const required = [...terms].filter((w) => foodWords.has(w) && !excluded.some((e) => words(e).has(w)));
  const requiredTags = tags.filter((t) => terms.has(t));
  const identity = request.preferences.dietaryIdentity.toLowerCase();
  if (tags.includes(identity)) requiredTags.push(identity);
  return { meal, cuisines, maxPrepMinutes, excluded, required, requiredTags: [...new Set(requiredTags)], proteinFocused: /\bprotein\b/.test(q) };
}

export function validateGeneration(value: unknown, request: GenerationRequest): string | null {
  if (!object(value) || !exactKeys(value, ["status", "options"]) || !Array.isArray(value.options)) return "invalid_shape";
  if (value.status === "no_match") return value.options.length === 0 ? null : "inconsistent_status";
  if (value.status !== "ok" || value.options.length < 1 || value.options.length > request.maxOptions) return "invalid_count";
  const rules = constraints(request);
  const names = new Set<string>();
  for (const unknownDish of value.options) {
    if (!object(unknownDish) || !exactKeys(unknownDish, ["name", "mealType", "cuisine", "prepMinutes", "ingredients", "proteinSources", "dietaryTags", "cookingAbility", "budget"])) return "invalid_dish";
    const d = unknownDish;
    if (!text(d.name, 100) || !text(d.cuisine, 60) || !strings(d.ingredients, 24) || d.ingredients.length === 0 ||
        !strings(d.proteinSources, 10) || !strings(d.dietaryTags, 5) || d.dietaryTags.some((t) => !tags.includes(t)) ||
        !meals.includes(String(d.mealType)) || !abilities.includes(String(d.cookingAbility)) || !budgets.includes(String(d.budget)) ||
        !Number.isInteger(d.prepMinutes) || Number(d.prepMinutes) < 1 || Number(d.prepMinutes) > rules.maxPrepMinutes) return "invalid_metadata_or_time";
    const name = [...words(d.name)].sort().join(" ");
    if (names.has(name) || /^(meal|food|dish|breakfast|lunch|dinner|snack|healthy bowl|protein bowl|salad)$/.test(d.name.toLowerCase())) return "duplicate_or_vague_name";
    if (/\b(cure|treat|detox|fat.burning|allergen.free|safe for|protein powder|supplement|whey|creatine)\b|\b\d+\s*(kcal|calories|grams|mg)\b|https?:/i.test(d.name)) return "unsupported_claim";
    names.add(name);
    if (rules.meal !== "any" && d.mealType !== rules.meal) return "wrong_meal";
    if (rules.cuisines.length && !rules.cuisines.some((c) => words(String(d.cuisine)).has(c))) return "wrong_cuisine";
    const ingredientWords = words(d.ingredients.join(" "));
    if (!rules.required.every((food) => ingredientWords.has(food))) return "missing_requested_ingredient";
    if (rules.excluded.some((rule) => containsRule(rule, [String(d.name), ...(d.ingredients as string[])]))) return "excluded_ingredient";
    if (!rules.requiredTags.every((tag) => (d.dietaryTags as string[]).includes(tag))) return "dietary_mismatch";
    if (rules.requiredTags.some((t) => ["vegetarian", "vegan", "jain"].includes(t)) && [...meat, "egg"].some((r) => containsRule(r, d.ingredients as string[]))) return "nonvegetarian_ingredient";
    if (rules.requiredTags.includes("vegan") && ["dairy", "honey"].some((r) => containsRule(r, d.ingredients as string[]))) return "nonvegan_ingredient";
    if (rules.requiredTags.includes("jain") && ["onion", "garlic", "potato", "carrot", "beet", "radish", "ginger"].some((r) => containsRule(r, d.ingredients as string[]))) return "jain_exclusion";
    if (rules.requiredTags.includes("halal") && ["pork", "bacon", "ham", "alcohol"].some((r) => containsRule(r, d.ingredients as string[]))) return "halal_exclusion";
    if (request.preferences.budget === "Value" && d.budget !== "Value") return "over_budget";
    if (abilities.indexOf(String(d.cookingAbility)) > abilities.indexOf(request.preferences.cookingAbility)) return "cooking_ability";
    if (!d.proteinSources.every((p) => (d.ingredients as string[]).includes(p))) return "unsupported_protein_source";
    if (rules.proteinFocused && !d.proteinSources.some((p) => [...words(p)].some((w) => proteinWords.has(w)))) return "missing_protein_source";
  }
  return null;
}

// Canonicalize model metadata, then keep only independently valid candidates.
// A rejected candidate never becomes a fabricated local/catalog suggestion.
export function validatedCandidates(value: unknown, request: GenerationRequest): Generation | null {
  if (!object(value) || !exactKeys(value, ["status", "options"]) || !Array.isArray(value.options)) return null;
  if (value.status === "no_match") return value.options.length === 0 ? { status: "no_match", options: [] } : null;
  if (value.status !== "ok" || value.options.length < 1 || value.options.length > 5) return null;
  const options: Dish[] = [];
  for (const candidate of value.options) {
    if (!object(candidate) || !strings(candidate.ingredients, 24) || !strings(candidate.proteinSources, 10)) continue;
    const ingredients = candidate.ingredients;
    const normalized = { ...candidate, proteinSources: candidate.proteinSources.map((source) =>
      ingredients.find((ingredient) => [...words(source)].every((word) => words(ingredient).has(word))) ?? source) };
    const proposed = { status: "ok", options: [...options, normalized] };
    if (!validateGeneration(proposed, request)) options.push(normalized as Dish);
    if (options.length === request.maxOptions) break;
  }
  return options.length ? { status: "ok", options } : null;
}
