-- Fix bootstrap_owner_team: new signups get role='owner' (not 'admin').
CREATE OR REPLACE FUNCTION public.bootstrap_owner_team(p_team_name text, p_full_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
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
  VALUES (auth.uid(), v_team_id, v_branch_id, v_fn, 'owner', true);

  INSERT INTO public.team_profiles (team_id, pharmacy_name)
  VALUES (v_team_id, v_name);

  RETURN v_team_id;
END;
$$;
