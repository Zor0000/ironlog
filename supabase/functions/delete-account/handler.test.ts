import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createLocalJWKSet,
  exportJWK,
  exportPKCS8,
  generateKeyPair,
  jwtVerify,
  SignJWT,
} from "npm:jose@6.1.0";
import { createHandler } from "./handler.ts";
import { createAppleRevoker } from "./apple.ts";

const credentials = {
  APPLE_CLIENT_ID: "com.parthjadhav.ironlog",
  APPLE_TEAM_ID: "75LRT8TRQY",
  APPLE_KEY_ID: "test-key",
  APPLE_PRIVATE_KEY: "test-private-key",
};
const appleUser = {
  id: "authenticated-user",
  identities: [{
    provider: "apple",
    identity_data: { sub: "linked-apple-user" },
  }],
};

function harness(
  options: {
    configured?: boolean;
    user?: typeof appleUser | null;
    failRevocation?: boolean;
    failDeletion?: boolean;
  } = {},
) {
  const events: string[] = [];
  const handler = createHandler({
    env: (name) =>
      options.configured === false
        ? undefined
        : credentials[name as keyof typeof credentials],
    authenticate: () =>
      Promise.resolve(options.user === undefined ? appleUser : options.user),
    revokeApple: (code, subjects) => {
      assertEquals(code, "fresh-code");
      assertEquals(subjects, ["linked-apple-user"]);
      events.push("revoke");
      if (options.failRevocation) {
        return Promise.reject(new Error("sensitive-token-must-not-leak"));
      }
      return Promise.resolve();
    },
    deleteUser: (id) => {
      assertEquals(id, "authenticated-user");
      events.push("delete");
      if (options.failDeletion) {
        return Promise.reject(new Error("database-error"));
      }
      return Promise.resolve();
    },
  });
  const request = (
    body: unknown = {},
    headers = { Authorization: "Bearer user-token" },
  ) =>
    handler(
      new Request("https://example.com/delete-account", {
        method: "POST",
        headers,
        body: JSON.stringify(body),
      }),
    );
  return { handler, request, events };
}

Deno.test("rejects missing or invalid authentication before deletion", async () => {
  const missing = harness();
  assertEquals(
    (await missing.request({}, {} as { Authorization: string })).status,
    401,
  );
  assertEquals(missing.events, []);
  const invalid = harness({ user: null });
  assertEquals((await invalid.request()).status, 401);
  assertEquals(invalid.events, []);
});

Deno.test("rejects unsupported methods and malformed bodies", async () => {
  const h = harness();
  assertEquals(
    (await h.handler(new Request("https://example.com"))).status,
    405,
  );
  for (const raw of ["null", "[]", "invalid-json"]) {
    const response = await h.handler(
      new Request("https://example.com", {
        method: "POST",
        headers: { Authorization: "Bearer user-token" },
        body: raw,
      }),
    );
    assertEquals(response.status, 400);
  }
  assertEquals((await h.request({ value: "x".repeat(9000) })).status, 413);
  assertEquals(h.events, []);
});

Deno.test("requires fresh Apple authorization and ignores supplied target IDs", async () => {
  const h = harness();
  const response = await h.request({ user_id: "victim" });
  assertEquals(response.status, 409);
  assertEquals(
    (await response.json()).error_code,
    "apple_reauthorization_required",
  );
  assertEquals(h.events, []);
  assertEquals(
    (await h.request({
      apple_authorization_code: "fresh-code",
      user_id: "victim",
    })).status,
    204,
  );
  assertEquals(h.events, ["revoke", "delete"]);
});

Deno.test("missing credentials need explicit boolean manual-revocation acknowledgement", async () => {
  const h = harness({ configured: false });
  for (const value of [undefined, false, "true", 1]) {
    const response = await h.request({ manual_apple_revocation: value });
    assertEquals(response.status, 409);
    assertEquals(
      (await response.json()).error_code,
      "apple_revocation_unavailable",
    );
  }
  assertEquals(h.events, []);
  assertEquals(
    (await h.request({ manual_apple_revocation: true })).status,
    200,
  );
  assertEquals(h.events, ["delete"]);
});

Deno.test("manual flag cannot bypass configured Apple revocation or a provider failure", async () => {
  const h = harness({ failRevocation: true });
  assertEquals(
    (await h.request({ manual_apple_revocation: true })).status,
    409,
  );
  const response = await h.request({
    apple_authorization_code: "fresh-code",
    manual_apple_revocation: true,
  });
  assertEquals(response.status, 502);
  assertEquals((await response.text()).includes("sensitive-token"), false);
  assertEquals(h.events, ["revoke"]);
});

Deno.test("email and guest accounts delete without Apple credentials", async () => {
  const h = harness({
    configured: false,
    user: { id: "authenticated-user", identities: [] },
  });
  assertEquals((await h.request()).status, 204);
  assertEquals(h.events, ["delete"]);
});

Deno.test("malformed Apple identities fail closed", async () => {
  const h = harness({
    user: {
      id: "authenticated-user",
      identities: [{ provider: "apple", identity_data: {} as { sub: string } }],
    },
  });
  assertEquals(
    (await h.request({ manual_apple_revocation: true })).status,
    409,
  );
  assertEquals(h.events, []);
});

Deno.test("database failure never reports successful account deletion", async () => {
  const h = harness({ failDeletion: true });
  assertEquals(
    (await h.request({ apple_authorization_code: "fresh-code" })).status,
    500,
  );
  assertEquals(h.events, ["revoke", "delete"]);
});

async function appleHarness(
  options: {
    subject?: string;
    audience?: string;
    issuer?: string;
    expired?: boolean;
    exchangeStatus?: number;
    revokeStatus?: number;
    accessOnly?: boolean;
    missingToken?: boolean;
  } = {},
) {
  const signing = await generateKeyPair("ES256", { extractable: true });
  const apple = await generateKeyPair("RS256");
  const jwk = await exportJWK(apple.publicKey);
  jwk.kid = "apple-test";
  const idToken = await new SignJWT({})
    .setProtectedHeader({ alg: "RS256", kid: "apple-test" })
    .setIssuer(options.issuer ?? "https://appleid.apple.com")
    .setAudience(options.audience ?? credentials.APPLE_CLIENT_ID)
    .setSubject(options.subject ?? "linked-apple-user")
    .setIssuedAt().setExpirationTime(options.expired ? "-1h" : "5m").sign(
      apple.privateKey,
    );
  const events: string[] = [];
  const revoker = createAppleRevoker(async (url, init) => {
    const form = init!.body as URLSearchParams;
    assertEquals(form.get("client_id"), credentials.APPLE_CLIENT_ID);
    await jwtVerify(form.get("client_secret")!, signing.publicKey, {
      algorithms: ["ES256"],
      issuer: credentials.APPLE_TEAM_ID,
      audience: "https://appleid.apple.com",
      subject: credentials.APPLE_CLIENT_ID,
    });
    if (url === "https://appleid.apple.com/auth/token") {
      events.push("exchange");
      assertEquals(form.get("code"), "fresh-code");
      assertEquals(form.get("grant_type"), "authorization_code");
      return Response.json({
        id_token: idToken,
        ...(options.missingToken
          ? {}
          : options.accessOnly
          ? { access_token: "apple-access" }
          : { refresh_token: "apple-refresh" }),
      }, { status: options.exchangeStatus ?? 200 });
    }
    assertEquals(url, "https://appleid.apple.com/auth/revoke");
    events.push("revoke");
    assertEquals(
      form.get("token"),
      options.accessOnly ? "apple-access" : "apple-refresh",
    );
    assertEquals(
      form.get("token_type_hint"),
      options.accessOnly ? "access_token" : "refresh_token",
    );
    return new Response(null, { status: options.revokeStatus ?? 200 });
  }, createLocalJWKSet({ keys: [jwk] }));
  return {
    events,
    revoke: async () =>
      revoker("fresh-code", ["linked-apple-user"], {
        clientID: credentials.APPLE_CLIENT_ID,
        teamID: credentials.APPLE_TEAM_ID,
        keyID: credentials.APPLE_KEY_ID,
        privateKey: await exportPKCS8(signing.privateKey),
      }),
  };
}

Deno.test("Apple exchange verifies signed identity and revokes the refresh token", async () => {
  const h = await appleHarness();
  await h.revoke();
  assertEquals(h.events, ["exchange", "revoke"]);
});

Deno.test("Apple exchange can revoke an access token when no refresh token is supplied", async () => {
  const h = await appleHarness({ accessOnly: true });
  await h.revoke();
  assertEquals(h.events, ["exchange", "revoke"]);
});

Deno.test("mismatched Apple subject, audience, issuer and expiry never reach revocation", async () => {
  for (
    const options of [
      { subject: "another-user" },
      { audience: "another-app" },
      { issuer: "https://attacker.example" },
      { expired: true },
    ]
  ) {
    const h = await appleHarness(options);
    await assertRejects(h.revoke);
    assertEquals(h.events, ["exchange"]);
  }
});

Deno.test("Apple exchange, missing-token and revocation failures are surfaced", async () => {
  for (
    const options of [{ exchangeStatus: 400 }, { missingToken: true }, {
      revokeStatus: 500,
    }]
  ) {
    const h = await appleHarness(options);
    await assertRejects(h.revoke);
    assertEquals(
      h.events,
      options.revokeStatus ? ["exchange", "revoke"] : ["exchange"],
    );
  }
});
