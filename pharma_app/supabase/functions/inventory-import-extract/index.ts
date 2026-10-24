import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// inventory-import-extract
// Extracts medicine / product rows from an uploaded photo of a supplier
// invoice or stock table using Gemini, then returns a strict, validated JSON
// payload for the Flutter review screen. No stock is committed here.
//
// Required secrets (set with `supabase secrets set ...`):
//   GEMINI_API_KEY             primary key (swap when moving free -> paid)
//   GEMINI_MODEL               optional, defaults to gemini-3.5-flash-lite (fast extract)
//   GEMINI_MODEL_FALLBACK      optional, defaults to gemini-3.6-flash
//   GEMINI_API_KEY_FALLBACK    optional, second project key for quota failover
// Standard Supabase secrets are also required: SUPABASE_URL,
// SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY.
//
// Note (2026-10): gemini-2.0-flash / gemini-2.0-flash-lite were shut down by Google
// (404). Prefer current Flash / Flash-Lite IDs below.

/** Fast multimodal extract — preferred for invoice/stock table photos. */
const DEFAULT_MODEL = "gemini-3.5-flash-lite";
const DEFAULT_MODEL_FALLBACK = "gemini-3.6-flash";
/** Extra models tried when configured models hit limits / timeouts. */
const BUILTIN_FAILOVER_MODELS = [
  "gemini-3.8-flash",
  "gemini-3.6-flash",
  "gemini-3.5-flash-lite",
];

const FAILOVER_RETRY_DELAY_MS = 250;
const GEMINI_CALL_TIMEOUT_MS = 45_000;

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ImportMode = "purchase_invoice" | "direct_stock_in";

type RequestBody = {
  mode?: string;
  image_base64?: string;
  mime_type?: string;
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function logEvent(
  level: "info" | "error",
  event: string,
  fields: Record<string, unknown> = {},
): void {
  const line = JSON.stringify({
    fn: "inventory-import-extract",
    level,
    event,
    ...fields,
  });
  if (level === "error") console.error(line);
  else console.log(line);
}

function errorResponse(code: string, status: number, detail?: string): Response {
  logEvent("error", "request_failed", { code, status, detail: detail ?? null });
  return jsonResponse({ error: code, detail: detail ?? null }, status);
}

const ALLOWED_MIME = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
]);

// Roughly 12 MB of base64 (~9 MB binary). Guards against oversized uploads.
const MAX_BASE64_LEN = 12 * 1024 * 1024;

const VALID_CATEGORY_KEYS = new Set([
  "medicine",
  "consumable",
  "medical_device",
  "supplements",
  "personal_care",
  "diagnostics",
  "other",
]);

function buildPrompt(): string {
  return `You are a precise data-extraction engine for a pharmacy inventory app.

You will receive a single photo. It is usually a supplier invoice, a delivery
note, a purchase order, or a handwritten/printed stock table listing medicines
or pharmacy products. The layout, language, column order, and column names VARY
between suppliers. Photos may be skewed, low quality, stamped, watermarked, or
have handwriting, pen marks, and checkmarks.

ORIENTATION (critical):
- The photo may NOT be upright. It may be rotated 90°, 180°, or 270°, captured
  sideways, or uploaded from a gallery with wrong EXIF orientation.
- Read the document as if mentally rotated to the correct upright reading
  position before extracting. Do NOT reject or skip extraction just because the
  image is rotated.
- Identify table header labels (Item, Code, Batch, Expiry, Qty, Price, etc.)
  regardless of rotation, then read each row following that column structure.
- If rotation makes a field uncertain, extract what you can and add a warning
  such as "rotated_image" or "orientation_uncertain" on affected rows or in
  document_warnings.

GOAL: Extract ONLY the product/medicine line items from the table.

STRICTLY IGNORE (never turn these into line items):
- Diagonal or background watermarks (e.g. "ATTACHMENT", "COPY", "SAMPLE").
- Company headers, addresses, phone/fax, TIN/VAT, logos.
- Customer / supplier info blocks, contact person, sales agent.
- Signatures, stamps, "approved by", "prepared by", "checked by".
- Checkmarks, ticks, or pen annotations.
- Subtotal / total / tax / grand total / "amount in words" rows.
- Notes, memos, terms, and any narrative text.

MEDICINE FIELD PARSING (critical — split each product row intelligently):

- name: Brand/trade product line INCLUDING strength, dosage form, and pack
  size when printed on the invoice (e.g. "Amoxil 400mg Tablet",
  "Paracetamol 500mg Tab 10x10", "ACILOC-300", "Dextrose 5% 500ml").
  KEEP strength (400mg, 25mg/ml), pack (10*10, 10x10, 1x10), volume (500ml),
  and dosage form words (Tablet, Tab, Capsule, Injection, Syrup) IN name.
  Do NOT move these to generic_name.

- generic_name: Active ingredient / INN / generic chemical name ONLY when
  clearly present or well known (e.g. "Amoxicillin", "Paracetamol",
  "Ranitidine Hydrochloride", "Pantoprazole"). null if unknown or not shown.

- description: Summary for display = name plus generic in parentheses when
  generic is known: "{name} ({generic_name})". If no generic, description = name.

- manual_code: Internal item / product / stock code for this row (columns like
  Code, Item No, SKU, Product Code). NOT the same as barcode.

- barcode: EAN/UPC/GTIN barcode digits ONLY when explicitly shown as a barcode
  number. Do not put manual_code here.

- reorder_level: Minimum/reorder stock level if a column shows it; else null.

- category_key: Pick ONE fixed key based on product type:
  medicine | consumable | medical_device | supplements | personal_care |
  diagnostics | other
  Use medicine for pharmaceutical tablets/injections/syrups/creams; consumable
  for gloves/syringes/cotton/bandages; medical_device for thermometers/
  glucometers/nebulizers; supplements for vitamins/herbal supplements;
  personal_care for cosmetics/shampoo; diagnostics for test kits/strips;
  other when unsure.

- subcategory: Therapeutic class when inferrable — pick the CLOSEST from:
  ANTI-INFECTIVE | CARDIOVASCULAR | GASTROINTESTINAL | RESPIRATORY & ALLERGY |
  PAIN & INFLAMMATION | VITAMINS & MINERALS | ENDOCRINE | OTHER / UNCATEGORIZED

- strength: e.g. "400mg", "5%", "25mg/ml" when identifiable; else null.
- dosage_form: e.g. "Tablet", "Injection", "Syrup", "Cream"; else null.
- presentation: pack/presentation text e.g. "Box of 10x10 tablets"; else null.

For every genuine product row, also extract these inventory fields (use null
when absent or unreadable; NEVER guess or invent values):
- batch_no: batch / lot number if present.
- expiry_date: expiry in ISO "YYYY-MM-DD" if you can confidently normalize it.
- expiry_date_raw: the expiry exactly as printed (e.g. "10/01/2028", "Jan 2028").
- uom: unit of measure as printed (e.g. "Pkt", "Bott", "Tube", "Viall").
- quantity: numeric quantity as a number (no thousands separators).
- unit_cost: unit price / unit cost as a number if present.
- sell_price: selling price as a number ONLY if a distinct sell price column exists.
- line_total: the row total as a number if present.
- field_confidence: object with 0..1 confidence for name, generic_name,
  batch_no, expiry_date, quantity, unit_cost.
- warnings: array of short strings about anything ambiguous in this row.

DATE RULES:
- Dates are DD/MM/YYYY when written with slashes. Normalize full dates using
  that order. Do not warn about date-order ambiguity.
- If only month/year is present, set expiry_date to null and keep the raw value.

HEADER: capture supplier_name, customer_name, invoice_no, invoice_date (ISO if
possible), currency, and grand_total when visible; otherwise null.

DOCUMENT CLASSIFICATION:
- Set is_supported_inventory_document to false if the photo is clearly NOT an
  inventory/invoice/stock document (e.g. a selfie, landscape, unrelated text).
- Put a brief note for skipped regions in ignored_content_summary.

OUTPUT: Return ONLY a single JSON object (no markdown, no code fences, no
commentary) with EXACTLY this shape:
{
  "document_type": string,
  "is_supported_inventory_document": boolean,
  "header": {
    "supplier_name": string|null,
    "customer_name": string|null,
    "invoice_no": string|null,
    "invoice_date": string|null,
    "currency": string|null,
    "grand_total": number|null
  },
  "lines": [
    {
      "row_index": number,
      "name": string|null,
      "generic_name": string|null,
      "description": string|null,
      "manual_code": string|null,
      "barcode": string|null,
      "reorder_level": number|null,
      "category_key": string|null,
      "subcategory": string|null,
      "strength": string|null,
      "dosage_form": string|null,
      "presentation": string|null,
      "batch_no": string|null,
      "expiry_date": string|null,
      "expiry_date_raw": string|null,
      "uom": string|null,
      "quantity": number|null,
      "unit_cost": number|null,
      "sell_price": number|null,
      "line_total": number|null,
      "field_confidence": {
        "name": number,
        "generic_name": number,
        "batch_no": number,
        "expiry_date": number,
        "quantity": number,
        "unit_cost": number
      },
      "warnings": [string]
    }
  ],
  "ignored_content_summary": [string],
  "document_warnings": [string]
}`;
}

function coerceNumberOrNull(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const cleaned = value.replace(/[, ]/g, "").trim();
    if (cleaned.length === 0) return null;
    const n = Number(cleaned);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function coerceStringOrNull(value: unknown): string | null {
  if (typeof value === "string") {
    const t = value.trim();
    return t.length === 0 ? null : t;
  }
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

function coerceConfidence(value: unknown): number {
  const n = coerceNumberOrNull(value);
  if (n == null) return 0;
  if (n < 0) return 0;
  if (n > 1) return 1;
  return n;
}

function coerceStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((v) => (typeof v === "string" ? v.trim() : ""))
    .filter((v) => v.length > 0)
    .slice(0, 40);
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function normalizeIsoDate(value: unknown): string | null {
  const s = coerceStringOrNull(value);
  if (s == null) return null;
  if (!ISO_DATE.test(s)) return null;
  const [y, m, d] = s.split("-").map((p) => Number(p));
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  if (y < 2000 || y > 2100) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) {
    return null;
  }
  return s;
}

function coerceCategoryKey(value: unknown): string | null {
  const s = coerceStringOrNull(value)?.toLowerCase();
  if (s == null) return null;
  return VALID_CATEGORY_KEYS.has(s) ? s : null;
}

function buildDescription(
  name: string | null,
  genericName: string | null,
  rawDescription: string | null,
): string | null {
  if (name != null && genericName != null) return `${name} (${genericName})`;
  if (name != null) return name;
  return rawDescription;
}

// deno-lint-ignore no-explicit-any
function normalizeLine(raw: any, index: number) {
  const fc = raw?.field_confidence ?? {};
  const name = coerceStringOrNull(raw?.name) ??
    coerceStringOrNull(raw?.description);
  const genericName = coerceStringOrNull(raw?.generic_name);
  const manualCode = coerceStringOrNull(raw?.manual_code) ??
    coerceStringOrNull(raw?.supplier_code);
  const description = buildDescription(
    name,
    genericName,
    coerceStringOrNull(raw?.description),
  );
  return {
    row_index: typeof raw?.row_index === "number" ? raw.row_index : index + 1,
    name,
    generic_name: genericName,
    description,
    manual_code: manualCode,
    supplier_code: manualCode,
    barcode: coerceStringOrNull(raw?.barcode),
    reorder_level: coerceNumberOrNull(raw?.reorder_level),
    category_key: coerceCategoryKey(raw?.category_key),
    subcategory: coerceStringOrNull(raw?.subcategory),
    strength: coerceStringOrNull(raw?.strength),
    dosage_form: coerceStringOrNull(raw?.dosage_form),
    presentation: coerceStringOrNull(raw?.presentation),
    batch_no: coerceStringOrNull(raw?.batch_no),
    expiry_date: normalizeIsoDate(raw?.expiry_date),
    expiry_date_raw: coerceStringOrNull(raw?.expiry_date_raw),
    uom: coerceStringOrNull(raw?.uom),
    quantity: coerceNumberOrNull(raw?.quantity),
    unit_cost: coerceNumberOrNull(raw?.unit_cost),
    sell_price: coerceNumberOrNull(raw?.sell_price),
    line_total: coerceNumberOrNull(raw?.line_total),
    field_confidence: {
      name: coerceConfidence(fc?.name ?? fc?.description),
      generic_name: coerceConfidence(fc?.generic_name),
      description: coerceConfidence(fc?.description ?? fc?.name),
      batch_no: coerceConfidence(fc?.batch_no),
      expiry_date: coerceConfidence(fc?.expiry_date),
      quantity: coerceConfidence(fc?.quantity),
      unit_cost: coerceConfidence(fc?.unit_cost),
    },
    warnings: coerceStringArray(raw?.warnings),
  };
}

// deno-lint-ignore no-explicit-any
function normalizePayload(parsed: any) {
  const header = parsed?.header ?? {};
  const linesRaw = Array.isArray(parsed?.lines) ? parsed.lines : [];
  // deno-lint-ignore no-explicit-any
  const lines = linesRaw
    .map((l: any, i: number) => normalizeLine(l, i))
    // Drop rows with no usable content at all.
    .filter(
      (l: {
        description: string | null;
        name: string | null;
        quantity: number | null;
      }) =>
        l.description != null || l.name != null || l.quantity != null,
    )
    .slice(0, 200);
  return {
    document_type: coerceStringOrNull(parsed?.document_type) ?? "unknown",
    is_supported_inventory_document:
      parsed?.is_supported_inventory_document === true,
    header: {
      supplier_name: coerceStringOrNull(header?.supplier_name),
      customer_name: coerceStringOrNull(header?.customer_name),
      invoice_no: coerceStringOrNull(header?.invoice_no),
      invoice_date: normalizeIsoDate(header?.invoice_date),
      currency: coerceStringOrNull(header?.currency),
      grand_total: coerceNumberOrNull(header?.grand_total),
    },
    lines,
    ignored_content_summary: coerceStringArray(parsed?.ignored_content_summary),
    document_warnings: coerceStringArray(parsed?.document_warnings),
  };
}

function extractJsonObject(text: string): string | null {
  const trimmed = text.trim();
  // Strip markdown code fences if present.
  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  const candidate = fenceMatch ? fenceMatch[1] : trimmed;
  const start = candidate.indexOf("{");
  const end = candidate.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return null;
  return candidate.slice(start, end + 1);
}

// Per-attempt ceiling (failover tries many key/model pairs).
const GEMINI_TIMEOUT_MS = GEMINI_CALL_TIMEOUT_MS;

async function callGemini(
  apiKey: string,
  model: string,
  mimeType: string,
  imageBase64: string,
): Promise<{ ok: true; text: string } | { ok: false; status: number; body: string }> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const requestBody = {
    contents: [
      {
        role: "user",
        parts: [
          { text: buildPrompt() },
          { inline_data: { mime_type: mimeType, data: imageBase64 } },
        ],
      },
    ],
    generationConfig: {
      temperature: 0,
      topP: 0.1,
      maxOutputTokens: 16384,
      responseMimeType: "application/json",
    },
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), GEMINI_TIMEOUT_MS);
  const startedAt = Date.now();
  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify(requestBody),
      signal: controller.signal,
    });
  } catch (e) {
    clearTimeout(timeout);
    const aborted = e instanceof DOMException && e.name === "AbortError";
    logEvent("error", "gemini_fetch_failed", {
      model,
      aborted,
      elapsedMs: Date.now() - startedAt,
      message: e instanceof Error ? e.message : String(e),
    });
    // 504 => treat as retryable/timeout upstream.
    return { ok: false, status: aborted ? 504 : 502, body: aborted ? "gemini_timeout" : "gemini_fetch_error" };
  }
  clearTimeout(timeout);

  logEvent("info", "gemini_response", {
    model,
    status: res.status,
    elapsedMs: Date.now() - startedAt,
  });

  if (!res.ok) {
    const body = await res.text();
    return { ok: false, status: res.status, body };
  }
  let data: unknown;
  try {
    data = await res.json();
  } catch (_) {
    return { ok: false, status: 502, body: "invalid_json_response" };
  }
  // Some Gemini quota/rate errors arrive as JSON error payloads.
  // deno-lint-ignore no-explicit-any
  const err = (data as any)?.error;
  if (err != null) {
    const errCode = typeof err.code === "number" ? err.code : res.status;
    const errBody = typeof err.message === "string"
      ? err.message
      : JSON.stringify(err);
    const status = errCode >= 400 ? errCode : res.status;
    logEvent("error", "gemini_api_error", {
      model,
      httpStatus: res.status,
      errorCode: errCode,
      errorStatus: err.status ?? null,
      message: errBody.slice(0, 240),
    });
    return { ok: false, status, body: errBody };
  }
  // deno-lint-ignore no-explicit-any
  const parts = (data as any)?.candidates?.[0]?.content?.parts as any[] | undefined;
  const text = parts?.map((p) => (typeof p?.text === "string" ? p.text : "")).join("") ?? "";
  if (text.trim().length === 0) {
    return { ok: false, status: 422, body: "empty_model_response" };
  }
  return { ok: true, text };
}

type GeminiHttpError = { ok: false; status: number; body: string };

function isQuotaOrRateLimit(status: number, body: string): boolean {
  if (status === 429 || status === 503) return true;
  const lower = body.toLowerCase();
  if (status === 403 && lower.includes("quota")) return true;
  return (
    lower.includes("quota") ||
    lower.includes("rate limit") ||
    lower.includes("rate_limit") ||
    lower.includes("resource_exhausted") ||
    lower.includes("resource exhausted") ||
    lower.includes("too many requests") ||
    lower.includes("exceeded your current quota") ||
    lower.includes("daily limit") ||
    lower.includes("limit: 0")
  );
}

function isModelOrConfigError(status: number, body: string): boolean {
  if (status === 404) return true;
  const lower = body.toLowerCase();
  return (
    status === 400 &&
    (lower.includes("not found") ||
      lower.includes("not supported") ||
      lower.includes("invalid model") ||
      lower.includes("response_mime_type"))
  );
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryableHttp(status: number, body = ""): boolean {
  if (isQuotaOrRateLimit(status, body)) return true;
  if (isModelOrConfigError(status, body)) return true;
  if (status === 422 || status === 408) return true;
  return status >= 500;
}

type FailoverAttempt = {
  model: string;
  key: string;
  keyLabel: string;
};

type FailoverTraceEntry = {
  attempt: number;
  model: string;
  key: string;
  status: number;
  quota: boolean;
};

function resolveApiKeys(primaryKey: string): string[] {
  const keys: string[] = [];
  const add = (raw: string | undefined) => {
    const t = raw?.trim() ?? "";
    if (t.length === 0 || keys.includes(t)) return;
    keys.push(t);
  };
  add(primaryKey);
  add(Deno.env.get("GEMINI_API_KEY_FALLBACK") ?? undefined);
  const csv = Deno.env.get("GEMINI_API_KEYS");
  if (csv != null) {
    for (const part of csv.split(",")) add(part);
  }
  return keys;
}

/** Model-first, then keys: primary quota → fallback key on same model immediately. */
function buildFailoverAttempts(
  apiKeys: string[],
  models: string[],
): FailoverAttempt[] {
  const attempts: FailoverAttempt[] = [];
  for (const model of models) {
    for (let i = 0; i < apiKeys.length; i++) {
      attempts.push({
        model,
        key: apiKeys[i],
        keyLabel: i === 0 ? "primary" : `fallback_${i}`,
      });
    }
  }
  return attempts;
}

// deno-lint-ignore no-explicit-any
type NormalizedPayload = ReturnType<typeof normalizePayload>;

/** Shut-down or superseded model IDs → current replacements (secrets may still list old names). */
const GEMINI_MODEL_REPLACEMENTS: Record<string, string> = {
  "gemini-2.0-flash": "gemini-3.8-flash",
  "gemini-2.0-flash-lite": "gemini-3.5-flash-lite",
  "gemini-2.0-flash-001": "gemini-3.8-flash",
  "gemini-2.0-flash-lite-001": "gemini-3.5-flash-lite",
  "gemini-2.5-flash": "gemini-3.6-flash",
  "gemini-2.5-flash-lite": "gemini-3.5-flash-lite",
  "gemini-1.5-flash": "gemini-3.5-flash-lite",
  "gemini-1.5-flash-latest": "gemini-3.5-flash-lite",
  "gemini-1.5-pro": "gemini-3.6-flash",
  "gemini-1.5-pro-latest": "gemini-3.6-flash",
};

function canonicalizeGeminiModel(model: string): string {
  return GEMINI_MODEL_REPLACEMENTS[model.trim()] ?? model.trim();
}

function resolveModelChain(): string[] {
  const fromEnv = Deno.env.get("GEMINI_MODELS");
  const primary = Deno.env.get("GEMINI_MODEL") ?? DEFAULT_MODEL;
  const fallback = Deno.env.get("GEMINI_MODEL_FALLBACK") ?? DEFAULT_MODEL_FALLBACK;
  const envList = fromEnv != null
    ? fromEnv.split(",").map((s) => s.trim()).filter((s) => s.length > 0)
    : [];
  // Lite first for photo extract (faster / less 503 than heavy Flash). Env
  // models still used, but after the preferred extract defaults.
  const chain = uniqueStrings(
    [
      DEFAULT_MODEL,
      DEFAULT_MODEL_FALLBACK,
      ...BUILTIN_FAILOVER_MODELS,
      ...envList,
      primary,
      fallback,
    ].map(canonicalizeGeminiModel),
  );
  if (chain.length === 0) {
    return uniqueStrings([
      DEFAULT_MODEL,
      DEFAULT_MODEL_FALLBACK,
      ...BUILTIN_FAILOVER_MODELS,
    ]);
  }
  return chain;
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const v of values) {
    const t = v.trim();
    if (t.length === 0 || seen.has(t)) continue;
    seen.add(t);
    out.push(t);
  }
  return out;
}

/** True when we should try the fallback model (parse/quality issues). */
function shouldRetryWithFallbackModel(payload: NormalizedPayload): boolean {
  if (payload.lines.length === 0) return true;
  const usable = payload.lines.filter(
    (l) => l.description != null || l.name != null || l.quantity != null,
  );
  return usable.length === 0;
}

type ParseAttempt =
  | { ok: true; payload: NormalizedPayload }
  | { ok: false; reason: "no_json" | "json_parse" | "low_quality" };
type ParseFailureReason = "no_json" | "json_parse" | "low_quality";

function parseGeminiText(text: string): ParseAttempt {
  const jsonText = extractJsonObject(text);
  if (jsonText == null) return { ok: false, reason: "no_json" };
  // deno-lint-ignore no-explicit-any
  let parsed: any;
  try {
    parsed = JSON.parse(jsonText);
  } catch (_) {
    return { ok: false, reason: "json_parse" };
  }
  const payload = normalizePayload(parsed);
  if (shouldRetryWithFallbackModel(payload)) {
    return { ok: false, reason: "low_quality" };
  }
  return { ok: true, payload };
}

type ExtractOutcome =
  | {
    ok: true;
    payload: NormalizedPayload;
    model: string;
    usedFallbackModel: boolean;
    usedFallbackKey: boolean;
  }
  | {
    ok: false;
    code: string;
    httpStatus: number;
    detail?: string;
    documentWarnings?: string[];
    failoverTrace?: FailoverTraceEntry[];
    keysTried?: number;
    modelsTried?: number;
  };

async function extractWithModelFailover(
  primaryKey: string,
  models: string[],
  mimeType: string,
  imageBase64: string,
): Promise<ExtractOutcome> {
  const apiKeys = resolveApiKeys(primaryKey);
  const attempts = buildFailoverAttempts(apiKeys, models);
  let lastHttp: GeminiHttpError | null = null;
  let lastParse: ParseFailureReason | null = null;
  let usedFallbackKey = false;
  let usedFallbackModel = false;
  let attemptIndex = 0;
  let quotaFailures = 0;
  const failoverTrace: FailoverTraceEntry[] = [];
  const keysUsed = new Set<string>();
  const modelsUsed = new Set<string>();
  const primaryModel = models[0];

  logEvent("info", "failover_plan", {
    modelCount: models.length,
    keyCount: apiKeys.length,
    attemptCount: attempts.length,
    models,
    keyLabels: attempts.map((a) => a.keyLabel),
  });

  for (const attempt of attempts) {
    attemptIndex += 1;
    if (attempt.keyLabel !== "primary") usedFallbackKey = true;
    if (attempt.model !== primaryModel) usedFallbackModel = true;
    keysUsed.add(attempt.keyLabel);
    modelsUsed.add(attempt.model);

    logEvent("info", "gemini_attempt", {
      attempt: attemptIndex,
      total: attempts.length,
      model: attempt.model,
      key: attempt.keyLabel,
    });

    const httpResult = await callGemini(
      attempt.key,
      attempt.model,
      mimeType,
      imageBase64,
    );

    if (!httpResult.ok) {
      lastHttp = httpResult;
      const quota = isQuotaOrRateLimit(httpResult.status, httpResult.body);
      if (quota) quotaFailures += 1;
      failoverTrace.push({
        attempt: attemptIndex,
        model: attempt.model,
        key: attempt.keyLabel,
        status: httpResult.status,
        quota,
      });
      logEvent("error", "gemini_attempt_failed", {
        attempt: attemptIndex,
        model: attempt.model,
        key: attempt.keyLabel,
        status: httpResult.status,
        quota,
        bodySnippet: httpResult.body.slice(0, 180),
      });
      if (attemptIndex < attempts.length) {
        await sleep(FAILOVER_RETRY_DELAY_MS);
      }
      continue;
    }

    const parsed = parseGeminiText(httpResult.text);
    if (!parsed.ok) {
      lastParse = parsed.reason;
      failoverTrace.push({
        attempt: attemptIndex,
        model: attempt.model,
        key: attempt.keyLabel,
        status: 422,
        quota: false,
      });
      logEvent("error", "gemini_parse_failed", {
        attempt: attemptIndex,
        model: attempt.model,
        key: attempt.keyLabel,
        reason: parsed.reason,
      });
      if (attemptIndex < attempts.length) {
        await sleep(FAILOVER_RETRY_DELAY_MS);
      }
      continue;
    }

    const payload = parsed.payload;
    if (!payload.is_supported_inventory_document && payload.lines.length === 0) {
      return {
        ok: false,
        code: "unsupported_document",
        httpStatus: 422,
        detail: "no_inventory_table_found",
        documentWarnings: payload.document_warnings,
        failoverTrace,
        keysTried: keysUsed.size,
        modelsTried: modelsUsed.size,
      };
    }

    logEvent("info", "gemini_attempt_ok", {
      attempt: attemptIndex,
      model: attempt.model,
      key: attempt.keyLabel,
      lineCount: payload.lines.length,
    });

    return {
      ok: true,
      payload,
      model: attempt.model,
      usedFallbackModel,
      usedFallbackKey,
    };
  }

  const failMeta = {
    failoverTrace,
    keysTried: keysUsed.size,
    modelsTried: modelsUsed.size,
  };

  if (lastHttp != null) {
    if (isQuotaOrRateLimit(lastHttp.status, lastHttp.body) || quotaFailures > 0) {
      logEvent("error", "failover_quota_exhausted", {
        attempts: attempts.length,
        attemptsExecuted: attemptIndex,
        quotaFailures,
        keysTried: keysUsed.size,
        lastStatus: lastHttp.status,
        trace: failoverTrace,
      });
      return {
        ok: false,
        code: "quota_exceeded",
        httpStatus: 429,
        detail: apiKeys.length > 1
          ? "all_failover_attempts_exhausted"
          : "quota_exceeded",
        ...failMeta,
      };
    }
    if (lastHttp.status === 504 || lastHttp.body === "gemini_timeout") {
      return {
        ok: false,
        code: "extract_provider_error",
        httpStatus: 504,
        detail: "timeout",
        ...failMeta,
      };
    }
    if (lastHttp.status === 400 || lastHttp.status === 413) {
      return {
        ok: false,
        code: "image_rejected",
        httpStatus: 422,
        detail: "bad_image",
        ...failMeta,
      };
    }
    return {
      ok: false,
      code: "extract_provider_error",
      httpStatus: 502,
      detail: "provider_unavailable",
      ...failMeta,
    };
  }

  if (lastParse === "no_json" || lastParse === "json_parse") {
    return {
      ok: false,
      code: "extract_unreadable",
      httpStatus: 422,
      detail: lastParse,
      ...failMeta,
    };
  }

  return {
    ok: false,
    code: "unsupported_document",
    httpStatus: 422,
    detail: "no_inventory_table_found",
    ...failMeta,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return errorResponse("method_not_allowed", 405);
  }

  logEvent("info", "request_received", {
    hasAuth: req.headers.get("Authorization") != null,
    contentLength: req.headers.get("content-length"),
  });

  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
  if (jwt.length === 0) {
    return errorResponse("unauthorized", 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (supabaseUrl == null || anonKey == null || serviceRoleKey == null) {
    return errorResponse("server_env_missing", 500);
  }

  const primaryKey = Deno.env.get("GEMINI_API_KEY");
  const models = resolveModelChain();
  const apiKeys = primaryKey != null ? resolveApiKeys(primaryKey) : [];
  if (primaryKey == null || primaryKey.length === 0) {
    return errorResponse("extract_not_configured", 500);
  }

  logEvent("info", "extract_config", {
    modelCount: models.length,
    keyCount: apiKeys.length,
    models,
  });

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

  const { data: userData } = await callerClient.auth.getUser();
  const callerUser = userData.user;
  if (callerUser == null) {
    return errorResponse("unauthorized", 401);
  }

  const { data: callerProfile, error: profileError } = await callerClient
    .from("profiles")
    .select("team_id, role, is_active")
    .eq("id", callerUser.id)
    .maybeSingle();
  if (profileError != null) {
    return errorResponse("profile_error", 400, profileError.message);
  }
  if (
    callerProfile == null ||
    callerProfile.is_active !== true ||
    (callerProfile.role !== "admin" && callerProfile.role !== "owner")
  ) {
    return errorResponse("forbidden", 403);
  }

  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch (_) {
    return errorResponse("bad_request", 400, "invalid_json");
  }

  const mode: ImportMode =
    body.mode === "direct_stock_in" ? "direct_stock_in" : "purchase_invoice";
  const imageBase64 = body.image_base64?.trim() ?? "";
  const mimeType = (body.mime_type?.trim() ?? "image/jpeg").toLowerCase();

  if (imageBase64.length === 0) {
    return errorResponse("missing_image", 400);
  }
  if (imageBase64.length > MAX_BASE64_LEN) {
    return errorResponse("image_too_large", 413);
  }
  if (!ALLOWED_MIME.has(mimeType)) {
    return errorResponse("unsupported_mime", 415, mimeType);
  }

  const startedAt = Date.now();
  const outcome = await extractWithModelFailover(
    primaryKey,
    models,
    mimeType,
    imageBase64,
  );

  if (!outcome.ok) {
    logEvent("error", "extract_failed", {
      code: outcome.code,
      httpStatus: outcome.httpStatus,
      detail: outcome.detail ?? null,
      warningCount: outcome.documentWarnings?.length ?? 0,
      keysTried: outcome.keysTried ?? null,
      modelsTried: outcome.modelsTried ?? null,
      failoverTrace: outcome.failoverTrace ?? null,
    });
    return jsonResponse(
      {
        error: outcome.code,
        detail: outcome.detail ?? null,
        document_warnings: outcome.documentWarnings ?? null,
        keys_tried: outcome.keysTried ?? null,
        models_tried: outcome.modelsTried ?? null,
        failover_trace: outcome.failoverTrace ?? null,
      },
      outcome.httpStatus,
    );
  }

  const elapsedMs = Date.now() - startedAt;

  logEvent("info", "extract_ok", {
    lineCount: outcome.payload.lines.length,
    supported: outcome.payload.is_supported_inventory_document,
    model: outcome.model,
    usedFallbackModel: outcome.usedFallbackModel,
    usedFallbackKey: outcome.usedFallbackKey,
    elapsedMs,
    mode,
  });

  return jsonResponse(
    {
      mode,
      model: outcome.model,
      used_fallback_model: outcome.usedFallbackModel,
      used_fallback_key: outcome.usedFallbackKey,
      elapsed_ms: elapsedMs,
      result: outcome.payload,
    },
    200,
  );
});
