import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type DeleteUserBody = {
  user_id?: string;
};

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
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: callerUserData } = await callerClient.auth.getUser();
  const callerUser = callerUserData.user;
  if (callerUser == null) {
    return new Response("unauthorized", {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const body = (await req.json()) as DeleteUserBody;
  const targetUserId = (body.user_id ?? "").trim();
  if (targetUserId.length == 0) {
    return new Response("missing_user_id", {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
  if (targetUserId == callerUser.id) {
    return new Response("cannot_delete_self", {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const { data: callerProfile, error: callerErr } = await adminClient
    .from("profiles")
    .select("team_id, role, is_active")
    .eq("id", callerUser.id)
    .maybeSingle();
  if (callerErr != null) {
    return new Response(callerErr.message, {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
  if (callerProfile == null || callerProfile.role != "owner" || callerProfile.is_active != true) {
    return new Response("forbidden", {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const teamId = callerProfile.team_id as string;
  const { data: targetProfile, error: targetErr } = await adminClient
    .from("profiles")
    .select("id, role")
    .eq("id", targetUserId)
    .eq("team_id", teamId)
    .maybeSingle();
  if (targetErr != null) {
    return new Response(targetErr.message, {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
  if (targetProfile == null) {
    return new Response("user_not_in_team", {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
  if (targetProfile.role === "owner") {
    return new Response("cannot_delete_owner", {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const nullifyRefs = async (table: string, column: string) => {
    const { error } = await adminClient
      .from(table)
      .update({ [column]: null })
      .eq("team_id", teamId)
      .eq(column, targetUserId);
    return error;
  };

  const refUpdates = await Promise.all([
    nullifyRefs("sales", "sold_by"),
    nullifyRefs("purchases", "created_by"),
    nullifyRefs("stock_movements", "created_by"),
    nullifyRefs("activity_logs", "user_id"),
  ]);
  const { error: teamRefError } = await adminClient
    .from("teams")
    .update({ created_by: null })
    .eq("id", teamId)
    .eq("created_by", targetUserId);
  const refError = refUpdates.find((e) => e != null);
  if (refError != null || teamRefError != null) {
    const err = refError ?? teamRefError!;
    return new Response(err.message, {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const { error: delErr } = await adminClient.auth.admin.deleteUser(targetUserId);
  if (delErr != null) {
    return new Response(delErr.message, {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  return Response.json(
    { ok: true, id: targetUserId },
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
