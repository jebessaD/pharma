-- Per-team drill-down for the superadmin dashboard: staff, catalog, sales mix,
-- stock concentration, and inventory risk for a single tenant.

CREATE OR REPLACE FUNCTION public.superadmin_team_detail(p_team_id uuid)
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
    'team', (
      SELECT to_jsonb(x)
      FROM (
        SELECT
          t.id,
          t.name,
          t.status,
          t.created_at,
          t.trial_ends_at,
          t.billing_status,
          t.billing_grace_ends_at,
          t.registration_country_name,
          t.registration_country_code,
          t.registration_region,
          t.registration_city,
          tp.pharmacy_name,
          tp.phone,
          tp.address,
          tp.license_number
        FROM public.teams t
        LEFT JOIN public.team_profiles tp ON tp.team_id = t.id
        WHERE t.id = p_team_id
      ) x
    ),
    'branches', coalesce((
      SELECT jsonb_agg(to_jsonb(b) ORDER BY b.name)
      FROM (
        SELECT
          br.id,
          br.name,
          br.code,
          br.address,
          br.is_active,
          br.created_at,
          (SELECT count(*) FROM public.profiles p WHERE p.branch_id = br.id) AS staff_count,
          (SELECT count(*) FROM public.sales s WHERE s.branch_id = br.id) AS sale_count,
          (SELECT coalesce(sum(s.grand_total), 0) FROM public.sales s WHERE s.branch_id = br.id) AS sales_total
        FROM public.branches br
        WHERE br.team_id = p_team_id
      ) b
    ), '[]'::jsonb),
    'staff', coalesce((
      SELECT jsonb_agg(to_jsonb(s) ORDER BY s.sales_total DESC, s.full_name)
      FROM (
        SELECT
          p.id,
          p.full_name,
          p.username,
          au.email,
          p.role,
          p.is_active,
          p.created_at,
          au.last_sign_in_at,
          br.name AS branch_name,
          (SELECT count(*) FROM public.sales sa WHERE sa.sold_by = p.id) AS sale_count,
          (SELECT coalesce(sum(sa.grand_total), 0) FROM public.sales sa WHERE sa.sold_by = p.id) AS sales_total
        FROM public.profiles p
        LEFT JOIN auth.users au ON au.id = p.id
        LEFT JOIN public.branches br ON br.id = p.branch_id
        WHERE p.team_id = p_team_id
      ) s
    ), '[]'::jsonb),
    'medicines', coalesce((
      SELECT jsonb_agg(to_jsonb(m))
      FROM (
        SELECT
          me.id,
          me.name,
          me.generic_name,
          me.category_key,
          me.strength,
          me.dosage_form,
          me.purchase_price,
          me.selling_price,
          me.reorder_level,
          me.is_active,
          me.created_at,
          coalesce((
            SELECT sum(sb.qty_base_unit)
            FROM public.stock_balances sb
            JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
            WHERE mb.medicine_id = me.id
          ), 0) AS stock_qty
        FROM public.medicines me
        WHERE me.team_id = p_team_id
        ORDER BY me.created_at DESC NULLS LAST
        LIMIT 300
      ) m
    ), '[]'::jsonb),
    'topSelling', coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.revenue DESC)
      FROM (
        SELECT
          coalesce(me.name, 'Unknown medicine') AS name,
          me.generic_name,
          sum(si.qty) AS qty_sold,
          sum(si.line_total) AS revenue,
          sum(coalesce(si.line_profit, 0)) AS profit
        FROM public.sale_items si
        JOIN public.sales sa ON sa.id = si.sale_id
        LEFT JOIN public.medicines me ON me.id = si.medicine_id
        WHERE sa.team_id = p_team_id
        GROUP BY me.name, me.generic_name
        ORDER BY sum(si.line_total) DESC
        LIMIT 20
      ) x
    ), '[]'::jsonb),
    'topStock', coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.stock_value DESC)
      FROM (
        SELECT
          me.name,
          me.generic_name,
          sum(sb.qty_base_unit) AS qty,
          sum(sb.qty_base_unit * coalesce(mb.unit_cost_base, me.purchase_price, 0)) AS stock_value
        FROM public.stock_balances sb
        JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
        JOIN public.medicines me ON me.id = mb.medicine_id
        WHERE sb.team_id = p_team_id
          AND sb.qty_base_unit > 0
        GROUP BY me.name, me.generic_name
        ORDER BY sum(sb.qty_base_unit * coalesce(mb.unit_cost_base, me.purchase_price, 0)) DESC
        LIMIT 20
      ) x
    ), '[]'::jsonb),
    'lowStock', coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.qty)
      FROM (
        SELECT
          me.name,
          me.generic_name,
          me.reorder_level,
          sum(sb.qty_base_unit) AS qty
        FROM public.stock_balances sb
        JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
        JOIN public.medicines me ON me.id = mb.medicine_id
        WHERE sb.team_id = p_team_id
          AND me.is_active IS NOT FALSE
        GROUP BY me.id, me.name, me.generic_name, me.reorder_level
        HAVING sum(sb.qty_base_unit) <= coalesce(me.reorder_level, 0)
        ORDER BY sum(sb.qty_base_unit)
        LIMIT 25
      ) x
    ), '[]'::jsonb),
    'expiryRisk', coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.expiry_date)
      FROM (
        SELECT
          me.name,
          mb.batch_no,
          mb.expiry_date,
          coalesce(sb.qty_base_unit, mb.quantity_in_base_unit, 0) AS qty,
          coalesce(mb.unit_cost_base, me.purchase_price, 0) AS unit_cost
        FROM public.medicine_batches mb
        JOIN public.medicines me ON me.id = mb.medicine_id
        LEFT JOIN public.stock_balances sb ON sb.medicine_batch_id = mb.id
        WHERE mb.team_id = p_team_id
          AND mb.expiry_date IS NOT NULL
          AND coalesce(sb.qty_base_unit, mb.quantity_in_base_unit, 0) > 0
          AND mb.expiry_date <= CURRENT_DATE + INTERVAL '90 days'
        ORDER BY mb.expiry_date
        LIMIT 25
      ) x
    ), '[]'::jsonb),
    'recentSales', coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT
          sa.id,
          sa.created_at,
          sa.grand_total,
          sa.gross_profit,
          coalesce(p.full_name, p.username, 'Unknown') AS seller,
          br.name AS branch_name,
          (SELECT count(*) FROM public.sale_items si WHERE si.sale_id = sa.id) AS item_count,
          (SELECT string_agg(DISTINCT pay.method, ', ') FROM public.payments pay WHERE pay.sale_id = sa.id) AS payment_methods
        FROM public.sales sa
        LEFT JOIN public.profiles p ON p.id = sa.sold_by
        LEFT JOIN public.branches br ON br.id = sa.branch_id
        WHERE sa.team_id = p_team_id
        ORDER BY sa.created_at DESC
        LIMIT 25
      ) x
    ), '[]'::jsonb),
    'suppliers', coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.name)
      FROM (
        SELECT
          su.name,
          su.phone,
          su.is_active,
          (SELECT count(*) FROM public.purchases pu WHERE pu.supplier_id = su.id) AS purchase_count
        FROM public.suppliers su
        WHERE su.team_id = p_team_id
        LIMIT 50
      ) x
    ), '[]'::jsonb),
    'salesDaily', coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.day)
      FROM (
        SELECT
          (sa.created_at)::date AS day,
          count(*) AS sale_count,
          sum(sa.grand_total) AS total
        FROM public.sales sa
        WHERE sa.team_id = p_team_id
          AND sa.created_at >= now() - INTERVAL '30 days'
        GROUP BY (sa.created_at)::date
      ) x
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.superadmin_team_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.superadmin_team_detail(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
