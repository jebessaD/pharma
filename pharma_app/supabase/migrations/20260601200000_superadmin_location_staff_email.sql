-- Extend superadmin dashboard payload with registration location and staff email.

CREATE OR REPLACE FUNCTION public.superadmin_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.platform_admins pa
    WHERE pa.auth_user_id = auth.uid()
      AND pa.is_active = true
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN jsonb_build_object(
    'teams', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC)
      FROM (
        SELECT
          id,
          name,
          status,
          created_at,
          trial_ends_at,
          billing_status,
          billing_grace_ends_at,
          registration_country_code,
          registration_country_name,
          registration_region,
          registration_city
        FROM public.teams
        LIMIT 10000
      ) t
    ), '[]'::jsonb),
    'teamProfiles', coalesce((
      SELECT jsonb_agg(to_jsonb(tp))
      FROM (
        SELECT team_id, pharmacy_name, phone, address, license_number
        FROM public.team_profiles
        LIMIT 10000
      ) tp
    ), '[]'::jsonb),
    'branches', coalesce((
      SELECT jsonb_agg(to_jsonb(b))
      FROM (
        SELECT id, team_id, name, code, is_active, created_at
        FROM public.branches
        LIMIT 10000
      ) b
    ), '[]'::jsonb),
    'profiles', coalesce((
      SELECT jsonb_agg(to_jsonb(p))
      FROM (
        SELECT
          p.id,
          p.team_id,
          p.branch_id,
          p.full_name,
          p.username,
          au.email,
          p.role,
          p.is_active
        FROM public.profiles p
        LEFT JOIN auth.users au ON au.id = p.id
        LIMIT 10000
      ) p
    ), '[]'::jsonb),
    'medicines', coalesce((
      SELECT jsonb_agg(to_jsonb(m))
      FROM (
        SELECT id, team_id, branch_id, name, purchase_price, reorder_level, is_active
        FROM public.medicines
        LIMIT 10000
      ) m
    ), '[]'::jsonb),
    'batches', coalesce((
      SELECT jsonb_agg(to_jsonb(mb))
      FROM (
        SELECT id, team_id, branch_id, medicine_id, expiry_date, quantity_in_base_unit, unit_cost_base
        FROM public.medicine_batches
        LIMIT 10000
      ) mb
    ), '[]'::jsonb),
    'stockBalances', coalesce((
      SELECT jsonb_agg(to_jsonb(sb))
      FROM (
        SELECT team_id, branch_id, medicine_batch_id, qty_base_unit, updated_at
        FROM public.stock_balances
        LIMIT 10000
      ) sb
    ), '[]'::jsonb),
    'stockMovements', coalesce((
      SELECT jsonb_agg(to_jsonb(sm))
      FROM (
        SELECT team_id, branch_id, medicine_batch_id, movement_type, qty_change_base_unit, created_at
        FROM public.stock_movements
        LIMIT 10000
      ) sm
    ), '[]'::jsonb),
    'sales', coalesce((
      SELECT jsonb_agg(to_jsonb(s))
      FROM (
        SELECT id, team_id, branch_id, grand_total, gross_profit, created_at
        FROM public.sales
        LIMIT 10000
      ) s
    ), '[]'::jsonb),
    'notifications', coalesce((
      SELECT jsonb_agg(to_jsonb(n))
      FROM (
        SELECT team_id, is_read, type, created_at
        FROM public.notifications
        LIMIT 10000
      ) n
    ), '[]'::jsonb),
    'activityLogs', coalesce((
      SELECT jsonb_agg(to_jsonb(a))
      FROM (
        SELECT team_id, created_at
        FROM public.activity_logs
        LIMIT 10000
      ) a
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.superadmin_dashboard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.superadmin_dashboard() TO authenticated;

NOTIFY pgrst, 'reload schema';
