# 11 - Notifications (version 1)

## Version 1 scope (build now)

- in-app alert badge
- alert list for low stock and near expiry

## Out of Scope (Do Not Build)

- SMS, email, WhatsApp delivery
- complex notification preference center

## AI Implementation Directive

- Flutter screens: `NotificationList` (or dashboard modal)
- Supabase table: `notifications`
- Generate notifications from low stock/expiry checks
- Add `is_read` boolean for simple read state

## Supabase Table Detail

`notifications`
- `id` uuid pk
- `team_id` uuid fk
- `branch_id` uuid fk nullable
- `type` text (`low_stock`,`near_expiry`,`expired`)
- `title` text
- `message` text
- `entity_type` text nullable
- `entity_id` uuid nullable
- `is_read` boolean default false
- `created_at` timestamptz

## Validation Rules

- create deduplicated alerts by `type + entity_id + date`
- do not show cross-team notifications

## Acceptance Criteria

- critical alerts appear without manual refresh
- user can mark alert as read
- alerts are always scoped to same `team_id`
