/**
 * JWT required. Returns whether a staff username is free globally (profiles.username).
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type Body = { username?: string };

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function normalizeUsername(raw: string): string {
  return raw.trim().toLowerCase().replace(/[^a-z0-9_]/g, "");
}

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
  if (callerProfile == null ||
    (callerProfile.role != "admin" && callerProfile.role != "owner") ||
    callerProfile.is_active != true) {
    return new Response("forbidden", {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const body = (await req.json()) as Body;
  const normalized = normalizeUsername(body.username ?? "");
  if (normalized.length < 3 || normalized.length > 32) {
    return Response.json(
      { available: false },
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
  if (!/^[a-z0-9_]+$/.test(normalized)) {
    return Response.json(
      { available: false },
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: row, error: qErr } = await adminClient
    .from("profiles")
    .select("id")
    .eq("username", normalized)
    .maybeSingle();

  if (qErr != null) {
    return new Response(qErr.message, {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  return Response.json(
    { available: row == null },
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
