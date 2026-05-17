-- Manual medicine codes are optional at catalog level (unique when provided).

ALTER TABLE public.medicines
  ALTER COLUMN manual_code DROP NOT NULL;

COMMENT ON COLUMN public.medicines.manual_code IS
  'Optional team/branch-scoped product code; unique per (team_id, branch_id) when set.';
