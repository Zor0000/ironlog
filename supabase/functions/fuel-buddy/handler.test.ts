import { test } from "node:test";
import assert from "node:assert/strict";
import { createHandler } from "./handler.ts";
import { constraints, validateGeneration, type GenerationRequest } from "./contract.ts";

const valid: GenerationRequest = {
  schemaVersion: 2, policyVersion: "2026-09", requestID: "12345678-1234-1234-1234-123456789abc",
  userText: "Protein rich breakfast", maxOptions: 5,
  preferences: { dietaryIdentity: "Vegetarian", excludedIngredients: ["peanut"], dislikes: [], preferredCuisines: ["Indian"], availableFoods: [], budget: "Value", maxCookingMinutes: 30, cookingAbility: "Basic cooking" },
};
const dish = { name: "Moong dal and paneer cheela", mealType: "breakfast", cuisine: "Indian", prepMinutes: 20, ingredients: ["moong lentil flour", "paneer", "tomato", "oil"], proteinSources: ["paneer", "moong lentil flour"], dietaryTags: ["vegetarian"], cookingAbility: "Basic cooking", budget: "Value" };
const generated = { status: "ok", options: [dish] };
function setup(options: { auth?: number; provider?: number; outputs?: unknown[]; key?: boolean; anonymous?: boolean } = {}) {
  const calls: { url: string; body?: any; headers?: Record<string, string> }[] = [];
  let generatedCount = 0;
  const handler = createHandler({
    env: (name) => ({ SUPABASE_URL: "https://test.supabase.co", SUPABASE_ANON_KEY: "public-key", GROQ_API_KEY: options.key === false ? undefined : "server-only-test-key" } as Record<string,string|undefined>)[name],
    fetch: (async (url: string | URL | Request, init?: RequestInit) => {
      calls.push({ url: String(url), body: init?.body ? JSON.parse(String(init.body)) : undefined, headers: init?.headers as Record<string, string> });
      if (String(url).endsWith("/auth/v1/user")) return Response.json({ id: "user-1", is_anonymous: options.anonymous ?? false }, { status: options.auth ?? 200 });
      const outputs = options.outputs ?? [generated];
      const output = outputs[Math.min(generatedCount++, outputs.length-1)];
      return Response.json({ choices: [{ message: { content: JSON.stringify(output) } }] }, { status: options.provider ?? 200 });
    }) as typeof fetch,
  });
  const request = (body: unknown = valid, headers: Record<string,string> = { Authorization: "Bearer user-token" }) => new Request("https://test/fuel-buddy", { method: "POST", headers, body: JSON.stringify(body) });
  return { handler, calls, request };
}

test("generates an uncatalogued dish using strict JSON schema and food preferences", async () => {
  const { handler, calls, request } = setup();
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { schemaVersion: 2, requestID: valid.requestID, ...generated });
  const upstream = calls[1];
  assert.equal(upstream.url, "https://api.groq.com/openai/v1/chat/completions");
  assert.equal(upstream.headers?.Authorization, "Bearer server-only-test-key");
  assert.equal(upstream.body.response_format.type, "json_schema");
  assert.equal(upstream.body.response_format.json_schema.strict, true);
  assert.ok(upstream.body.messages[1].content.includes('"excludedIngredients":["peanut"]'));
  assert.ok(!JSON.stringify(upstream.body).includes("user-token"));
  assert.ok(!JSON.stringify(upstream.body).includes("candidates"));
});

test("authenticated guests can generate meals without a permanent account", async () => {
  const { handler, request } = setup({ anonymous: true });
  assert.equal((await handler(request())).status, 200);
});

test("public key alone or invalid user sessions cannot call Groq", async () => {
  const missing = setup();
  assert.equal((await missing.handler(missing.request(valid, {}))).status, 401);
  assert.equal(missing.calls.length, 0);
  const invalid = setup({ auth: 401 });
  assert.equal((await invalid.handler(invalid.request())).status, 401);
  assert.equal(invalid.calls.length, 1);
});

test("rejects old contract, private fields and unredacted identifiers", async () => {
  for (const body of [null, { ...valid, schemaVersion: 1 }, { ...valid, maxOptions: 6 }, { ...valid, userText: "person@example.com" }, { ...valid, weight: 75 }]) {
    const { handler, calls, request } = setup();
    assert.equal((await handler(request(body))).status, 400);
    assert.equal(calls.length, 1);
  }
});

test("enforces one to five, specific unique names and real protein sources", () => {
  assert.equal(validateGeneration(generated, valid), null);
  for (const invalid of [
    { status: "ok", options: [] }, { status: "ok", options: Array(6).fill(dish) },
    { status: "ok", options: [dish, dish] }, { status: "ok", options: [{ ...dish, name: "Healthy bowl" }] },
    { status: "ok", options: [{ ...dish, proteinSources: [] }] },
    { status: "ok", options: [{ ...dish, proteinSources: ["chicken"] }] },
  ]) assert.notEqual(validateGeneration(invalid, valid), null);
});

test("rejects wrong meal, cuisine, time, ingredient substitutions and Passport violations", () => {
  assert.equal(validateGeneration({status:"ok",options:[{...dish,mealType:"dinner"}]}, valid), "wrong_meal");
  assert.equal(validateGeneration({status:"ok",options:[{...dish,ingredients:[...dish.ingredients,"peanut oil"]}]}, valid), "excluded_ingredient");
  assert.equal(validateGeneration({status:"ok",options:[{...dish,ingredients:[...dish.ingredients,"chicken"]}]}, valid), "nonvegetarian_ingredient");
  const dinner = {...valid,userText:"Quick Indian dinner"};
  assert.equal(validateGeneration({status:"ok",options:[{...dish,mealType:"dinner",prepMinutes:25}]}, dinner), "invalid_metadata_or_time");
  assert.equal(validateGeneration({status:"ok",options:[{...dish,mealType:"dinner",cuisine:"Italian"}]}, dinner), "wrong_cuisine");
  const eggRice = {...valid,userText:"Quick egg rice",preferences:{...valid.preferences,dietaryIdentity:"No dietary identity"}};
  assert.equal(validateGeneration(generated,eggRice), "missing_requested_ingredient");
});

test("query exclusions are added and never relax Passport exclusions", () => {
  const resolved=constraints({...valid,userText:"breakfast without milk or eggs"});
  assert.ok(resolved.excluded.includes("peanut"));
  assert.ok(resolved.excluded.includes("milk"));
  assert.ok(resolved.excluded.includes("egg"));
  assert.ok(!resolved.required.includes("egg"));
});

test("corrects a bad model response once, then fails without catalog fallback", async () => {
  const wrong={status:"ok",options:[{...dish,mealType:"dinner"}]};
  const retry=setup({outputs:[wrong,generated]});
  assert.equal((await retry.handler(retry.request())).status,200);
  assert.equal(retry.calls.length,3);
  const failed=setup({outputs:[wrong]});
  const response=await failed.handler(failed.request());
  assert.equal(response.status,502);
  assert.equal(failed.calls.length,3);
  assert.deepEqual(await response.json(),{error:"invalid_provider_response"});
});

test("returns explicit provider and rate limit failures", async () => {
  for(const [options,expected] of [[{key:false},503],[{provider:429},429],[{provider:401},502]] as const){
    const {handler,request}=setup(options);
    assert.equal((await handler(request())).status,expected);
  }
});

test("keeps valid generated dishes and canonicalizes protein ingredient names", async () => {
  const validTofu={...dish,name:"Tofu and tomato scramble",ingredients:["firm tofu","tomato","oil"],proteinSources:["tofu"]};
  const bad={...dish,name:"Peanut breakfast",ingredients:["peanut"]};
  const {handler,request,calls}=setup({outputs:[{status:"ok",options:[bad,validTofu,validTofu]}]});
  const response=await handler(request());
  assert.equal(response.status,200);
  const result=await response.json();
  assert.equal(result.options.length,1);
  assert.equal(result.options[0].name,validTofu.name);
  assert.deepEqual(result.options[0].proteinSources,["firm tofu"]);
  assert.equal(calls.length,2);
});
