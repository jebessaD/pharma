-- Branch-scoped staff: helper functions for enforcing branch access.

-- Caller's assigned branch (NULL if unset or inactive).
CREATE OR REPLACE FUNCTION public.current_profile_branch_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT branch_id
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.current_profile_branch_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_profile_branch_id() TO authenticated;

-- Caller's role (NULL if no active profile).
CREATE OR REPLACE FUNCTION public.current_profile_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.current_profile_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_profile_role() TO authenticated;

-- Guard: owner/admin may access any branch; others must match profiles.branch_id.
-- Raises 'branch_access_denied' on mismatch.
CREATE OR REPLACE FUNCTION public.assert_branch_access(p_branch_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role   text;
  v_branch uuid;
BEGIN
  SELECT role, branch_id INTO v_role, v_branch
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true
  LIMIT 1;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  IF v_role IN ('owner', 'admin') THEN
    RETURN;
  END IF;

  IF v_branch IS NULL OR v_branch IS DISTINCT FROM p_branch_id THEN
    RAISE EXCEPTION 'branch_access_denied';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_branch_access(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_branch_access(uuid) TO authenticated;
