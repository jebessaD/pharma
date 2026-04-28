# 02 - Team Organization (version 1)

## Version 1 scope (build now)

- edit pharmacy profile (name, phone, address, license no)
- create branches
- list branches

## Out of Scope (Do Not Build)

- branding system and advanced organization settings
- full business metadata validation workflows

## AI Implementation Directive

- Flutter screens: `TeamProfile`, `BranchList`, `CreateBranch`
- Supabase tables: `teams`, `team_profiles`, `branches`
- All business tables must include `team_id`
- Apply RLS by `team_id` for isolation

## Supabase Table Detail

`team_profiles`
- `id` uuid pk
- `team_id` uuid fk -> `teams.id`
- `pharmacy_name` text
- `phone` text
- `address` text
- `license_number` text
- `updated_at` timestamptz

`branches`
- `id` uuid pk
- `team_id` uuid fk
- `name` text
- `code` text
- `address` text
- `is_active` boolean default true
- `created_at` timestamptz

## Core Flow

1. admin updates pharmacy profile
2. admin creates branch
3. branch appears in dropdown selectors across app

## Validation Rules

- branch `code` unique per team
- cannot delete a branch with existing sales/stock data
- profile fields must reject empty pharmacy name

## Acceptance Criteria

- one team cannot read/write another team data
- admin can create at least one branch
- profile update is persisted and visible after refresh
