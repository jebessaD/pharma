# Branch-Scoped Medicines Rollout Checklist

## Migration Order
- Apply `20260430173000_branch_scoped_medicines_and_duplication.sql`.
- Verify no `public.medicines` rows have null `branch_id`.
- Verify branch-scoped unique indexes exist.
- Deploy app changes that enforce `branch_id` filtering in medicine and notification reads.

## Database Verification Queries
- `select count(*) from public.medicines where branch_id is null;`
- `select indexname from pg_indexes where schemaname='public' and tablename='medicines' and indexname='idx_medicines_team_branch_manual_unique';`
- `select indexname from pg_indexes where schemaname='public' and tablename='medicines' and indexname='idx_medicines_team_branch_barcode_unique';`
- `select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='duplicate_branch_medicines';`

## Functional Verification
- Branch A medicine list only shows Branch A catalog entries.
- Branch B medicine list only shows Branch B catalog entries.
- Medicine detail page only loads batches for selected branch.
- POS search, stock-in lookup, and stock-adjust medicine pickers return current branch medicines only.
- Notifications page shows global alerts plus selected-branch alerts only.

## Duplication Verification (Catalog Only)
- Create new branch from Organization hub with "Copy medicines from another branch" enabled.
- Confirm success toast appears.
- Confirm target branch contains missing medicines from source branch.
- Confirm existing target medicines are not overwritten.
- Confirm no stock balances or batches are created by duplication.

## Regression Checks
- Stock-in and stock-adjust operations still save correctly.
- POS checkout and receipt flow still complete.
- Purchase draft + receive still work.
- Reports and dashboard still load with selected branch.
