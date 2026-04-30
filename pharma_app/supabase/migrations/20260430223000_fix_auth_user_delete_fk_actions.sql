-- Ensure auth user deletion does not fail when historical business rows exist.
-- Keep rows for audit/history by nulling user references on delete.

ALTER TABLE public.teams
  ALTER COLUMN created_by DROP NOT NULL;

ALTER TABLE public.stock_movements
  ALTER COLUMN created_by DROP NOT NULL;

ALTER TABLE public.purchases
  ALTER COLUMN created_by DROP NOT NULL;

ALTER TABLE public.activity_logs
  ALTER COLUMN user_id DROP NOT NULL;

ALTER TABLE public.sales
  ALTER COLUMN sold_by DROP NOT NULL;

ALTER TABLE public.teams
  DROP CONSTRAINT IF EXISTS teams_created_by_fkey;
ALTER TABLE public.teams
  ADD CONSTRAINT teams_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.stock_movements
  DROP CONSTRAINT IF EXISTS stock_movements_created_by_fkey;
ALTER TABLE public.stock_movements
  ADD CONSTRAINT stock_movements_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.purchases
  DROP CONSTRAINT IF EXISTS purchases_created_by_fkey;
ALTER TABLE public.purchases
  ADD CONSTRAINT purchases_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.activity_logs
  DROP CONSTRAINT IF EXISTS activity_logs_user_id_fkey;
ALTER TABLE public.activity_logs
  ADD CONSTRAINT activity_logs_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.sales
  DROP CONSTRAINT IF EXISTS sales_sold_by_fkey;
ALTER TABLE public.sales
  ADD CONSTRAINT sales_sold_by_fkey
  FOREIGN KEY (sold_by) REFERENCES auth.users(id) ON DELETE SET NULL;
