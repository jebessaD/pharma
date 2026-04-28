# 08 - Purchases (version 1)

## Version 1 scope (build now)

- supplier CRUD (basic)
- record purchase and purchase items
- receive goods into stock

## Out of Scope (Do Not Build)

- purchase approval chains
- supplier credit reconciliation workflows

## AI Implementation Directive

- Flutter screens: `SupplierList`, `CreatePurchase`, `ReceiveGoods`
- Supabase tables: `suppliers`, `purchases`, `purchase_items`
- Optional field: `invoice_reference` (text)
- On receive goods, create stock movement `purchase_in`

## Supabase Table Detail

`suppliers`
- `id` uuid pk
- `team_id` uuid fk
- `name` text
- `phone` text nullable
- `address` text nullable
- `is_active` boolean default true

`purchases`
- `id` uuid pk
- `team_id` uuid fk
- `branch_id` uuid fk
- `supplier_id` uuid fk
- `invoice_reference` text nullable
- `status` text (`draft`,`received`)
- `created_by` uuid
- `created_at` timestamptz

`purchase_items`
- `id` uuid pk
- `purchase_id` uuid fk
- `medicine_id` uuid fk
- `batch_no` text
- `expiry_date` date
- `qty_base_unit` numeric
- `unit_cost` numeric(12,2)

## Validation Rules

- cannot mark purchase `received` with empty items
- receiving a purchase updates stock balances atomically
- duplicate invoice refs allowed but should be searchable

## Acceptance Criteria

- received purchase increases stock balances correctly
- purchase history is filterable by supplier/date
- all purchases are scoped by `team_id`
