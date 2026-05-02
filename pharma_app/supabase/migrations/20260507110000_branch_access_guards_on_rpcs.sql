-- Add assert_branch_access() guard to every RPC that accepts p_branch_id.
-- For plpgsql functions: inject guard after BEGIN.
-- For SQL-language functions: wrap in plpgsql with guard + RETURN QUERY.

--------------------------------------------------------------------
-- 1. rpc_report_sales_unified  (was SQL → now plpgsql)
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_report_sales_unified(
  p_team_id uuid,
  p_branch_id uuid,
  p_from date,
  p_to date,
  p_sold_by uuid DEFAULT NULL,
  p_min_amount numeric DEFAULT NULL,
  p_max_amount numeric DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_overrides_only boolean DEFAULT false,
  p_category_ids uuid[] DEFAULT NULL
) RETURNS TABLE (
  sold_at timestamptz,
  sale_id uuid,
  seller_name text,
  medicine_name text,
  medicine_code text,
  qty numeric,
  unit_price numeric,
  line_total numeric,
  discount_total numeric,
  grand_total numeric,
  payment_method text,
  payment_reference text,
  override_reason text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_eff_sold_by uuid;
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid() AND is_active LIMIT 1;
  v_eff_sold_by := p_sold_by;
  IF v_role IN ('cashier', 'seller') THEN
    v_eff_sold_by := auth.uid();
  END IF;

  RETURN QUERY
  SELECT
    s.created_at AS sold_at,
    s.id AS sale_id,
    coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member') AS seller_name,
    coalesce(m.name, mbm.name, 'Unknown medicine') AS medicine_name,
    coalesce(m.manual_code, mbm.manual_code, '') AS medicine_code,
    si.qty,
    si.unit_price,
    si.line_total,
    s.discount_total,
    s.grand_total,
    pay.method AS payment_method,
    pay.reference_no AS payment_reference,
    si.price_override_reason AS override_reason
  FROM public.sales s
  JOIN public.sale_items si ON si.sale_id = s.id
  LEFT JOIN public.medicines m ON m.id = si.medicine_id
  LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
  LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
  LEFT JOIN public.profiles p ON p.id = s.sold_by AND p.team_id = p_team_id
  LEFT JOIN public.payments pay ON pay.sale_id = s.id
  WHERE s.team_id = p_team_id
    AND s.branch_id = p_branch_id
    AND s.created_at::date BETWEEN p_from AND p_to
    AND (v_eff_sold_by IS NULL OR s.sold_by = v_eff_sold_by)
    AND (p_min_amount IS NULL OR s.grand_total >= p_min_amount)
    AND (p_max_amount IS NULL OR s.grand_total <= p_max_amount)
    AND (p_payment_method IS NULL OR pay.method = p_payment_method)
    AND (NOT p_overrides_only OR si.price_override_reason IS NOT NULL)
    AND (
      p_category_ids IS NULL OR
      cardinality(p_category_ids) = 0 OR
      coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
    )
    AND EXISTS (
      SELECT 1 FROM public.profiles me
      WHERE me.id = auth.uid() AND me.team_id = p_team_id AND me.is_active
    )
  ORDER BY s.created_at DESC, s.id DESC, si.id ASC;
END;
$$;

--------------------------------------------------------------------
-- 2. rpc_report_stock_balance  (was SQL → now plpgsql)
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_report_stock_balance(
  p_team_id uuid,
  p_branch_id uuid,
  p_category_ids uuid[] DEFAULT NULL
) RETURNS TABLE (medicine_name text, batch_no text, qty numeric, expiry_date date)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  RETURN QUERY
  SELECT m.name, mb.batch_no, sb.qty_base_unit, mb.expiry_date
  FROM public.stock_balances sb
  JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id
    AND (
      p_category_ids IS NULL OR
      cardinality(p_category_ids) = 0 OR
      m.category_id = ANY(p_category_ids)
    )
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = p_team_id
    );
END;
$$;

--------------------------------------------------------------------
-- 3. rpc_report_expiry_status  (was SQL → now plpgsql)
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_report_expiry_status(
  p_team_id uuid,
  p_branch_id uuid,
  p_threshold_days int,
  p_category_ids uuid[] DEFAULT NULL
) RETURNS TABLE (medicine_name text, batch_no text, expiry_date date, days_left int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  RETURN QUERY
  SELECT m.name, mb.batch_no, mb.expiry_date,
    (mb.expiry_date - CURRENT_DATE)::int
  FROM public.medicine_batches mb
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
    AND mb.expiry_date <= CURRENT_DATE + (p_threshold_days || ' days')::interval
    AND (
      p_category_ids IS NULL OR
      cardinality(p_category_ids) = 0 OR
      m.category_id = ANY(p_category_ids)
    )
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = p_team_id
    );
END;
$$;

--------------------------------------------------------------------
-- 4. rpc_report_sales_by_staff  (was SQL → now plpgsql)
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_report_sales_by_staff(
  p_team_id uuid,
  p_branch_id uuid,
  p_from date,
  p_to date
) RETURNS TABLE (
  seller_name text,
  sale_count bigint,
  total_sales numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  RETURN QUERY
  SELECT
    coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member') AS seller_name,
    count(*)::bigint AS sale_count,
    sum(s.grand_total)::numeric(12, 2) AS total_sales
  FROM public.sales s
  LEFT JOIN public.profiles p ON p.id = s.sold_by AND p.team_id = p_team_id
  WHERE s.team_id = p_team_id
    AND s.branch_id = p_branch_id
    AND s.created_at::date BETWEEN p_from AND p_to
    AND EXISTS (SELECT 1 FROM public.profiles me WHERE me.id = auth.uid() AND me.team_id = p_team_id)
  GROUP BY coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member')
  ORDER BY total_sales DESC NULLS LAST, seller_name;
END;
$$;

--------------------------------------------------------------------
-- 5. rpc_report_profit_summary  (was SQL → now plpgsql)
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_report_profit_summary(
  p_team_id uuid,
  p_branch_id uuid,
  p_from date,
  p_to date
) RETURNS TABLE (
  revenue numeric,
  cogs numeric,
  gross_profit numeric,
  gross_margin_pct numeric,
  sale_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  RETURN QUERY
  WITH scoped_sales AS (
    SELECT s.*
    FROM public.sales s
    WHERE s.team_id = p_team_id
      AND s.branch_id = p_branch_id
      AND s.created_at::date BETWEEN p_from AND p_to
      AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = p_team_id AND p.is_active)
  ),
  agg AS (
    SELECT
      coalesce(sum(ss.grand_total), 0) AS revenue_sum,
      coalesce(sum(si.qty * si.cost_unit_at_sale), 0) AS cogs_sum,
      coalesce(sum(ss.gross_profit), 0) AS profit_sum,
      coalesce(count(DISTINCT ss.id), 0) AS sale_count_sum
    FROM scoped_sales ss
    LEFT JOIN public.sale_items si ON si.sale_id = ss.id
  )
  SELECT
    revenue_sum AS revenue,
    cogs_sum AS cogs,
    profit_sum AS gross_profit,
    CASE WHEN revenue_sum = 0 THEN 0 ELSE round((profit_sum / revenue_sum) * 100, 2) END AS gross_margin_pct,
    sale_count_sum AS sale_count
  FROM agg;
END;
$$;

--------------------------------------------------------------------
-- 6. rpc_report_sales_trend  (already plpgsql, add guard)
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_report_sales_trend(
  p_team_id uuid,
  p_branch_id uuid,
  p_from date,
  p_to date,
  p_granularity text
) RETURNS TABLE (
  period_start date,
  period_label text,
  sale_count bigint,
  revenue numeric,
  gross_profit numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  IF p_granularity NOT IN ('day', 'month', 'year') THEN
    RAISE EXCEPTION 'bad_granularity';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.team_id = p_team_id AND p.is_active
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT s.id, s.created_at::date AS sold_date, s.grand_total, s.gross_profit
    FROM public.sales s
    WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
      AND s.created_at::date BETWEEN p_from AND p_to
  ),
  grouped AS (
    SELECT
      CASE
        WHEN p_granularity = 'day' THEN date_trunc('day', b.sold_date::timestamp)::date
        WHEN p_granularity = 'month' THEN date_trunc('month', b.sold_date::timestamp)::date
        ELSE date_trunc('year', b.sold_date::timestamp)::date
      END AS grp,
      count(*)::bigint AS cnt,
      coalesce(sum(b.grand_total), 0)::numeric AS rev,
      coalesce(sum(b.gross_profit), 0)::numeric AS prof
    FROM base b
    GROUP BY 1
  )
  SELECT g.grp, CASE
    WHEN p_granularity = 'day' THEN to_char(g.grp, 'YYYY-MM-DD')
    WHEN p_granularity = 'month' THEN to_char(g.grp, 'YYYY-MM')
    ELSE to_char(g.grp, 'YYYY')
  END, g.cnt, g.rev, g.prof
  FROM grouped g ORDER BY g.grp;
END;
$$;

--------------------------------------------------------------------
-- 7. dashboard_metrics  (plpgsql, add guard after BEGIN)
--------------------------------------------------------------------
-- Already uses 3-arg form. Redefine the latest version with guard.
-- (Full body carried forward from 20260504100000.)
CREATE OR REPLACE FUNCTION public.dashboard_metrics(
  p_team_id uuid,
  p_branch_id uuid,
  p_category_ids uuid[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.team_id = p_team_id AND p.is_active
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN jsonb_build_object(
    'today_sales_total', coalesce((
      SELECT sum(s.grand_total) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date = CURRENT_DATE
        AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
          SELECT 1 FROM public.sale_items si
          LEFT JOIN public.medicines m ON m.id = si.medicine_id
          LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
          LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
          WHERE si.sale_id = s.id AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
        ))
    ), 0),
    'today_sales_count', coalesce((
      SELECT count(*) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date = CURRENT_DATE
        AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
          SELECT 1 FROM public.sale_items si
          LEFT JOIN public.medicines m ON m.id = si.medicine_id
          LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
          LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
          WHERE si.sale_id = s.id AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
        ))
    ), 0),
    'today_profit_total', coalesce((
      SELECT sum(s.gross_profit) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date = CURRENT_DATE
        AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
          SELECT 1 FROM public.sale_items si
          LEFT JOIN public.medicines m ON m.id = si.medicine_id
          LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
          LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
          WHERE si.sale_id = s.id AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
        ))
    ), 0),
    'sales_7d_total', coalesce((
      SELECT sum(s.grand_total) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date >= (CURRENT_DATE - 6)
        AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
          SELECT 1 FROM public.sale_items si
          LEFT JOIN public.medicines m ON m.id = si.medicine_id
          LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
          LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
          WHERE si.sale_id = s.id AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
        ))
    ), 0),
    'sales_mtd_total', coalesce((
      SELECT sum(s.grand_total) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND date_trunc('month', s.created_at) = date_trunc('month', now())
        AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
          SELECT 1 FROM public.sale_items si
          LEFT JOIN public.medicines m ON m.id = si.medicine_id
          LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
          LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
          WHERE si.sale_id = s.id AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
        ))
    ), 0),
    'stock_value_at_cost', coalesce((
      SELECT sum(sb.qty_base_unit * coalesce(mb.unit_cost_base, m.purchase_price, 0))
      FROM public.stock_balances sb
      JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id AND m.is_active
        AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR m.category_id = ANY(p_category_ids))
    ), 0),
    'low_stock_count', coalesce((
      SELECT count(*) FROM public.stock_balances sb
      JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id AND sb.qty_base_unit <= m.reorder_level
        AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR m.category_id = ANY(p_category_ids))
    ), 0),
    'near_expiry_count', coalesce((
      SELECT count(*) FROM public.medicine_batches mb
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
        AND mb.expiry_date >= CURRENT_DATE AND mb.expiry_date <= CURRENT_DATE + interval '90 days'
        AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR m.category_id = ANY(p_category_ids))
    ), 0),
    'expired_count', coalesce((
      SELECT count(*) FROM public.medicine_batches mb
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id AND mb.expiry_date < CURRENT_DATE
        AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR m.category_id = ANY(p_category_ids))
    ), 0),
    'top_sellers_7d', coalesce((
      SELECT jsonb_agg(jsonb_build_object('name', q.name, 'revenue', q.revenue))
      FROM (
        SELECT m.name, (sum(si.line_total))::numeric(12, 2) AS revenue
        FROM public.sale_items si
        JOIN public.sales s ON s.id = si.sale_id
        JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
        JOIN public.medicines m ON m.id = mb.medicine_id
        WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
          AND s.created_at::date >= (CURRENT_DATE - 6) AND m.is_active
          AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR m.category_id = ANY(p_category_ids))
        GROUP BY m.id, m.name ORDER BY revenue DESC LIMIT 5
      ) q
    ), '[]'::jsonb),
    'sales_by_staff_7d', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object('name', x.seller_name, 'sale_count', x.cnt, 'total', x.tot) ORDER BY x.tot DESC NULLS LAST
      )
      FROM (
        SELECT
          coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member') AS seller_name,
          count(*)::bigint AS cnt,
          sum(s.grand_total)::numeric(12, 2) AS tot
        FROM public.sales s
        LEFT JOIN public.profiles p ON p.id = s.sold_by AND p.team_id = p_team_id
        WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
          AND s.created_at::date >= (CURRENT_DATE - 6)
          AND (p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
            SELECT 1 FROM public.sale_items si
            LEFT JOIN public.medicines m ON m.id = si.medicine_id
            LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
            LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
            WHERE si.sale_id = s.id AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
          ))
        GROUP BY coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member')
      ) x
    ), '[]'::jsonb)
  );
END;
$$;

DROP FUNCTION IF EXISTS public.dashboard_metrics(uuid, uuid);

--------------------------------------------------------------------
-- 8. refresh_alerts  (plpgsql, add guard)
--------------------------------------------------------------------
-- Redefine with guard. Full body from 20260429180000.
CREATE OR REPLACE FUNCTION public.refresh_alerts(p_team_id uuid, p_branch_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND team_id = p_team_id AND is_active
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT p_team_id, p_branch_id, 'near_expiry_30',
    'Expires within 30 days',
    m.name || ' · batch ' || mb.batch_no || ' · exp ' || mb.expiry_date::text,
    'medicine_batch', mb.id
  FROM public.medicine_batches mb
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
    AND mb.expiry_date > CURRENT_DATE AND mb.expiry_date <= CURRENT_DATE + interval '30 days'
    AND mb.quantity_in_base_unit > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'near_expiry_30' AND n.entity_type = 'medicine_batch'
        AND n.entity_id = mb.id AND n.created_at > CURRENT_DATE - interval '7 days'
    );

  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT p_team_id, p_branch_id, 'expired',
    'Batch expired',
    m.name || ' · batch ' || mb.batch_no || ' · exp ' || mb.expiry_date::text,
    'medicine_batch', mb.id
  FROM public.medicine_batches mb
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
    AND mb.expiry_date < CURRENT_DATE
    AND mb.quantity_in_base_unit > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'expired' AND n.entity_type = 'medicine_batch'
        AND n.entity_id = mb.id AND n.created_at > CURRENT_DATE - interval '7 days'
    );

  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT p_team_id, p_branch_id, 'low_stock',
    'Low stock',
    m.name || ': ' || sb.qty_base_unit || ' left (reorder at ' || m.reorder_level || ')',
    'medicine', m.id
  FROM public.stock_balances sb
  JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id
    AND sb.qty_base_unit > 0 AND sb.qty_base_unit <= m.reorder_level
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'low_stock' AND n.entity_type = 'medicine'
        AND n.entity_id = m.id AND n.created_at > CURRENT_DATE - interval '1 day'
    );
END;
$$;

--------------------------------------------------------------------
-- 9. create_sale — add guard (full body from 20260504100000)
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_sale(
  p_branch_id uuid,
  p_items jsonb,
  p_method text,
  p_reference_no text,
  p_discount_total numeric,
  p_client_operation_id text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  v_role text;
  v_sale_id uuid;
  v_existing_sale_id uuid;
  v_subtotal numeric := 0;
  v_gross_profit numeric := 0;
  v_grand numeric;
  r jsonb;
  v_batch uuid;
  v_medicine uuid;
  v_qty numeric;
  v_price numeric;
  v_line numeric;
  v_exp date;
  v_list_price numeric;
  v_batch_uc numeric;
  v_med_pp numeric;
  v_pi_uc numeric;
  v_unit_cost numeric;
  v_line_profit numeric;
  v_override_reason text;
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  SELECT team_id, role INTO v_team_id, v_role
  FROM public.profiles WHERE id = auth.uid() AND is_active = true;
  IF v_team_id IS NULL THEN RAISE EXCEPTION 'no_profile'; END IF;

  PERFORM public.assert_team_may_mutate(v_team_id);

  IF p_client_operation_id IS NOT NULL THEN
    SELECT s.id INTO v_existing_sale_id FROM public.sales s
    WHERE s.team_id = v_team_id AND s.sold_by = auth.uid()
      AND s.client_operation_id = p_client_operation_id LIMIT 1;
    IF v_existing_sale_id IS NOT NULL THEN RETURN v_existing_sale_id; END IF;
  END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');
    IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'bad_qty'; END IF;
    IF v_price IS NULL OR v_price < 0 THEN RAISE EXCEPTION 'bad_price'; END IF;
    SELECT mb.expiry_date, mb.medicine_id, m.selling_price
    INTO v_exp, v_medicine, v_list_price
    FROM public.medicine_batches mb JOIN public.medicines m ON m.id = mb.medicine_id
    WHERE mb.id = v_batch AND mb.team_id = v_team_id AND mb.branch_id = p_branch_id;
    IF v_exp IS NULL THEN RAISE EXCEPTION 'batch_not_found'; END IF;
    IF v_exp < CURRENT_DATE THEN RAISE EXCEPTION 'expired_batch'; END IF;
    IF v_role IN ('cashier', 'seller') THEN
      IF v_list_price IS NULL THEN RAISE EXCEPTION 'missing_list_price'; END IF;
      IF v_price < (v_list_price * 0.95) OR v_price > (v_list_price * 1.05) THEN
        RAISE EXCEPTION 'cashier_price_override_out_of_range';
      END IF;
    END IF;
    v_line := v_qty * v_price;
    v_subtotal := v_subtotal + v_line;
  END LOOP;

  v_grand := v_subtotal - coalesce(p_discount_total, 0);
  IF v_grand < 0 THEN RAISE EXCEPTION 'bad_discount'; END IF;

  INSERT INTO public.sales (team_id, branch_id, sold_by, subtotal, discount_total, grand_total, gross_profit, client_operation_id)
  VALUES (v_team_id, p_branch_id, auth.uid(), v_subtotal, coalesce(p_discount_total, 0), v_grand, 0, p_client_operation_id)
  RETURNING id INTO v_sale_id;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');
    SELECT mb.medicine_id, m.selling_price, mb.unit_cost_base, m.purchase_price
    INTO v_medicine, v_list_price, v_batch_uc, v_med_pp
    FROM public.medicine_batches mb JOIN public.medicines m ON m.id = mb.medicine_id WHERE mb.id = v_batch;
    SELECT pi.unit_cost INTO v_pi_uc
    FROM public.purchase_items pi
    JOIN public.purchases pu ON pu.id = pi.purchase_id
    JOIN public.medicine_batches mb2 ON mb2.batch_no IS NOT DISTINCT FROM pi.batch_no
      AND mb2.medicine_id = pi.medicine_id AND mb2.branch_id = pu.branch_id
    WHERE pu.team_id = v_team_id AND pu.branch_id = p_branch_id AND pu.status = 'received' AND mb2.id = v_batch
    ORDER BY pu.created_at DESC, pi.id DESC LIMIT 1;
    v_unit_cost := coalesce(v_batch_uc, v_pi_uc, v_med_pp, 0);
    v_line := v_qty * v_price;
    v_line_profit := v_line - (v_qty * v_unit_cost);
    v_gross_profit := v_gross_profit + v_line_profit;
    INSERT INTO public.sale_items (sale_id, medicine_batch_id, medicine_id, unit, qty, unit_price, line_total,
      list_unit_price, cost_unit_at_sale, line_profit, price_override_reason)
    VALUES (v_sale_id, v_batch, v_medicine, 'base', v_qty, v_price, v_line,
      coalesce(v_list_price, 0), v_unit_cost, v_line_profit, v_override_reason);
    PERFORM public.apply_stock_movement(v_team_id, p_branch_id, v_batch, 'sale_out', -v_qty, null, 'sale', v_sale_id);
  END LOOP;

  UPDATE public.sales SET gross_profit = v_gross_profit WHERE id = v_sale_id;
  INSERT INTO public.payments (sale_id, method, amount, reference_no) VALUES (v_sale_id, p_method, v_grand, p_reference_no);
  INSERT INTO public.activity_logs (team_id, branch_id, user_id, action_type, entity_type, entity_id, meta)
  VALUES (v_team_id, p_branch_id, auth.uid(), 'sale_created', 'sale', v_sale_id,
    jsonb_build_object('items', jsonb_array_length(p_items), 'grand_total', v_grand));
  RETURN v_sale_id;
END;
$$;

--------------------------------------------------------------------
-- 10. bulk_stock_in — add guard (full body from 20260504100000)
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bulk_stock_in(p_branch_id uuid, p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid; r jsonb; v_mid uuid; v_batch_no text; v_exp date;
  v_qty numeric; v_unit_cost numeric; v_med_pp numeric; v_batch_id uuid; v_done int := 0;
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  SELECT team_id INTO v_team_id FROM public.profiles WHERE id = auth.uid() AND is_active = true;
  IF v_team_id IS NULL THEN RAISE EXCEPTION 'no_profile'; END IF;
  PERFORM public.assert_team_may_mutate(v_team_id);
  IF NOT EXISTS (SELECT 1 FROM public.branches b WHERE b.id = p_branch_id AND b.team_id = v_team_id) THEN
    RAISE EXCEPTION 'bad_branch';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'bulk_stock_empty'; END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_mid := (r->>'medicine_id')::uuid;
    v_batch_no := nullif(trim(coalesce(r->>'batch_no', '')), '');
    v_exp := (r->>'expiry_date')::date;
    v_qty := (r->>'qty')::numeric;
    IF v_mid IS NULL OR v_exp IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'bulk_stock_bad_row'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.medicines m WHERE m.id = v_mid AND m.team_id = v_team_id) THEN
      RAISE EXCEPTION 'medicine_not_found';
    END IF;
    IF v_exp < CURRENT_DATE THEN RAISE EXCEPTION 'expiry_in_past'; END IF;
    SELECT m.purchase_price INTO v_med_pp FROM public.medicines m WHERE m.id = v_mid;
    v_unit_cost := (r->>'unit_cost')::numeric;
    v_unit_cost := coalesce(v_unit_cost, v_med_pp, 0);
    INSERT INTO public.medicine_batches (team_id, branch_id, medicine_id, batch_no, expiry_date, quantity_in_base_unit, unit_cost_base)
    VALUES (v_team_id, p_branch_id, v_mid, v_batch_no, v_exp, 0, v_unit_cost)
    RETURNING id INTO v_batch_id;
    PERFORM public.apply_stock_movement(v_team_id, p_branch_id, v_batch_id, 'purchase_in', v_qty, 'bulk_stock_in', 'bulk_stock_in', NULL);
    v_done := v_done + 1;
  END LOOP;
  RETURN jsonb_build_object('rows_applied', v_done);
END;
$$;

--------------------------------------------------------------------
-- 11. receive_purchase — add guard using purchase's branch_id
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.receive_purchase(p_purchase_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pu RECORD; it RECORD; v_batch uuid;
BEGIN
  SELECT * INTO pu FROM public.purchases WHERE id = p_purchase_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  PERFORM public.assert_branch_access(pu.branch_id);

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND team_id = pu.team_id AND is_active) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF pu.status = 'received' THEN RETURN; END IF;

  FOR it IN SELECT * FROM public.purchase_items WHERE purchase_id = pu.id LOOP
    INSERT INTO public.medicine_batches (team_id, branch_id, medicine_id, batch_no, expiry_date, quantity_in_base_unit, unit_cost_base)
    VALUES (pu.team_id, pu.branch_id, it.medicine_id, it.batch_no, it.expiry_date, 0, it.unit_cost)
    RETURNING id INTO v_batch;
    PERFORM public.apply_stock_movement(pu.team_id, pu.branch_id, v_batch, 'purchase_in', it.qty_base_unit, null, 'purchase', pu.id);
  END LOOP;
  UPDATE public.purchases SET status = 'received' WHERE id = pu.id;
END;
$$;

NOTIFY pgrst, 'reload schema';
