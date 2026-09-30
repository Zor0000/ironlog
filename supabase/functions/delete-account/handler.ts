export type AppleCredentials = {
  clientID: string;
  teamID: string;
  keyID: string;
  privateKey: string;
};

type User = {
  id: string;
  identities?: { provider: string; identity_data?: Record<string, unknown> }[];
};

type Dependencies = {
  env: (name: string) => string | undefined;
  authenticate: (authorization: string) => Promise<User | null>;
  revokeApple: (
    code: string,
    subjects: string[],
    credentials: AppleCredentials,
  ) => Promise<void>;
  deleteUser: (id: string) => Promise<void>;
};

const error = (code: string, message: string, status: number) =>
  Response.json({ error_code: code, message }, { status });

export function createHandler(deps: Dependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return new Response(null, { status: 405, headers: { Allow: "POST" } });
    }
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return error("unauthorized", "Unauthorized", 401);
    }
    try {
      const user = await deps.authenticate(authorization);
      if (!user) return error("unauthorized", "Unauthorized", 401);
      const raw = await request.text();
      if (new TextEncoder().encode(raw).length > 8192) {
        return error("invalid_request", "Request too large", 413);
      }
      let body;
      try {
        body = JSON.parse(raw);
      } catch {
        return error("invalid_request", "Invalid request", 400);
      }
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        return error("invalid_request", "Invalid request", 400);
      }

      let manual = false;
      const appleIdentities = user.identities?.filter((identity) =>
        identity.provider === "apple"
      ) ?? [];
      if (appleIdentities.length) {
        const subjects = appleIdentities.map((identity) =>
          identity.identity_data?.sub
        )
          .filter((sub): sub is string =>
            typeof sub === "string" && sub.length > 0
          );
        if (!subjects.length) {
          return error(
            "apple_identity_missing",
            "Sign in again before deleting your account.",
            409,
          );
        }
        const clientID = deps.env("APPLE_CLIENT_ID");
        const teamID = deps.env("APPLE_TEAM_ID");
        const keyID = deps.env("APPLE_KEY_ID");
        const privateKey = deps.env("APPLE_PRIVATE_KEY");
        if (!clientID || !teamID || !keyID || !privateKey) {
          // Only an explicit user choice may bypass missing credentials. Never
          // bypass a mismatched identity, failed exchange, or failed revocation.
          if (body.manual_apple_revocation !== true) {
            return error(
              "apple_revocation_unavailable",
              "Automatic Apple revocation is unavailable. You can delete your account and remove Setzo from Sign in with Apple in Settings.",
              409,
            );
          }
          manual = true;
          console.info("Manual Apple revocation selected");
        } else {
          if (
            typeof body.apple_authorization_code !== "string" ||
            !body.apple_authorization_code.trim()
          ) {
            return error(
              "apple_reauthorization_required",
              "Confirm with Apple to delete your account.",
              409,
            );
          }
          try {
            await deps.revokeApple(body.apple_authorization_code, subjects, {
              clientID,
              teamID,
              keyID,
              privateKey,
            });
          } catch {
            return error(
              "apple_revocation_failed",
              "Apple confirmation failed. Use the Apple account linked to Setzo and try again.",
              502,
            );
          }
          console.info("Apple authorization revoked");
        }
      }
      // The ID comes exclusively from Auth, never from the request body.
      await deps.deleteUser(user.id);
      return manual
        ? Response.json({ manual_apple_revocation_required: true })
        : new Response(null, { status: 204 });
    } catch {
      console.error("Account deletion failed");
      return error(
        "account_deletion_failed",
        "Account deletion failed. Please try again.",
        500,
      );
    }
  };
}
