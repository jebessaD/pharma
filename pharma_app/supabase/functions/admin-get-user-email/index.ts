/**
 * Team admin: returns auth.users email for a staff member on the same team.
 * JWT required (verify_jwt = true).
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type Body = { user_id?: string };

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  if (req.method != "POST") {
    return new Response("method_not_allowed", {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
  if (jwt.length == 0) {
    return new Response("unauthorized", {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (supabaseUrl == null || anonKey == null || serviceRoleKey == null) {
    return new Response("server_env_missing", {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

  const { data: userData } = await callerClient.auth.getUser();
  const callerUser = userData.user;
  if (callerUser == null) {
    return new Response("unauthorized", {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const { data: callerProfile, error: callerProfileError } = await callerClient
    .from("profiles")
    .select("team_id, role, is_active")
    .eq("id", callerUser.id)
    .maybeSingle();
  if (callerProfileError != null) {
    return new Response(callerProfileError.message, {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
  if (
    callerProfile == null || callerProfile.role != "admin" ||
    callerProfile.is_active != true
  ) {
    return new Response("forbidden", {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const body = (await req.json()) as Body;
  const targetId = body.user_id?.trim();
  if (targetId == null || targetId.length == 0) {
    return new Response("missing_user_id", {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const { data: targetProfile, error: targetErr } = await callerClient
    .from("profiles")
    .select("team_id")
    .eq("id", targetId)
    .maybeSingle();
  if (targetErr != null || targetProfile == null) {
    return new Response("user_not_found", {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
  if (targetProfile.team_id != callerProfile.team_id) {
    return new Response("forbidden", {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: authUser, error: guErr } = await adminClient.auth.admin.getUserById(
    targetId,
  );
  if (guErr != null || authUser.user?.email == null) {
    return new Response("user_not_found", {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  return Response.json(
    { email: authUser.user.email },
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
