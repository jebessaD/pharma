/**
 * Supabase Auth Send SMS Hook — Ethiopia-first (SMSEthiopia direct Ethio Telecom).
 *
 * Secrets (Dashboard → Edge Functions → send-sms-hook):
 *   SEND_SMS_HOOK_SECRET  — Auth → Hooks → Send SMS only (v1,whsec_...)
 *   SMS_PROVIDER          — "smsethiopia" (default) | "textlocal"
 *   SMSETHIOPIA_API_KEY   — from https://smsethiopia.com Console → API Keys
 *   TEXTLOCAL_API_KEY     — optional fallback (India gateway)
 *   TEXTLOCAL_SENDER      — e.g. "Pharma Shelf"
 *
 * Health: GET /functions/v1/send-sms-hook (no auth) — config diagnostics only.
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { rateLimitConfigFromEnv } from "../_shared/sms_rate_limits.ts";

type SmsHookPayload = {
  user: { phone?: string };
  sms: { otp?: string };
};

type SmsProvider = "smsethiopia" | "textlocal";

type ConfigIssue = {
  code: string;
  message: string;
};

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, webhook-id, webhook-timestamp, webhook-signature",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const ETHIOPIAN_MOBILE_MSISDN = /^251(9[1-9]|7[0-9])\d{7}$/;

function log(step: string, data: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ hook: "send-sms-hook", step, ...data }));
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function maskPhone(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  if (digits.length < 4) return "***";
  return `${digits.slice(0, 4)}***${digits.slice(-2)}`;
}

function looksLikeHookSecret(value: string): boolean {
  return value.trim().startsWith("v1,whsec_");
}

function smsProvider(): SmsProvider {
  const configured = (Deno.env.get("SMS_PROVIDER") ?? "smsethiopia")
    .trim()
    .toLowerCase();
  return configured === "textlocal" ? "textlocal" : "smsethiopia";
}

function readSecret(name: string): string {
  return Deno.env.get(name)?.trim().replace(/^["']|["']$/g, "") ?? "";
}

function diagnoseConfig(): {
  ok: boolean;
  provider: SmsProvider;
  issues: ConfigIssue[];
} {
  const provider = smsProvider();
  const issues: ConfigIssue[] = [];

  const hookSecret = readSecret("SEND_SMS_HOOK_SECRET");
  const smsethiopiaKey = readSecret("SMSETHIOPIA_API_KEY");
  const textlocalKey = readSecret("TEXTLOCAL_API_KEY");

  if (!hookSecret) {
    issues.push({
      code: "hook_secret_missing",
      message:
        "Set SEND_SMS_HOOK_SECRET to the v1,whsec_... value from Auth → Hooks → Send SMS.",
    });
  } else if (!looksLikeHookSecret(hookSecret)) {
    issues.push({
      code: "hook_secret_wrong_format",
      message:
        "SEND_SMS_HOOK_SECRET must start with v1,whsec_. It is NOT your SMS provider API key.",
    });
  }

  if (provider === "smsethiopia") {
    if (!smsethiopiaKey || smsethiopiaKey === "UPDATE_ME") {
      issues.push({
        code: "smsethiopia_key_missing",
        message:
          "Set SMSETHIOPIA_API_KEY from https://smsethiopia.com Console → API Keys.",
      });
    } else if (looksLikeHookSecret(smsethiopiaKey)) {
      issues.push({
        code: "smsethiopia_key_is_hook_secret",
        message:
          "SMSETHIOPIA_API_KEY contains the hook secret. Paste your SMSEthiopia API key instead.",
      });
    }
  }

  if (provider === "textlocal") {
    if (!textlocalKey) {
      issues.push({
        code: "textlocal_key_missing",
        message: "Set TEXTLOCAL_API_KEY for Textlocal delivery.",
      });
    } else if (looksLikeHookSecret(textlocalKey)) {
      issues.push({
        code: "textlocal_key_is_hook_secret",
        message:
          "TEXTLOCAL_API_KEY contains the hook secret. Paste your Textlocal API key instead.",
      });
    }
  }

  if (
    hookSecret &&
    smsethiopiaKey &&
    hookSecret === smsethiopiaKey
  ) {
    issues.push({
      code: "hook_secret_equals_smsethiopia_key",
      message:
        "SEND_SMS_HOOK_SECRET and SMSETHIOPIA_API_KEY must be different values.",
    });
  }

  if (hookSecret && textlocalKey && hookSecret === textlocalKey) {
    issues.push({
      code: "hook_secret_equals_textlocal_key",
      message:
        "SEND_SMS_HOOK_SECRET and TEXTLOCAL_API_KEY must be different values.",
    });
  }

  return { ok: issues.length === 0, provider, issues };
}

function hookSecretBytes(raw: string): Uint8Array {
  const trimmed = raw.trim().replace(/^["']|["']$/g, "");
  const base64Part = trimmed.startsWith("v1,whsec_")
    ? trimmed.slice("v1,whsec_".length)
    : trimmed;
  const cleaned = base64Part.replace(/\s/g, "");
  const normalized = cleaned.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  } catch {
    throw new Error("hook_secret_not_base64");
  }
}

function toBase64(bytes: ArrayBuffer): string {
  const view = new Uint8Array(bytes);
  let binary = "";
  for (const byte of view) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

async function verifyHookPayload(
  payload: string,
  headers: Headers,
  secretRaw: string,
): Promise<SmsHookPayload> {
  const msgId = headers.get("webhook-id");
  const msgTimestamp = headers.get("webhook-timestamp");
  const msgSignature = headers.get("webhook-signature");
  if (!msgId || !msgTimestamp || !msgSignature) {
    throw new Error("missing_webhook_headers");
  }

  const key = await crypto.subtle.importKey(
    "raw",
    hookSecretBytes(secretRaw),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signedContent = `${msgId}.${msgTimestamp}.${payload}`;
  const expected = toBase64(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(signedContent),
    ),
  );

  const valid = msgSignature.split(" ").some((part) => {
    const comma = part.indexOf(",");
    if (comma === -1) return false;
    return part.slice(comma + 1) === expected;
  });

  if (!valid) {
    throw new Error("invalid_webhook_signature");
  }

  log("verify_ok");
  return JSON.parse(payload) as SmsHookPayload;
}

function phoneToMsisdn(phone: string): string {
  const trimmed = phone.trim();
  if (trimmed.startsWith("+")) {
    return trimmed.slice(1);
  }
  return trimmed;
}

function validateEthiopianMsisdn(msisdn: string): boolean {
  return ETHIOPIAN_MOBILE_MSISDN.test(msisdn);
}

function otpMessage(otp: string): string {
  return `Pharma Shelf code: ${otp}. Valid for 10 minutes. Do not share.`;
}

async function sendViaSmsEthiopia(
  msisdn: string,
  text: string,
): Promise<Response> {
  const apiKey = readSecret("SMSETHIOPIA_API_KEY");
  if (!apiKey || apiKey === "UPDATE_ME" || looksLikeHookSecret(apiKey)) {
    log("smsethiopia_missing_or_invalid_key");
    return jsonResponse({ error: "smsethiopia_api_key_missing" }, 500);
  }

  log("smsethiopia_send_start", { msisdn: maskPhone(msisdn) });

  const res = await fetch("https://smsethiopia.com/api/sms/send", {
    method: "POST",
    headers: {
      KEY: apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ msisdn, text }),
  });

  const detail = await res.text();
  log("smsethiopia_response", {
    status: res.status,
    ok: res.ok,
    detailLength: detail.length,
  });

  let parsed: Record<string, unknown> | null = null;
  try {
    parsed = JSON.parse(detail) as Record<string, unknown>;
  } catch {
    parsed = null;
  }

  if (!res.ok) {
    const providerMessage = String(
      parsed?.error_message ?? parsed?.message ?? detail,
    );
    const notWhitelisted = providerMessage.includes("NOT_WHITELISTED") ||
      providerMessage.includes("whitelist");
    return jsonResponse(
      {
        error: notWhitelisted
          ? "smsethiopia_recipient_not_whitelisted"
          : "smsethiopia_http_failed",
        message: notWhitelisted
          ? "This phone number is not verified on the SMS provider yet. Contact support or verify the number in SMSEthiopia."
          : "SMS provider rejected the message.",
        detail: providerMessage.slice(0, 500),
      },
      notWhitelisted ? 400 : 502,
    );
  }

  if (parsed) {
    const status = String(parsed.status ?? "");
    if (status && status !== "success" && parsed.sent !== true) {
      const providerMessage = String(
        parsed.error_message ?? parsed.message ?? detail,
      );
      log("smsethiopia_api_error", { status, message: providerMessage });
      return jsonResponse(
        { error: "smsethiopia_api_failed", detail: providerMessage },
        502,
      );
    }
  }

  log("smsethiopia_send_ok");
  return jsonResponse({}, 200);
}

async function sendViaTextlocal(
  msisdn: string,
  text: string,
): Promise<Response> {
  const apiKey = readSecret("TEXTLOCAL_API_KEY");
  const sender = readSecret("TEXTLOCAL_SENDER") || "Pharma Shelf";
  if (!apiKey) {
    log("textlocal_missing_key");
    return jsonResponse({ error: "textlocal_api_key_missing" }, 500);
  }
  if (looksLikeHookSecret(apiKey)) {
    return jsonResponse({ error: "textlocal_api_key_invalid" }, 500);
  }

  log("textlocal_send_start", { msisdn: maskPhone(msisdn), sender });

  const body = new URLSearchParams({
    apikey: apiKey,
    numbers: msisdn,
    message: text,
    sender,
  });

  const res = await fetch("https://api.textlocal.in/send/", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  const detail = await res.text();
  log("textlocal_response", { status: res.status, ok: res.ok });

  if (!res.ok) {
    return jsonResponse({ error: "textlocal_http_failed", detail }, 502);
  }

  try {
    const parsed = JSON.parse(detail) as { status?: string; errors?: unknown[] };
    if (parsed.status && parsed.status !== "success") {
      log("textlocal_api_error", { status: parsed.status, errors: parsed.errors });
      return jsonResponse({ error: "textlocal_api_failed", detail: parsed }, 502);
    }
  } catch {
    // Non-JSON body; treat HTTP 200 as success.
  }

  log("textlocal_send_ok");
  return jsonResponse({}, 200);
}

async function handleHealthCheck(): Promise<Response> {
  const config = diagnoseConfig();
  log("health_check", { ok: config.ok, issueCount: config.issues.length });
  return jsonResponse(
    {
      service: "send-sms-hook",
      region: "ethiopia",
      provider: config.provider,
      ok: config.ok,
      issues: config.issues,
      hookUrl:
        "https://jyscupmaxarzzscilvvg.supabase.co/functions/v1/send-sms-hook",
      setup: "Run pharma_app/tool/setup-ethiopian-sms.sh to configure secrets.",
    },
    config.ok ? 200 : 503,
  );
}

async function handleSmsHook(req: Request): Promise<Response> {
  const config = diagnoseConfig();
  if (!config.ok) {
    log("config_invalid", { issues: config.issues.map((i) => i.code) });
    return jsonResponse(
      {
        error: "sms_config_invalid",
        issues: config.issues,
      },
      500,
    );
  }

  const hookSecretRaw = readSecret("SEND_SMS_HOOK_SECRET");
  const payloadText = await req.text();
  const verified = await verifyHookPayload(payloadText, req.headers, hookSecretRaw);

  const phone = verified.user?.phone?.trim() ?? "";
  const otp = verified.sms?.otp?.trim() ?? "";
  if (!phone || !otp) {
    log("invalid_payload", { hasPhone: Boolean(phone), otpLength: otp.length });
    return jsonResponse({ error: "invalid_hook_payload" }, 400);
  }

  const msisdn = phoneToMsisdn(phone);
  if (!validateEthiopianMsisdn(msisdn)) {
    log("invalid_ethiopian_msisdn", { msisdn: maskPhone(msisdn) });
    return jsonResponse({ error: "invalid_ethiopian_phone" }, 400);
  }

  const limits = rateLimitConfigFromEnv();
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  if (supabaseUrl && serviceRoleKey) {
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: limitResult, error: limitError } = await admin.rpc(
      "assert_sms_otp_rate_limit",
      {
        p_msisdn: msisdn,
        p_ip_hash: "hook",
        p_record: false,
        p_max_per_phone_day: limits.maxPerPhoneDay,
        p_max_per_ip_day: limits.maxPerIpDay,
        p_max_per_phone_hour: limits.maxPerPhoneHour,
      },
    );
    if (limitError) {
      log("rate_limit_rpc_error", { detail: limitError.message });
    } else if ((limitResult as { allowed?: boolean })?.allowed !== true) {
      const reason = (limitResult as { reason?: string })?.reason ?? "rate_limited";
      log("rate_limit_blocked", { reason, msisdn: maskPhone(msisdn) });
      return jsonResponse({ error: reason }, 429);
    }
  }

  const message = otpMessage(otp);
  const provider = smsProvider();
  log("sending_sms", {
    provider,
    phone: maskPhone(phone),
    msisdn: maskPhone(msisdn),
    otpLength: otp.length,
  });

  if (provider === "textlocal") {
    return await sendViaTextlocal(msisdn, message);
  }
  return await sendViaSmsEthiopia(msisdn, message);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  if (req.method === "GET") {
    return await handleHealthCheck();
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  log("request_received", {
    userAgent: req.headers.get("user-agent") ?? "unknown",
    provider: smsProvider(),
  });

  try {
    return await handleSmsHook(req);
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    log("error", { detail });

    if (detail === "hook_secret_not_base64") {
      return jsonResponse(
        {
          error: "hook_secret_invalid",
          detail:
            "SEND_SMS_HOOK_SECRET is malformed. Use the full v1,whsec_... from Auth → Hooks → Send SMS.",
        },
        500,
      );
    }
    if (detail === "invalid_webhook_signature") {
      return jsonResponse(
        {
          error: "invalid_webhook_signature",
          detail:
            "Hook secret mismatch. Auth → Hooks → Send SMS must match SEND_SMS_HOOK_SECRET exactly.",
        },
        401,
      );
    }
    return jsonResponse({ error: "hook_failed", detail }, 500);
  }
});
