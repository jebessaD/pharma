# 03 - User Roles (version 1)

## Version 1 scope (build now)

- create user
- assign one role
- disable/enable user

Roles for version 1:
- `admin`
- `pharmacist`
- `cashier`

## Out of Scope (Do Not Build)

- complex multi-role assignment per user
- granular permissions matrix UI

## AI Implementation Directive

- Flutter screens: `UserList`, `CreateUser`, `EditUser`
- Supabase: Auth users + `profiles` table with `team_id`, `branch_id`, `role`, `is_active`
- Restrict user management to `admin` role
- Never hard delete users

## Supabase Table Detail

`profiles`
- `id` uuid pk (same as auth user id)
- `team_id` uuid fk
- `branch_id` uuid fk nullable
- `full_name` text
- `role` text check in (`admin`,`pharmacist`,`cashier`)
- `is_active` boolean default true
- `created_at` timestamptz

## Access matrix (version 1)

- `admin`: users, medicines, inventory, purchases, reports
- `pharmacist`: POS, medicine search, stock view
- `cashier`: POS and receipt history only

## Validation Rules

- no duplicate email within same team
- disabled users cannot create/modify transactions
- role changes are logged to `activity_logs`

## Acceptance Criteria

- admin can add new user
- disabled user cannot login
- role controls menu visibility for critical actions
