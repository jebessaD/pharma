-- Platform-admin write access for the team lifecycle (trial, billing, suspension),
-- usable for a single team or in bulk, with a tamper-resistant audit trail.

-- Shared guard so every admin-only object checks membership the same way.
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_admins pa
    WHERE pa.auth_user_id = auth.uid()
      AND pa.is_active = true
  );
$$;

REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;

CREATE TABLE IF NOT EXISTS public.platform_admin_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  admin_email text,
  action text NOT NULL,
  team_id uuid REFERENCES public.teams (id) ON DELETE SET NULL,
  before_state jsonb,
  after_state jsonb,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS platform_admin_audit_admin_created_idx
  ON public.platform_admin_audit (admin_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS platform_admin_audit_team_created_idx
  ON public.platform_admin_audit (team_id, created_at DESC);

ALTER TABLE public.platform_admin_audit ENABLE ROW LEVEL SECURITY;

-- Admins may read the trail. Nobody may write it directly: rows are only inserted
-- by the SECURITY DEFINER function below, so an admin cannot erase their own tracks.
DROP POLICY IF EXISTS platform_admin_audit_select_admin ON public.platform_admin_audit;
CREATE POLICY platform_admin_audit_select_admin
  ON public.platform_admin_audit FOR SELECT TO authenticated
  USING (public.is_platform_admin());

DROP POLICY IF EXISTS platform_admin_audit_service_all ON public.platform_admin_audit;
CREATE POLICY platform_admin_audit_service_all
  ON public.platform_admin_audit FOR ALL TO service_role
  USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.superadmin_update_teams(
  p_team_ids uuid[],
  p_action text,
  p_days integer DEFAULT NULL,
  p_until timestamptz DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_email text;
  v_action text := lower(trim(coalesce(p_action, '')));
  v_reason text := nullif(left(trim(coalesce(p_reason, '')), 500), '');
  v_ids uuid[];
  v_requested integer;
  v_updated integer := 0;
  v_recent integer;
  r record;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_action NOT IN (
    'suspend', 'activate',
    'extend_trial', 'set_trial_end',
    'start_grace', 'mark_paid', 'mark_past_due', 'mark_churned', 'suspend_billing'
  ) THEN
    RAISE EXCEPTION 'invalid_action';
  END IF;

  SELECT array_agg(DISTINCT t)
  INTO v_ids
  FROM unnest(coalesce(p_team_ids, '{}'::uuid[])) AS t
  WHERE t IS NOT NULL;

  v_requested := coalesce(array_length(v_ids, 1), 0);

  IF v_requested = 0 THEN
    RAISE EXCEPTION 'no_teams_selected';
  END IF;
  IF v_requested > 200 THEN
    RAISE EXCEPTION 'too_many_teams';
  END IF;

  -- Cheap throttle: a compromised admin session cannot churn the whole platform in a loop.
  SELECT count(*)
  INTO v_recent
  FROM public.platform_admin_audit
  WHERE admin_user_id = v_admin
    AND created_at > now() - interval '1 minute';

  IF v_recent > 1000 THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  IF v_action IN ('extend_trial', 'start_grace') THEN
    IF p_days IS NULL OR p_days < 1 OR p_days > 3650 THEN
      RAISE EXCEPTION 'invalid_days';
    END IF;
  END IF;

  IF v_action = 'set_trial_end' THEN
    IF p_until IS NULL OR p_until > now() + interval '10 years' THEN
      RAISE EXCEPTION 'invalid_date';
    END IF;
  END IF;

  SELECT u.email INTO v_email FROM auth.users u WHERE u.id = v_admin;

  FOR r IN
    SELECT t.id, t.status, t.billing_status, t.trial_ends_at, t.billing_grace_ends_at
    FROM public.teams t
    WHERE t.id = ANY (v_ids)
    ORDER BY t.id
    FOR UPDATE
  LOOP
    CASE v_action
      WHEN 'suspend' THEN
        UPDATE public.teams SET status = 'suspended' WHERE id = r.id;
      WHEN 'activate' THEN
        UPDATE public.teams SET status = 'active' WHERE id = r.id;
      WHEN 'extend_trial' THEN
        UPDATE public.teams
        SET billing_status = 'trial',
            trial_ends_at = greatest(coalesce(r.trial_ends_at, now()), now())
                            + make_interval(days => p_days)
        WHERE id = r.id;
      WHEN 'set_trial_end' THEN
        UPDATE public.teams
        SET billing_status = 'trial', trial_ends_at = p_until
        WHERE id = r.id;
      WHEN 'start_grace' THEN
        UPDATE public.teams
        SET billing_status = 'grace',
            billing_grace_ends_at = now() + make_interval(days => p_days)
        WHERE id = r.id;
      WHEN 'mark_paid' THEN
        UPDATE public.teams SET billing_status = 'active' WHERE id = r.id;
      WHEN 'mark_past_due' THEN
        UPDATE public.teams SET billing_status = 'past_due' WHERE id = r.id;
      WHEN 'mark_churned' THEN
        UPDATE public.teams SET billing_status = 'churned' WHERE id = r.id;
      WHEN 'suspend_billing' THEN
        UPDATE public.teams SET billing_status = 'suspended_billing' WHERE id = r.id;
    END CASE;

    v_updated := v_updated + 1;

    INSERT INTO public.platform_admin_audit (
      admin_user_id, admin_email, action, team_id, before_state, after_state, reason
    )
    SELECT
      v_admin,
      v_email,
      v_action,
      r.id,
      jsonb_build_object(
        'status', r.status,
        'billing_status', r.billing_status,
        'trial_ends_at', r.trial_ends_at,
        'billing_grace_ends_at', r.billing_grace_ends_at
      ),
      jsonb_build_object(
        'status', t.status,
        'billing_status', t.billing_status,
        'trial_ends_at', t.trial_ends_at,
        'billing_grace_ends_at', t.billing_grace_ends_at
      ),
      v_reason
    FROM public.teams t
    WHERE t.id = r.id;
  END LOOP;

  RETURN jsonb_build_object(
    'action', v_action,
    'requested', v_requested,
    'updated', v_updated
  );
END;
$$;

REVOKE ALL ON FUNCTION public.superadmin_update_teams(uuid[], text, integer, timestamptz, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.superadmin_update_teams(uuid[], text, integer, timestamptz, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_team_audit(
  p_team_id uuid,
  p_limit integer DEFAULT 25
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 200);
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
    FROM (
      SELECT
        a.id,
        a.created_at,
        a.action,
        a.admin_email,
        a.reason,
        a.before_state,
        a.after_state
      FROM public.platform_admin_audit a
      WHERE a.team_id = p_team_id
      ORDER BY a.created_at DESC
      LIMIT v_limit
    ) x
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.superadmin_team_audit(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.superadmin_team_audit(uuid, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
