# Ops gates and platform messaging

This document describes **server-driven controls** for app version enforcement, team billing/subscription gates, and global announcements. It is meant for **operators and future maintainers** (no in-app admin UI is required today).

Schema and RPC changes live in the migration:

[`../supabase/migrations/20260430210000_app_gates_billing_platform_messages.sql`](../supabase/migrations/20260430210000_app_gates_billing_platform_messages.sql)

---

## 1. Force update (`app_client_config`)

### Purpose

Block (or prepare to block) **outdated app binaries** when APIs, security, or flows require a newer build. The Flutter app compares its **published version** (from `pubspec.yaml` / store) to `min_supported_version` and, when `force_update` is true, redirects to **`/update-required`**.

### Where to manage

Supabase **Dashboard** → **Table Editor** → `app_client_config` (single logical row, **`id = 1`**) or **SQL Editor**.

### Columns

| Column | Type | Notes |
|--------|------|--------|
| `id` | `smallint` | Must stay `1` (singleton). |
| `min_supported_version` | `text` | Semver string, e.g. `1.2.0`. Build suffix in the app (`1.0.0+5`) is **ignored** for comparison; only `1.0.0` is compared. |
| `force_update` | `boolean` | If `true` **and** installed version **&lt;** `min_supported_version`, the app blocks with the update screen. |
| `update_message` | `text` | Optional copy on the update screen. |
| `store_url_ios` | `text` | App Store (or TestFlight) URL for “Get update” on iOS. |
| `store_url_android` | `text` | Play Store URL on Android. |
| `store_url_web` | `text` | Used on **web** and as fallback when a native URL is empty. |

### Access (RLS)

**`SELECT`** is allowed for **`anon`** and **`authenticated`**. There is no policy for clients to **write** this table; updates are done with the **service role** in SQL/scripts or from the Supabase UI as a project owner.

### Recommended rollout

1. Ship a new app version to stores and wait until a reasonable share has updated (optional).
2. Set `min_supported_version` to the **minimum** build you still support.
3. Set `force_update = true` when you are ready to **hard-block** older builds.
4. Set `force_update = false` to stop blocking (e.g. emergency rollback).

### Example SQL

```sql
UPDATE public.app_client_config
SET
  min_supported_version = '1.1.0',
  force_update = true,
  update_message = 'This release fixes inventory sync. Please update to continue.',
  store_url_web = 'https://example.com/download',
  updated_at = now()
WHERE id = 1;
```

---

## 2. Billing and subscription gate (`teams`)

### Purpose

Control **whether a team may use pharmacy features** beyond a simple trial date: paid vs trial vs grace vs blocked states. The app reads **`billing_status`** (and optional **`billing_grace_ends_at`**) together with **`trial_ends_at`** and routes users to **`/trial-ended`** or **`/billing-blocked`**. **Mutations** on the backend also call **`assert_team_may_mutate`**, which can raise **`billing_blocked`** so bypassing the UI is not enough.

### Where to manage

Supabase **Table Editor** → **`teams`**, or **SQL Editor** / automation (e.g. future Stripe webhooks updating `billing_status`).

### Columns (relevant to this feature)

| Column | Notes |
|--------|--------|
| `status` | Platform-level: `active` vs `suspended`. Suspended teams use **`/suspended`** (unchanged). |
| `trial_ends_at` | Trial end instant (UTC). Still used when `billing_status = 'trial'`. |
| `billing_status` | One of: `trial`, `active`, `grace`, `past_due`, `suspended_billing`, `churned` (see migration `CHECK`). |
| `billing_grace_ends_at` | Used when `billing_status = 'grace'`; after this time (if set), access aligns with “grace expired” behavior. |

### Client routing (summary)

- **`billing_status = 'active'`** — trial clock does **not** block pharmacy access for trial wording; use this for paying or grandfathered teams.
- **`billing_status = 'trial'`** and **`trial_ends_at`** in the past — **`/trial-ended`**.
- **`past_due`**, **`suspended_billing`**, **`churned`**, or **`grace`** with expired grace — **`/billing-blocked`**.

Exact precedence in the app is documented in **`lib/core/router/app_router.dart`** (force update → auth → suspended → billing → trial → roles).

### Example SQL

Grandfather a team to paid access (ignores trial end for gating):

```sql
UPDATE public.teams
SET billing_status = 'active'
WHERE id = '<team_uuid>';
```

Payment problem (block non-trial UX):

```sql
UPDATE public.teams
SET billing_status = 'past_due'
WHERE id = '<team_uuid>';
```

Short extension:

```sql
UPDATE public.teams
SET
  billing_status = 'grace',
  billing_grace_ends_at = now() + interval '14 days'
WHERE id = '<team_uuid>';
```

### User-visible errors

If the database rejects a write with **`billing_blocked`**, the app maps that to a billing/support message (see **`lib/core/forms/form_error_mapper.dart`**).

---

## 3. Platform messages (`platform_messages` + `platform_message_reads`)

### Purpose

**Global** announcements (maintenance, policy, critical incidents) **without** mixing them into per-team **`notifications`** (stock/expiry alerts).

### Where to manage

- **Insert / update / delete** rows in **`platform_messages`**.  
- RLS: only **`platform_admins`** (active) have **`FOR ALL`** on `platform_messages`. Team members only **`SELECT`** active rows in the time window.
- **`platform_message_reads`** is written by the **app** when a user dismisses or acknowledges a message.

### Columns

| Column | Notes |
|--------|--------|
| `title`, `body` | Shown in drawer, banner, and **`/pharmacy/platform-messages`**. |
| `severity` | `info`, `warning`, `critical`. First **unread** `warning`/`critical` can drive a **MaterialBanner** in the pharmacy shell. |
| `starts_at`, `ends_at` | Message visible when `starts_at <= now()` and (`ends_at` is null or `ends_at >= now()`). |
| `min_app_version` | Optional; if set, clients below this semver **hide** the message until they update. |

### In-app behavior

- Drawer: **campaign** icon + unread count.
- Shell: **banner** for unread **warning** / **critical** messages (dismiss marks read).
- Full list: **`/pharmacy/platform-messages`** (also on role allowlists in the router).

### Example SQL (as superuser / service role or via admin tooling)

```sql
INSERT INTO public.platform_messages (title, body, severity, starts_at, ends_at)
VALUES (
  'Planned maintenance',
  'POS sync may be delayed tonight 22:00–23:00 UTC.',
  'warning',
  now(),
  now() + interval '2 days'
);
```

To retire a message early, set **`ends_at`** to **`now()`** or delete the row.

---

## 4. Operational checklist

| Goal | Action |
|------|--------|
| Force users onto a new build | `app_client_config`: raise `min_supported_version`, set `force_update`, set store URLs. |
| Stop forcing updates | `force_update = false`. |
| Mark team as paying | `teams.billing_status = 'active'`. |
| Block team for billing | `past_due`, `suspended_billing`, or `churned`. |
| Give a short extension | `grace` + `billing_grace_ends_at`. |
| Broadcast to all signed-in users | Insert into `platform_messages` (as platform admin or service role). |

---

## 5. Applying schema changes

After pulling migrations, apply them to your Supabase project (CLI or linked project):

```bash
cd pharma_app
supabase db push
```

Or run the SQL from the migration file in the **SQL Editor** on a fresh environment (not recommended for production drift; prefer versioned migrations).

---

## 6. Related app files (for engineers)

| Topic | File |
|------|------|
| Version compare | `lib/core/utils/app_version_compare.dart` |
| Update gate + router refresh | `lib/core/providers/app_update_gate_provider.dart` |
| Team gate cache | `lib/core/providers/pharmacy_redirect_cache_provider.dart` |
| Redirect order and routes | `lib/core/router/app_router.dart` |
| Platform messages provider | `lib/core/providers/platform_messages_provider.dart` |
| Shell banner + badges | `lib/features/pharmacy/pharmacy_shell.dart` |

---

## 7. Future improvements (optional)

- **Internal admin screens** in the app for `app_client_config` and `platform_messages` (would still use RLS or service role carefully).
- **Stripe (or similar) webhooks** updating `teams.billing_status` automatically.
- **Soft update** nudge when `force_update` is false but version is below a “recommended” threshold (not implemented today).
