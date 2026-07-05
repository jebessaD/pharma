/**
 * Rate-limited phone OTP entry point (per phone + per IP).
 * Clients should call this instead of auth.signInWithOtp directly.
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  clientIpFromRequest,
  hashClientIp,
  phoneToMsisdn,
  rateLimitConfigFromEnv,
  rateLimitUserMessage,
} from "../_shared/sms_rate_limits.ts";

type RequestBody = {
  phone?: string;
  data?: Record<string, unknown>;
  action?: "send" | "resend";
  should_create_user?: boolean;
};

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "server_env_missing" }, 500);
  }

  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const phone = body.phone?.trim() ?? "";
  const msisdn = phoneToMsisdn(phone);
  if (!msisdn.startsWith("251") || msisdn.length !== 12) {
    return json({ error: "invalid_phone", message: rateLimitUserMessage("invalid_msisdn") }, 400);
  }

  const e164 = phone.startsWith("+") ? phone : `+${msisdn}`;
  const action = body.action === "resend" ? "resend" : "send";
  const limits = rateLimitConfigFromEnv();
  const ip = clientIpFromRequest(req);
  const ipHash = await hashClientIp(ip);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: limitResult, error: limitError } = await admin.rpc(
    "assert_sms_otp_rate_limit",
    {
      p_msisdn: msisdn,
      p_ip_hash: ipHash,
      p_record: false,
      p_max_per_phone_day: limits.maxPerPhoneDay,
      p_max_per_ip_day: limits.maxPerIpDay,
      p_max_per_phone_hour: limits.maxPerPhoneHour,
    },
  );

  if (limitError) {
    console.error(JSON.stringify({ fn: "request-phone-otp", step: "rate_limit_rpc_error", detail: limitError.message }));
    return json({ error: "rate_limit_check_failed", message: "Could not verify SMS rate limits. Try again." }, 500);
  }

  const allowed = (limitResult as { allowed?: boolean })?.allowed === true;
  const reason = String((limitResult as { reason?: string })?.reason ?? "rate_limited");
  if (!allowed) {
    return json(
      {
        error: reason,
        message: rateLimitUserMessage(reason),
        retry_after_seconds: (limitResult as { retry_after_seconds?: number })?.retry_after_seconds ?? 3600,
      },
      429,
    );
  }

  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  async function recordSend() {
    await admin.rpc("assert_sms_otp_rate_limit", {
      p_msisdn: msisdn,
      p_ip_hash: ipHash,
      p_record: true,
      p_max_per_phone_day: limits.maxPerPhoneDay,
      p_max_per_ip_day: limits.maxPerIpDay,
      p_max_per_phone_hour: limits.maxPerPhoneHour,
    });
  }

  function authErrorResponse(error: { message?: string; code?: string | number; status?: number }) {
    const raw = (error.message ?? "").trim();
    const message = raw === "{}" || raw === ""
      ? "Could not send the verification SMS. The SMS service may be unavailable for this number."
      : raw;
    return json(
      {
        error: error.code ?? "otp_send_failed",
        message,
        code: error.code,
      },
      typeof error.status === "number" ? error.status : 400,
    );
  }

  function isSmsDeliveryFailure(error: { message?: string; code?: string | number; status?: number }) {
    const raw = (error.message ?? "").toLowerCase();
    const code = String(error.code ?? "").toLowerCase();
    return (
      code === "unexpected_failure" ||
      raw.includes("hook") ||
      raw.includes("unexpected_failure") ||
      raw.includes("502") ||
      (error.status === 500 && (raw === "{}" || raw === ""))
    );
  }

  if (action === "resend") {
    const { error } = await authClient.auth.resend({ type: "sms", phone: e164 });
    if (error) {
      if (isSmsDeliveryFailure(error)) {
        return json({
          error: "sms_hook_failed",
          message:
            "Could not deliver SMS to this number. On SMSEthiopia trial accounts, each phone must be whitelisted in their dashboard first.",
          code: error.code,
        }, 502);
      }
      return authErrorResponse(error);
    }
    await recordSend();
    return json({ ok: true, action: "resend" }, 200);
  }

  const { error } = await authClient.auth.signInWithOtp({
    phone: e164,
    options: {
      data: body.data ?? {},
      shouldCreateUser: body.should_create_user !== false,
    },
  });
  if (error) {
    if (isSmsDeliveryFailure(error)) {
      return json({
        error: "sms_hook_failed",
        message:
          "Could not deliver SMS to this number. On SMSEthiopia trial accounts, each phone must be whitelisted in their dashboard first.",
        code: error.code,
      }, 502);
    }
    return authErrorResponse(error);
  }

  await recordSend();
  return json({ ok: true, action: "send" }, 200);
});
