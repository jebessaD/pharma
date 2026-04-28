# 05 - Inventory (version 1)

## Version 1 scope (build now)

- stock in
- stock out (from sales)
- stock adjustment
- low stock view

## Out of Scope (Do Not Build)

- multi-step approval for adjustments
- warehouse optimization logic

## AI Implementation Directive

- Flutter screens: `StockBalance`, `StockIn`, `StockAdjust`
- Supabase tables: `stock_balances`, `stock_movements`
- Every stock update must create one movement record
- Keep balance per `team_id + branch_id + medicine_batch_id`

## Supabase Table Detail

`stock_balances`
- `id` uuid pk
- `team_id` uuid fk
- `branch_id` uuid fk
- `medicine_batch_id` uuid fk
- `qty_base_unit` numeric
- `updated_at` timestamptz

`stock_movements`
- `id` uuid pk
- `team_id` uuid fk
- `branch_id` uuid fk
- `medicine_batch_id` uuid fk
- `movement_type` text (`purchase_in`,`sale_out`,`adjustment`)
- `qty_change_base_unit` numeric
- `reason` text nullable
- `reference_type` text nullable
- `reference_id` uuid nullable
- `created_by` uuid
- `created_at` timestamptz

## Transaction Rule

- use one DB transaction for movement insert + balance update
- reject operation if resulting balance < 0
- adjustments must include reason text

## Acceptance Criteria

- balance updates correctly after stock in/out/adjustment
- low stock list reflects reorder level
- movement history can be filtered by medicine and date
