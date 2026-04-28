-- Break infinite RLS recursion on profiles: policies must not SELECT profiles
-- directly. Use SECURITY DEFINER helpers (bypass RLS) for the caller's row.

CREATE OR REPLACE FUNCTION public.current_profile_team_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT team_id
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.current_profile_team_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_profile_team_id() TO authenticated;

CREATE OR REPLACE FUNCTION public.current_profile_is_active_admin_for_team(p_team_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND team_id = p_team_id
      AND role = 'admin'
      AND is_active = true
  );
$$;

REVOKE ALL ON FUNCTION public.current_profile_is_active_admin_for_team(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_profile_is_active_admin_for_team(uuid) TO authenticated;

DROP POLICY IF EXISTS profiles_select_team ON public.profiles;
CREATE POLICY profiles_select_team
  ON public.profiles FOR SELECT TO authenticated
  USING (team_id = public.current_profile_team_id());

DROP POLICY IF EXISTS profiles_mutate_team_admin ON public.profiles;
CREATE POLICY profiles_mutate_team_admin
  ON public.profiles FOR UPDATE TO authenticated
  USING (public.current_profile_is_active_admin_for_team(profiles.team_id))
  WITH CHECK (public.current_profile_is_active_admin_for_team(profiles.team_id));
