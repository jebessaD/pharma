-- Team-scoped teams/branch visibility; platform_messages admin via service_role only;
-- apply_stock_movement requires active profile on team (no platform bypass).

-- ---------------------------------------------------------------------------
-- teams
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS teams_select_platform_admin ON public.teams;
DROP POLICY IF EXISTS teams_select_platform_or_member ON public.teams;
DROP POLICY IF EXISTS teams_select_member ON public.teams;

CREATE POLICY teams_select_member ON public.teams FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_active = true AND p.team_id = teams.id
    )
  );

DROP POLICY IF EXISTS teams_insert_platform_admin ON public.teams;
DROP POLICY IF EXISTS teams_update_platform_admin ON public.teams;
DROP POLICY IF EXISTS teams_delete_platform_admin ON public.teams;
DROP POLICY IF EXISTS teams_update_own_team_owner_admin ON public.teams;

CREATE POLICY teams_update_own_team_owner_admin ON public.teams FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = teams.id
        AND p.role IN ('owner', 'admin') AND p.is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = teams.id
        AND p.role IN ('owner', 'admin') AND p.is_active = true
    )
  );

-- ---------------------------------------------------------------------------
-- team_profiles + branches SELECT (remove cross-tenant platform read)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS team_profiles_select_team ON public.team_profiles;
CREATE POLICY team_profiles_select_team ON public.team_profiles FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = team_profiles.team_id
    )
  );

DROP POLICY IF EXISTS branches_select_team ON public.branches;
CREATE POLICY branches_select_team ON public.branches FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = branches.team_id
    )
  );

-- ---------------------------------------------------------------------------
-- platform_messages: authenticated cannot INSERT/UPDATE/DELETE; use Dashboard SQL.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS platform_messages_admin_all ON public.platform_messages;
DROP POLICY IF EXISTS platform_messages_admin_insert ON public.platform_messages;
DROP POLICY IF EXISTS platform_messages_admin_update ON public.platform_messages;
DROP POLICY IF EXISTS platform_messages_admin_delete ON public.platform_messages;
DROP POLICY IF EXISTS platform_messages_service_role_all ON public.platform_messages;

CREATE POLICY platform_messages_service_role_all ON public.platform_messages
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- apply_stock_movement: active team member only
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_stock_movement(
  p_team_id uuid,
  p_branch_id uuid,
  p_batch_id uuid,
  p_type text,
  p_qty numeric,
  p_reason text,
  p_ref_type text,
  p_ref_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND team_id = p_team_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  PERFORM public.assert_team_may_mutate(p_team_id);

  INSERT INTO public.stock_movements (
    team_id, branch_id, medicine_batch_id, movement_type,
    qty_change_base_unit, reason, reference_type, reference_id, created_by
  ) VALUES (
    p_team_id, p_branch_id, p_batch_id, p_type,
    p_qty, p_reason, p_ref_type, p_ref_id, auth.uid()
  );

  INSERT INTO public.stock_balances (team_id, branch_id, medicine_batch_id, qty_base_unit)
  VALUES (p_team_id, p_branch_id, p_batch_id, p_qty)
  ON CONFLICT (team_id, branch_id, medicine_batch_id)
  DO UPDATE SET
    qty_base_unit = public.stock_balances.qty_base_unit + EXCLUDED.qty_base_unit,
    updated_at = now();

  IF (
    SELECT qty_base_unit FROM public.stock_balances
    WHERE team_id = p_team_id AND branch_id = p_branch_id AND medicine_batch_id = p_batch_id
  ) < 0 THEN
    RAISE EXCEPTION 'insufficient_stock';
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
