-- Phase 12: dynamic POS pricing controls + profit-ready reporting

ALTER TABLE public.sale_items
  ADD COLUMN IF NOT EXISTS medicine_id uuid REFERENCES public.medicines (id),
  ADD COLUMN IF NOT EXISTS list_unit_price numeric(12, 2),
  ADD COLUMN IF NOT EXISTS cost_unit_at_sale numeric(12, 2),
  ADD COLUMN IF NOT EXISTS line_profit numeric(12, 2),
  ADD COLUMN IF NOT EXISTS price_override_reason text;

ALTER TABLE public.sales
  ADD COLUMN IF NOT EXISTS gross_profit numeric(12, 2) NOT NULL DEFAULT 0;

UPDATE public.sale_items si
SET medicine_id = mb.medicine_id
FROM public.medicine_batches mb
WHERE si.medicine_batch_id = mb.id
  AND si.medicine_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_sale_items_medicine ON public.sale_items (medicine_id);

CREATE OR REPLACE FUNCTION public.create_sale(
  p_branch_id uuid,
  p_items jsonb,
  p_method text,
  p_reference_no text,
  p_discount_total numeric
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  v_role text;
  v_sale_id uuid;
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
  v_unit_cost numeric;
  v_line_profit numeric;
  v_override_reason text;
BEGIN
  SELECT team_id, role
  INTO v_team_id, v_role
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'no_profile';
  END IF;

  IF EXISTS (SELECT 1 FROM public.teams t WHERE t.id = v_team_id AND t.status <> 'active') THEN
    RAISE EXCEPTION 'team_suspended';
  END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');

    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'bad_qty';
    END IF;
    IF v_price IS NULL OR v_price < 0 THEN
      RAISE EXCEPTION 'bad_price';
    END IF;

    SELECT mb.expiry_date, mb.medicine_id, m.selling_price
    INTO v_exp, v_medicine, v_list_price
    FROM public.medicine_batches mb
    JOIN public.medicines m ON m.id = mb.medicine_id
    WHERE mb.id = v_batch AND mb.team_id = v_team_id AND mb.branch_id = p_branch_id;

    IF v_exp IS NULL THEN
      RAISE EXCEPTION 'batch_not_found';
    END IF;
    IF v_exp < CURRENT_DATE THEN
      RAISE EXCEPTION 'expired_batch';
    END IF;

    IF v_price <> coalesce(v_list_price, 0) AND v_override_reason IS NULL THEN
      RAISE EXCEPTION 'price_override_reason_required';
    END IF;

    -- Cashier can only apply small overrides, admin/pharmacist can set any non-negative price.
    IF v_role = 'cashier' THEN
      IF v_list_price IS NULL THEN
        RAISE EXCEPTION 'missing_list_price';
      END IF;
      IF v_price < (v_list_price * 0.95) OR v_price > (v_list_price * 1.05) THEN
        RAISE EXCEPTION 'cashier_price_override_out_of_range';
      END IF;
    END IF;

    v_line := v_qty * v_price;
    v_subtotal := v_subtotal + v_line;
  END LOOP;

  v_grand := v_subtotal - coalesce(p_discount_total, 0);
  IF v_grand < 0 THEN
    RAISE EXCEPTION 'bad_discount';
  END IF;

  INSERT INTO public.sales (team_id, branch_id, sold_by, subtotal, discount_total, grand_total, gross_profit)
  VALUES (v_team_id, p_branch_id, auth.uid(), v_subtotal, coalesce(p_discount_total, 0), v_grand, 0)
  RETURNING id INTO v_sale_id;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');

    SELECT mb.medicine_id, m.selling_price
    INTO v_medicine, v_list_price
    FROM public.medicine_batches mb
    JOIN public.medicines m ON m.id = mb.medicine_id
    WHERE mb.id = v_batch;

    SELECT pi.unit_cost
    INTO v_unit_cost
    FROM public.purchase_items pi
    JOIN public.purchases pu ON pu.id = pi.purchase_id
    JOIN public.medicine_batches mb ON mb.batch_no = pi.batch_no
                               AND mb.medicine_id = pi.medicine_id
                               AND mb.branch_id = pu.branch_id
    WHERE pu.team_id = v_team_id
      AND pu.branch_id = p_branch_id
      AND pu.status = 'received'
      AND mb.id = v_batch
    ORDER BY pu.created_at DESC, pi.id DESC
    LIMIT 1;

    v_line := v_qty * v_price;
    v_line_profit := v_line - (v_qty * coalesce(v_unit_cost, 0));
    v_gross_profit := v_gross_profit + v_line_profit;

    INSERT INTO public.sale_items (
      sale_id, medicine_batch_id, medicine_id, unit, qty, unit_price, line_total,
      list_unit_price, cost_unit_at_sale, line_profit, price_override_reason
    )
    VALUES (
      v_sale_id, v_batch, v_medicine, 'base', v_qty, v_price, v_line,
      coalesce(v_list_price, 0), coalesce(v_unit_cost, 0), v_line_profit, v_override_reason
    );

    PERFORM public.apply_stock_movement(
      v_team_id, p_branch_id, v_batch, 'sale_out', -v_qty, null, 'sale', v_sale_id
    );
  END LOOP;

  UPDATE public.sales
  SET gross_profit = v_gross_profit
  WHERE id = v_sale_id;

  INSERT INTO public.payments (sale_id, method, amount, reference_no)
  VALUES (v_sale_id, p_method, v_grand, p_reference_no);

  INSERT INTO public.activity_logs (
    team_id, branch_id, user_id, action_type, entity_type, entity_id, meta
  )
  VALUES (
    v_team_id,
    p_branch_id,
    auth.uid(),
    'sale_created',
    'sale',
    v_sale_id,
    jsonb_build_object('items', jsonb_array_length(p_items), 'grand_total', v_grand)
  );

  RETURN v_sale_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_sale(uuid, jsonb, text, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_sale(uuid, jsonb, text, text, numeric) TO authenticated;

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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.rpc_report_profit_summary(uuid, uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_report_profit_summary(uuid, uuid, date, date) TO authenticated;

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
  IF p_granularity NOT IN ('day', 'month', 'year') THEN
    RAISE EXCEPTION 'bad_granularity';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid() AND p.team_id = p_team_id AND p.is_active
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      s.id,
      s.created_at::date AS sold_date,
      s.grand_total,
      s.gross_profit
    FROM public.sales s
    WHERE s.team_id = p_team_id
      AND s.branch_id = p_branch_id
      AND s.created_at::date BETWEEN p_from AND p_to
  ),
  grouped AS (
    SELECT
      CASE
        WHEN p_granularity = 'day' THEN date_trunc('day', sold_date::timestamp)::date
        WHEN p_granularity = 'month' THEN date_trunc('month', sold_date::timestamp)::date
        ELSE date_trunc('year', sold_date::timestamp)::date
      END AS grp,
      count(*)::bigint AS cnt,
      coalesce(sum(grand_total), 0)::numeric AS rev,
      coalesce(sum(gross_profit), 0)::numeric AS prof
    FROM base
    GROUP BY 1
  )
  SELECT
    grp AS period_start,
    CASE
      WHEN p_granularity = 'day' THEN to_char(grp, 'YYYY-MM-DD')
      WHEN p_granularity = 'month' THEN to_char(grp, 'YYYY-MM')
      ELSE to_char(grp, 'YYYY')
    END AS period_label,
    cnt AS sale_count,
    rev AS revenue,
    prof AS gross_profit
  FROM grouped
  ORDER BY grp;
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_report_sales_trend(uuid, uuid, date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_report_sales_trend(uuid, uuid, date, date, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.dashboard_metrics(p_team_id uuid, p_branch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.team_id = p_team_id AND p.is_active
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN jsonb_build_object(
    'today_sales_total', coalesce((
      SELECT sum(grand_total) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND (s.created_at::date = CURRENT_DATE)
    ), 0),
    'today_sales_count', coalesce((
      SELECT count(*) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND (s.created_at::date = CURRENT_DATE)
    ), 0),
    'today_profit_total', coalesce((
      SELECT sum(gross_profit) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND (s.created_at::date = CURRENT_DATE)
    ), 0),
    'low_stock_count', coalesce((
      SELECT count(*) FROM public.stock_balances sb
      JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id
        AND sb.qty_base_unit <= m.reorder_level
    ), 0),
    'near_expiry_count', coalesce((
      SELECT count(*) FROM public.medicine_batches mb
      WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
        AND mb.expiry_date >= CURRENT_DATE
        AND mb.expiry_date <= CURRENT_DATE + interval '90 days'
    ), 0),
    'expired_count', coalesce((
      SELECT count(*) FROM public.medicine_batches mb
      WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
        AND mb.expiry_date < CURRENT_DATE
    ), 0)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dashboard_metrics(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dashboard_metrics(uuid, uuid) TO authenticated;

