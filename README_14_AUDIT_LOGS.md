# 14 - Audit Logs (version 1)

## Version 1 scope (build now)

- log critical actions:
  - sale created
  - stock adjusted
  - price updated

## Out of Scope (Do Not Build)

- full audit for every minor read operation
- complex diff viewer for JSON before/after

## AI Implementation Directive

- Supabase table: `activity_logs`
- Required fields: `team_id`, `branch_id`, `user_id`, `action_type`, `entity_id`, `created_at`
- Optional JSON payload: `meta`
- Write audit row in same transaction when possible

## Supabase Table Detail

`activity_logs`
- `id` uuid pk
- `team_id` uuid fk
- `branch_id` uuid fk nullable
- `user_id` uuid fk
- `action_type` text
- `entity_type` text
- `entity_id` uuid
- `meta` jsonb
- `created_at` timestamptz

## Action Naming Convention

- `sale.created`
- `stock.adjusted`
- `medicine.price_updated`
- `user.role_changed`

## Validation Rules

- never allow client to spoof `team_id`/`user_id`
- derive actor from auth context on server/RPC

## Acceptance Criteria

- admin can filter logs by date and user
- every stock adjustment has an audit entry
- team isolation is enforced by RLS
