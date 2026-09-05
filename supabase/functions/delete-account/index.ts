import { createClient } from "jsr:@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json" };

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...jsonHeaders, Allow: "POST" },
    });
  }

  const authorization = request.headers.get("Authorization");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!authorization || !supabaseURL || !anonKey || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  // Resolve the caller from the signed user token. Never accept a user id from
  // the request body, so one account cannot request deletion of another.
  const userClient = createClient(supabaseURL, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // Remove child rows before their sessions because session_sets has no user_id.
  const { data: sessions, error: sessionLookupError } = await admin
    .from("sessions")
    .select("id")
    .eq("user_id", user.id);
  if (sessionLookupError) return serverError(sessionLookupError);

  const sessionIDs = (sessions ?? []).map((session) => session.id);
  if (sessionIDs.length > 0) {
    const { error } = await admin.from("session_sets").delete().in("session_id", sessionIDs);
    if (error) return serverError(error);
  }

  for (const table of ["sessions", "personal_records", "routines"]) {
    const { error } = await admin.from(table).delete().eq("user_id", user.id);
    if (error) return serverError(error);
  }

  const { error: deleteUserError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteUserError) return serverError(deleteUserError);

  return new Response(null, { status: 204 });
});

function serverError(error: { message: string }): Response {
  console.error("Account deletion failed:", error.message);
  return new Response(JSON.stringify({ error: "Account deletion failed" }), {
    status: 500,
    headers: jsonHeaders,
  });
}
