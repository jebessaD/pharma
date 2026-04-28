# 01 - Platform Owner (version 1)

## Version 1 scope (build now)

- super admin login
- create pharmacy team
- view teams list
- activate/suspend team

## Out of Scope (Do Not Build)

- complex subscription billing logic
- invoices, tax billing, payment collection

## AI Implementation Directive

- Flutter screens: `AdminLogin`, `TeamList`, `CreateTeam`, `TeamDetail`
- Supabase tables: `platform_admins`, `teams`
- Keep `teams.status` enum: `active`, `suspended`
- Add RLS so only platform admins can manage `teams`

## Supabase Table Detail

`platform_admins`
- `id` uuid pk
- `auth_user_id` uuid unique
- `email` text unique
- `is_active` boolean default true
- `created_at` timestamptz

`teams`
- `id` uuid pk
- `name` text
- `status` text check in (`active`,`suspended`)
- `created_by` uuid
- `created_at` timestamptz

## Core Flow

1. platform admin signs in
2. creates team with `active` status
3. team appears in team list
4. admin can suspend/reactivate team

## Validation Rules

- team name required and unique
- only active platform admins can mutate team status
- suspended teams cannot access business APIs

## Acceptance Criteria

- admin can create a team
- suspended team users are blocked from app features
- active team users can continue normally
