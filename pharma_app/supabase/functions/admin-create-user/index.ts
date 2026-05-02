import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

/** Must match Flutter `kStaffAuthEmailDomain` */
const STAFF_EMAIL_DOMAIN = "staff.internal";

type CreateUserBody = {
  username?: string;
  /** @deprecated use username */
  email?: string;
  password?: string;
  full_name?: string;
  role?: string;
  branch_id?: string | null;
};

const ownerAllowedRoles = new Set([
  "admin",
  "pharmacist",
  "cashier",
  "seller",
]);
const adminAllowedRoles = new Set(["pharmacist", "cashier", "seller"]);

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function normalizeUsername(raw: string): string {
  return raw.trim().toLowerCase().replace(/[^a-z0-9_]/g, "");
}

function staffLoginEmail(username: string): string {
  return `${username}@${STAFF_EMAIL_DOMAIN}`;
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

  const teamId = callerProfile.team_id as string;
  const callerRole = callerProfile.role as string;

  const body = (await req.json()) as CreateUserBody;
  const password = body.password;
  const fullName = body.full_name?.trim();
  const role = body.role?.trim();
  const branchId = body.branch_id ?? null;

  const usernameRaw = body.username?.trim();
  const legacyEmail = body.email?.trim().toLowerCase();

  let email: string;
  let username: string | null;

  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  if (usernameRaw != null && usernameRaw.length > 0) {
    const normalized = normalizeUsername(usernameRaw);
    if (normalized.length < 3 || normalized.length > 32) {
      return new Response("invalid_username", {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "text/plain" },
      });
    }
    if (!/^[a-z0-9_]+$/.test(normalized)) {
      return new Response("invalid_username", {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "text/plain" },
      });
    }
    username = normalized;

    email = staffLoginEmail(normalized);

    const { data: dup, error: dupErr } = await adminClient
      .from("profiles")
      .select("id")
      .eq("username", normalized)
      .maybeSingle();
    if (dupErr != null) {
      return new Response(dupErr.message, {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "text/plain" },
      });
    }
    if (dup != null) {
      return new Response("username_taken", {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "text/plain" },
      });
    }
  } else if (legacyEmail != null && legacyEmail.length > 0) {
    email = legacyEmail;
    username = null;
  } else {
    return new Response("missing_username", {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  if (password == null || fullName == null || role == null) {
    return new Response("missing_fields", {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
  if (password.length == 0 || fullName.length == 0) {
    return new Response("invalid_fields", {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
  const allowedRoles = callerRole == "owner" ? ownerAllowedRoles : adminAllowedRoles;
  if (!allowedRoles.has(role)) {
    return new Response("bad_role", {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const { data: createdUserData, error: createUserError } = await adminClient
    .auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
  if (createUserError != null || createdUserData.user == null) {
    return new Response(createUserError?.message ?? "create_user_failed", {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const createdUserId = createdUserData.user.id;
  const { error: profileInsertError } = await adminClient.from("profiles")
    .insert({
      id: createdUserId,
      team_id: teamId,
      full_name: fullName,
      role,
      branch_id: branchId,
      is_active: true,
      username,
    });
  if (profileInsertError != null) {
    await adminClient.auth.admin.deleteUser(createdUserId);
    return new Response(profileInsertError.message, {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  return Response.json(
    { id: createdUserId, login_email: email, username },
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
