import {
  createRemoteJWKSet,
  importPKCS8,
  jwtVerify,
  SignJWT,
} from "npm:jose@6.1.0";
import type { JWTVerifyGetKey } from "npm:jose@6.1.0";
import type { AppleCredentials } from "./handler.ts";

const appleKeys = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
);

export function createAppleRevoker(
  fetcher: typeof fetch,
  keys: JWTVerifyGetKey,
) {
  return async (
    code: string,
    subjects: string[],
    credentials: AppleCredentials,
  ) => {
    const key = await importPKCS8(credentials.privateKey, "ES256");
    const clientSecret = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: credentials.keyID })
      .setIssuer(credentials.teamID)
      .setSubject(credentials.clientID)
      .setAudience("https://appleid.apple.com")
      .setIssuedAt()
      .setExpirationTime("5m")
      .sign(key);
    const tokenResponse = await fetcher(
      "https://appleid.apple.com/auth/token",
      {
        method: "POST",
        body: new URLSearchParams({
          client_id: credentials.clientID,
          client_secret: clientSecret,
          grant_type: "authorization_code",
          code,
        }),
        signal: AbortSignal.timeout(10_000),
        redirect: "error",
      },
    );
    if (!tokenResponse.ok) throw new Error("Apple token exchange failed");
    const tokens = await tokenResponse.json();
    if (typeof tokens.id_token !== "string") {
      throw new Error("Apple identity missing");
    }
    // Verify the Apple signature, issuer, audience, expiry and linked subject
    // before revoking access. A valid Supabase JWT cannot revoke another user.
    const { payload } = await jwtVerify(tokens.id_token, keys, {
      issuer: "https://appleid.apple.com",
      audience: credentials.clientID,
      algorithms: ["RS256"],
      requiredClaims: ["sub", "exp", "iat"],
    });
    if (!payload.sub || !subjects.includes(payload.sub)) {
      throw new Error("Apple identity mismatch");
    }
    const token = tokens.refresh_token ?? tokens.access_token;
    if (typeof token !== "string" || !token) {
      throw new Error("Apple revocation token missing");
    }
    const response = await fetcher("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      body: new URLSearchParams({
        client_id: credentials.clientID,
        client_secret: clientSecret,
        token,
        token_type_hint: tokens.refresh_token
          ? "refresh_token"
          : "access_token",
      }),
      signal: AbortSignal.timeout(10_000),
      redirect: "error",
    });
    if (!response.ok) throw new Error("Apple token revocation failed");
  };
}

export const revokeAppleAuthorization = createAppleRevoker(fetch, appleKeys);
