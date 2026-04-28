# 04 - Medicine Management (version 1)

## Version 1 scope (build now)

- medicine catalog CRUD
- manual code support
- batch + expiry capture
- base unit + sell unit conversion

## Out of Scope (Do Not Build)

- advanced product taxonomy and regulatory datasets
- barcode dependency as required field

## AI Implementation Directive

- Flutter screens: `MedicineList`, `CreateMedicine`, `MedicineDetail`
- Supabase tables: `medicines`, `medicine_batches`, `unit_conversions`
- Minimum fields: name, generic_name, manual_code, purchase_price, selling_price
- Required on batch: `batch_no`, `expiry_date`, `quantity_in_base_unit`

## Supabase Table Detail

`medicines`
- `id` uuid pk
- `team_id` uuid fk
- `name` text
- `generic_name` text
- `manual_code` text
- `barcode` text nullable
- `category` text nullable
- `purchase_price` numeric(12,2)
- `selling_price` numeric(12,2)
- `reorder_level` numeric default 0
- `is_active` boolean default true

`unit_conversions`
- `id` uuid pk
- `team_id` uuid fk
- `medicine_id` uuid fk
- `from_unit` text
- `to_unit` text
- `multiplier` numeric

`medicine_batches`
- `id` uuid pk
- `team_id` uuid fk
- `branch_id` uuid fk
- `medicine_id` uuid fk
- `batch_no` text
- `expiry_date` date
- `quantity_in_base_unit` numeric

## Validation Rules

- unique `manual_code` per team
- `expiry_date` must be future date when receiving stock
- conversion multiplier must be > 0

## Acceptance Criteria

- user can sell by piece/strip/box using conversion
- medicine is searchable by name and manual code
- stock received without barcode is fully supported
