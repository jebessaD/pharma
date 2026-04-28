# 07 - Sales POS (version 1)

## Version 1 scope (build now)

- create sale
- add medicine by fast search
- choose sell unit (piece/strip/box)
- payment type: cash or bank transfer
- print/share simple receipt data

## Out of Scope (Do Not Build)

- credit sales workflow
- full return/refund management

## AI Implementation Directive

- Flutter screens: `POS`, `Checkout`, `Receipt`
- Supabase tables: `sales`, `sale_items`, `payments`
- Validate stock before confirming sale
- Deduct inventory in same transaction as sale insert

## Supabase Table Detail

`sales`
- `id` uuid pk
- `team_id` uuid fk
- `branch_id` uuid fk
- `sold_by` uuid fk (`profiles.id`)
- `subtotal` numeric(12,2)
- `discount_total` numeric(12,2)
- `grand_total` numeric(12,2)
- `created_at` timestamptz

`sale_items`
- `id` uuid pk
- `sale_id` uuid fk
- `medicine_batch_id` uuid fk
- `unit` text
- `qty` numeric
- `unit_price` numeric(12,2)
- `line_total` numeric(12,2)

`payments`
- `id` uuid pk
- `sale_id` uuid fk
- `method` text (`cash`,`bank_transfer`)
- `amount` numeric(12,2)
- `reference_no` text nullable

## POS UX Rules

- keyboard-first flow for speed
- search and add item in <= 2 taps after typing
- clear stock/expiry error messages

## Acceptance Criteria

- cashier can complete sale in under 30 seconds for common flow
- insufficient stock blocks checkout with clear message
- each sale stores cashier id, branch id, payment type, total
