ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('owner', 'admin', 'pharmacist', 'cashier', 'seller'));

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
      AND role IN ('owner', 'admin')
      AND is_active = true
  );
$$;

REVOKE ALL ON FUNCTION public.current_profile_is_active_admin_for_team(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_profile_is_active_admin_for_team(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.current_profile_can_manage_profile(
  p_target_team_id uuid,
  p_target_role text,
  p_target_user_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles me
    WHERE me.id = auth.uid()
      AND me.is_active = true
      AND me.team_id = p_target_team_id
      AND p_target_user_id IS DISTINCT FROM me.id
      AND (
        me.role = 'owner'
        OR (me.role = 'admin' AND p_target_role NOT IN ('owner', 'admin'))
      )
  );
$$;

REVOKE ALL ON FUNCTION public.current_profile_can_manage_profile(uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_profile_can_manage_profile(uuid, text, uuid) TO authenticated;

DROP POLICY IF EXISTS profiles_mutate_team_admin ON public.profiles;
CREATE POLICY profiles_mutate_team_admin
  ON public.profiles FOR UPDATE TO authenticated
  USING (
    public.current_profile_can_manage_profile(
      profiles.team_id,
      profiles.role,
      profiles.id
    )
  )
  WITH CHECK (
    public.current_profile_can_manage_profile(
      profiles.team_id,
      profiles.role,
      profiles.id
    )
  );

DROP POLICY IF EXISTS team_profiles_update_admin ON public.team_profiles;
CREATE POLICY team_profiles_update_admin
  ON public.team_profiles FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.team_id = team_profiles.team_id
        AND p.role IN ('owner', 'admin')
        AND p.is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.team_id = team_profiles.team_id
        AND p.role IN ('owner', 'admin')
        AND p.is_active = true
    )
  );

DROP POLICY IF EXISTS team_profiles_insert_admin ON public.team_profiles;
CREATE POLICY team_profiles_insert_admin
  ON public.team_profiles FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.team_id = team_profiles.team_id
        AND p.role IN ('owner', 'admin')
        AND p.is_active = true
    )
  );

DROP POLICY IF EXISTS branches_mutate_admin ON public.branches;
CREATE POLICY branches_mutate_admin
  ON public.branches FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.team_id = branches.team_id
        AND p.role IN ('owner', 'admin')
        AND p.is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.team_id = branches.team_id
        AND p.role IN ('owner', 'admin')
        AND p.is_active = true
    )
  );

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
  VALUES (auth.uid(), v_team_id, v_branch_id, v_fn, 'owner', true);

  INSERT INTO public.team_profiles (team_id, pharmacy_name)
  VALUES (v_team_id, v_name);

  RETURN v_team_id;
END;
$$;

REVOKE ALL ON FUNCTION public.bootstrap_owner_team(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bootstrap_owner_team(text, text) TO authenticated;
