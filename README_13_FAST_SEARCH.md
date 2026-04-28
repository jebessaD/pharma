# 13 - Fast Search (version 1)

## Version 1 scope (build now)

- quick medicine search in POS
- search by medicine name, generic name, manual code

## Out of Scope (Do Not Build)

- fuzzy AI search
- heavy advanced filter builder

## AI Implementation Directive

- Flutter widgets: shared `MedicineSearchBar` + POS suggestions list
- Supabase indexed columns: `name`, `generic_name`, `manual_code`
- Normalize query to lowercase
- Limit result size for speed (example: top 20)

## SQL Index Guidance

- btree index on `lower(name)`
- btree index on `lower(generic_name)`
- btree index on `lower(manual_code)`

## Search Ranking (Simple)

1. exact manual code
2. prefix match on name
3. contains match on generic name

## Validation Rules

- ignore leading/trailing spaces in query
- return only active medicines with sellable stock for POS mode

## Acceptance Criteria

- search results appear quickly during typing
- no barcode required for successful lookup
- top result is usable to add item to cart directly
