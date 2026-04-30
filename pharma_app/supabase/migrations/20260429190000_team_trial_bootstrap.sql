-- Trial window + one-shot owner signup bootstrap (no platform admin required).

ALTER TABLE public.teams
  ADD COLUMN IF NOT EXISTS trial_ends_at timestamptz;

UPDATE public.teams
SET trial_ends_at = coalesce(
  trial_ends_at,
  (created_at AT TIME ZONE 'UTC') + interval '30 days'
)
WHERE trial_ends_at IS NULL;

CREATE OR REPLACE FUNCTION public.bootstrap_owner_team(
  p_team_name text,
  p_full_name text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  v_branch_id uuid;
  v_name text := trim(p_team_name);
  v_fn text := trim(p_full_name);
BEGIN
  IF length(v_name) < 2 THEN
    RAISE EXCEPTION 'invalid_team_name';
  END IF;
  IF length(v_fn) < 1 THEN
    RAISE EXCEPTION 'invalid_full_name';
  END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'profile_exists';
  END IF;

  INSERT INTO public.teams (name, status, created_by, trial_ends_at)
  VALUES (v_name, 'active', auth.uid(), (now() AT TIME ZONE 'utc') + interval '30 days')
  RETURNING id INTO v_team_id;

  INSERT INTO public.branches (team_id, name, code)
  VALUES (v_team_id, 'Main', 'MAIN')
  RETURNING id INTO v_branch_id;

  INSERT INTO public.profiles (id, team_id, branch_id, full_name, role, is_active)
  VALUES (auth.uid(), v_team_id, v_branch_id, v_fn, 'admin', true);

  INSERT INTO public.team_profiles (team_id, pharmacy_name)
  VALUES (v_team_id, v_name);

  RETURN v_team_id;
END;
$$;

REVOKE ALL ON FUNCTION public.bootstrap_owner_team(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bootstrap_owner_team(text, text) TO authenticated;
