ALTER TABLE public.teams
  ADD COLUMN IF NOT EXISTS registration_country_code text,
  ADD COLUMN IF NOT EXISTS registration_country_name text,
  ADD COLUMN IF NOT EXISTS registration_region text,
  ADD COLUMN IF NOT EXISTS registration_city text,
  ADD COLUMN IF NOT EXISTS registration_location_source text,
  ADD COLUMN IF NOT EXISTS registration_location_detected_at timestamptz;

ALTER TABLE public.teams
  DROP CONSTRAINT IF EXISTS teams_registration_location_source_check;

ALTER TABLE public.teams
  ADD CONSTRAINT teams_registration_location_source_check
  CHECK (
    registration_location_source IS NULL
    OR registration_location_source IN ('ip')
  );

COMMENT ON COLUMN public.teams.registration_country_code IS
  'Inferred ISO 3166-1 alpha-2 country code captured at registration.';
COMMENT ON COLUMN public.teams.registration_country_name IS
  'Inferred country name captured at registration.';
COMMENT ON COLUMN public.teams.registration_region IS
  'Inferred region/state captured at registration.';
COMMENT ON COLUMN public.teams.registration_city IS
  'Inferred city captured at registration; approximate and may be wrong.';
COMMENT ON COLUMN public.teams.registration_location_source IS
  'Source for inferred registration location metadata.';
COMMENT ON COLUMN public.teams.registration_location_detected_at IS
  'Time inferred registration location metadata was written.';

DROP FUNCTION IF EXISTS public.bootstrap_owner_team(text, text);

CREATE OR REPLACE FUNCTION public.bootstrap_owner_team(
  p_team_name text,
  p_full_name text,
  p_registration_country_code text DEFAULT NULL,
  p_registration_country_name text DEFAULT NULL,
  p_registration_region text DEFAULT NULL,
  p_registration_city text DEFAULT NULL,
  p_registration_location_source text DEFAULT NULL
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
  v_country_code text := upper(nullif(left(trim(coalesce(p_registration_country_code, '')), 2), ''));
  v_country_name text := nullif(left(trim(coalesce(p_registration_country_name, '')), 120), '');
  v_region text := nullif(left(trim(coalesce(p_registration_region, '')), 120), '');
  v_city text := nullif(left(trim(coalesce(p_registration_city, '')), 120), '');
  v_source text := lower(nullif(trim(coalesce(p_registration_location_source, '')), ''));
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

  IF v_country_code IS NOT NULL AND length(v_country_code) <> 2 THEN
    v_country_code := NULL;
  END IF;

  IF v_source IS DISTINCT FROM 'ip' THEN
    v_source := NULL;
  END IF;

  IF v_source IS NULL AND (
    v_country_code IS NOT NULL
    OR v_country_name IS NOT NULL
    OR v_region IS NOT NULL
    OR v_city IS NOT NULL
  ) THEN
    v_source := 'ip';
  END IF;

  INSERT INTO public.teams (
    name,
    status,
    created_by,
    trial_ends_at,
    registration_country_code,
    registration_country_name,
    registration_region,
    registration_city,
    registration_location_source,
    registration_location_detected_at
  )
  VALUES (
    v_name,
    'active',
    auth.uid(),
    (now() AT TIME ZONE 'utc') + interval '30 days',
    v_country_code,
    v_country_name,
    v_region,
    v_city,
    v_source,
    CASE WHEN v_source IS NOT NULL THEN now() ELSE NULL END
  )
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

REVOKE ALL ON FUNCTION public.bootstrap_owner_team(
  text,
  text,
  text,
  text,
  text,
  text,
  text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bootstrap_owner_team(
  text,
  text,
  text,
  text,
  text,
  text,
  text
) TO authenticated;
