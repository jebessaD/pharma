-- Drop the legacy 2-argument overload so PostgREST schema cache
-- resolves `dashboard_metrics` unambiguously to the 3-arg version
-- (p_team_id uuid, p_branch_id uuid, p_category_ids uuid[] DEFAULT NULL).
DROP FUNCTION IF EXISTS public.dashboard_metrics(uuid, uuid);
