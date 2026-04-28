/**
 * Public: sign in with staff username + password (no JWT on this function).
 * Deploy with verify_jwt = false in Supabase Dashboard (or config.toml).
 *
 * Resolves auth email via profiles.username, then performs password grant.
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type Body = { username?: string; password?: string };

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

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (supabaseUrl == null || anonKey == null || serviceRoleKey == null) {
    return new Response("server_env_missing", {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const body = (await req.json()) as Body;
  const password = body.password ?? "";
  const normalized = normalizeUsername(body.username ?? "");
  if (normalized.length < 3 || password.length == 0) {
    return new Response("invalid_credentials", {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: rows, error: qErr } = await adminClient
    .from("profiles")
    .select("id")
    .eq("username", normalized)
    .eq("is_active", true);

  if (qErr != null) {
    return new Response(qErr.message, {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const list = (rows ?? []) as { id: string }[];
  if (list.length === 0) {
    return new Response("invalid_credentials", {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
  if (list.length > 1) {
    return new Response("ambiguous_username", {
      status: 409,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const userId = list[0]!.id;
  const { data: authUser, error: guErr } = await adminClient.auth.admin.getUserById(
    userId,
  );
  if (guErr != null || authUser.user?.email == null) {
    return new Response("invalid_credentials", {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
  const email = authUser.user.email;

  const tokenRes = await fetch(
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey,
        Authorization: `Bearer ${anonKey}`,
      },
      body: JSON.stringify({ email, password }),
    },
  );

  const tokenJson = await tokenRes.json() as Record<string, unknown>;
  if (!tokenRes.ok) {
    const msg = typeof tokenJson["error_description"] === "string"
      ? tokenJson["error_description"] as string
      : "invalid_credentials";
    return new Response(msg, {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  return Response.json(
    {
      access_token: tokenJson["access_token"],
      refresh_token: tokenJson["refresh_token"],
      expires_in: tokenJson["expires_in"],
      token_type: tokenJson["token_type"],
    },
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
