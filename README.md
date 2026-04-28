# Pharmacy Management SaaS (Ethiopia) — version 1 build docs

This repo defines a **Flutter + Supabase** app for Ethiopian pharmacy operations (version 1).

## Version 1 goal

Ship a usable first version fast:
- prevent expiry loss
- speed up sales
- improve stock control

## Core Stack

- App: Flutter
- Backend/Auth/DB: Supabase
- Architecture: simple modules, clear ownership, strict version 1 limits

## AI Working Rule

When an AI agent works on this repo, it must:
- follow the version 1 scope in each section file
- not add out-of-scope ERP features
- implement smallest working version first
- add tests for critical flows only

## Global Engineering Standards

- Multi-tenant rule: every business row includes `team_id`
- Branch-aware rule: operational rows include `branch_id`
- Security rule: enforce Supabase RLS for all tenant tables
- Audit rule: write activity logs for critical mutations
- Performance rule: add indexes for POS search and dashboard filters

## Suggested Supabase Core Tables

- `teams`
- `team_profiles`
- `branches`
- `profiles` (app users linked to Supabase Auth)
- `medicines`
- `medicine_batches`
- `unit_conversions`
- `stock_balances`
- `stock_movements`
- `sales`
- `sale_items`
- `payments`
- `suppliers`
- `purchases`
- `purchase_items`
- `notifications`
- `activity_logs`

## Suggested Build Order

1. Auth + profiles + roles + RLS baseline
2. Team/branch setup
3. Medicines + batch + conversion
4. Inventory engine
5. POS sales
6. Expiry + alerts
7. Purchases
8. Dashboard + reports + audit views

## Definition of version 1 done

- pharmacy can setup team/branch/users
- medicines can be stocked, searched, and sold by unit
- expired medicine cannot be sold
- stock is always traceable by movement history
- core daily dashboard and reports are usable

## Section Files (AI Directives Included)

1. `README_01_PLATFORM_OWNER.md`
2. `README_02_TEAM_ORGANIZATION.md`
3. `README_03_USER_ROLES.md`
4. `README_04_MEDICINE_MANAGEMENT.md`
5. `README_05_INVENTORY.md`
6. `README_06_EXPIRY.md`
7. `README_07_SALES_POS.md`
8. `README_08_PURCHASES.md`
9. `README_09_MULTI_BRANCH.md`
10. `README_10_DASHBOARD.md`
11. `README_11_NOTIFICATIONS.md`
12. `README_12_REPORTS.md`
13. `README_13_FAST_SEARCH.md`
14. `README_14_AUDIT_LOGS.md`
15. `README_V1_BOUNDARIES.md`
16. `README_ROADMAP.md`
