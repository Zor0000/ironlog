import { createClient } from "jsr:@supabase/supabase-js@2";
import { createHandler } from "./handler.ts";
import { revokeAppleAuthorization } from "./apple.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

Deno.serve(createHandler({
  env: (name) => Deno.env.get(name),
  authenticate: async (authorization) => {
    const client = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: { user }, error } = await client.auth.getUser();
    return error ? null : user;
  },
  revokeApple: revokeAppleAuthorization,
  deleteUser: async (id) => {
    // ON DELETE CASCADE removes all owned rows in the same transaction.
    const { error } = await admin.auth.admin.deleteUser(id);
    if (error) throw new Error("Account deletion failed");
  },
}));
