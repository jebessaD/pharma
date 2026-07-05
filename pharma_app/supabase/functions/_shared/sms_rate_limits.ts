export type RateLimitConfig = {
  maxPerPhoneDay: number;
  maxPerIpDay: number;
  maxPerPhoneHour: number;
};

export function rateLimitConfigFromEnv(): RateLimitConfig {
  return {
    maxPerPhoneDay: parseInt(Deno.env.get("SMS_MAX_PER_PHONE_DAY") ?? "10", 10),
    maxPerIpDay: parseInt(Deno.env.get("SMS_MAX_PER_IP_DAY") ?? "30", 10),
    maxPerPhoneHour: parseInt(Deno.env.get("SMS_MAX_PER_PHONE_HOUR") ?? "5", 10),
  };
}

export function phoneToMsisdn(phone: string): string {
  const trimmed = phone.trim();
  if (trimmed.startsWith("+")) return trimmed.slice(1);
  return trimmed.replace(/\D/g, "");
}

export async function hashClientIp(ip: string): Promise<string> {
  const normalized = ip.trim().toLowerCase();
  const data = new TextEncoder().encode(`pharma-sms-ip:${normalized}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function clientIpFromRequest(req: Request): string {
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  if (forwarded) return forwarded;
  const realIp = req.headers.get("x-real-ip")?.trim();
  if (realIp) return realIp;
  return "unknown";
}

export function rateLimitUserMessage(reason: string): string {
  switch (reason) {
    case "phone_daily_limit":
      return "Too many codes sent to this number today. Try again tomorrow.";
    case "phone_hourly_limit":
      return "Too many codes sent to this number. Wait an hour and try again.";
    case "ip_daily_limit":
      return "Too many code requests from your network today. Try again tomorrow.";
    case "invalid_msisdn":
      return "Enter a valid Ethiopian mobile number.";
    default:
      return "Too many code requests. Please wait and try again.";
  }
}
