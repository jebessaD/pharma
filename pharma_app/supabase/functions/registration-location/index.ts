import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type LocationPayload = {
  country_code: string | null;
  country_name: string | null;
  region: string | null;
  city: string | null;
  source: "ip" | null;
};

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const emptyPayload: LocationPayload = {
  country_code: null,
  country_name: null,
  region: null,
  city: null,
  source: null,
};

function textOrNull(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  return trimmed.slice(0, maxLength);
}

function countryCodeOrNull(value: unknown): string | null {
  const code = textOrNull(value, 2)?.toUpperCase() ?? null;
  return code != null && /^[A-Z]{2}$/.test(code) ? code : null;
}

function isPrivateIp(ip: string): boolean {
  if (
    ip === "127.0.0.1" ||
    ip === "::1" ||
    ip.startsWith("10.") ||
    ip.startsWith("192.168.") ||
    /^172\.(1[6-9]|2\d|3[0-1])\./.test(ip) ||
    /^(fc|fd)/i.test(ip)
  ) {
    return true;
  }
  return false;
}

function clientIpFromHeaders(headers: Headers): string | null {
  const candidates = [
    headers.get("cf-connecting-ip"),
    headers.get("x-real-ip"),
    headers.get("x-forwarded-for")?.split(",")[0],
  ];

  for (const candidate of candidates) {
    const ip = candidate?.trim();
    if (ip != null && ip.length > 0 && !isPrivateIp(ip)) return ip;
  }
  return null;
}

async function lookupWithIpapi(ip: string): Promise<LocationPayload> {
  const res = await fetch(`https://ipapi.co/${encodeURIComponent(ip)}/json/`, {
    signal: AbortSignal.timeout(1500),
    headers: { Accept: "application/json" },
  });
  if (!res.ok) return emptyPayload;

  const json = (await res.json()) as Record<string, unknown>;
  const countryCode = countryCodeOrNull(json.country_code);
  const countryName = textOrNull(json.country_name, 120);
  const region = textOrNull(json.region, 120);
  const city = textOrNull(json.city, 120);

  if (
    countryCode == null &&
    countryName == null &&
    region == null &&
    city == null
  ) {
    return emptyPayload;
  }

  return {
    country_code: countryCode,
    country_name: countryName,
    region,
    city,
    source: "ip",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response("method_not_allowed", {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  const ip = clientIpFromHeaders(req.headers);
  if (ip == null) {
    return Response.json(emptyPayload, {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const provider = (Deno.env.get("REGISTRATION_GEO_PROVIDER") ?? "ipapi")
      .trim()
      .toLowerCase();
    const payload =
      provider === "ipapi" ? await lookupWithIpapi(ip) : emptyPayload;

    return Response.json(payload, {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (_) {
    return Response.json(emptyPayload, {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
