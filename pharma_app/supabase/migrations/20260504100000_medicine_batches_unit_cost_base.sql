-- Per-batch unit cost for COGS and stock valuation.
-- unit_cost_base: set at receipt (purchase receive, bulk_stock_in). NULL = legacy row (use purchase_items join, then medicines.purchase_price).

ALTER TABLE public.medicine_batches
  ADD COLUMN IF NOT EXISTS unit_cost_base numeric(12, 2);

COMMENT ON COLUMN public.medicine_batches.unit_cost_base IS
  'Purchase cost per base unit for this batch. NULL for legacy rows; prefer coalesce(unit_cost_base, purchase_items.unit_cost, medicines.purchase_price).';

-- Best-effort backfill from received purchase lines (same medicine, batch, expiry, branch).
UPDATE public.medicine_batches mb
SET unit_cost_base = x.unit_cost
FROM (
  SELECT DISTINCT ON (mb_inner.id)
    mb_inner.id AS batch_id,
    pi.unit_cost
  FROM public.medicine_batches mb_inner
  JOIN public.purchase_items pi
    ON pi.medicine_id = mb_inner.medicine_id
   AND pi.batch_no IS NOT DISTINCT FROM mb_inner.batch_no
   AND pi.expiry_date = mb_inner.expiry_date
  JOIN public.purchases pu ON pu.id = pi.purchase_id
    AND pu.team_id = mb_inner.team_id
    AND pu.branch_id = mb_inner.branch_id
    AND pu.status = 'received'
  ORDER BY mb_inner.id, pu.created_at DESC, pi.id DESC
) x
WHERE mb.id = x.batch_id
  AND mb.unit_cost_base IS NULL;

CREATE OR REPLACE FUNCTION public.receive_purchase(p_purchase_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pu RECORD;
  it RECORD;
  v_batch uuid;
BEGIN
  SELECT * INTO pu FROM public.purchases WHERE id = p_purchase_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND team_id = pu.team_id AND is_active) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF pu.status = 'received' THEN
    RETURN;
  END IF;

  FOR it IN SELECT * FROM public.purchase_items WHERE purchase_id = pu.id
  LOOP
    INSERT INTO public.medicine_batches (
      team_id, branch_id, medicine_id, batch_no, expiry_date, quantity_in_base_unit, unit_cost_base
    ) VALUES (
      pu.team_id, pu.branch_id, it.medicine_id, it.batch_no, it.expiry_date, 0, it.unit_cost
    )
    RETURNING id INTO v_batch;

    PERFORM public.apply_stock_movement(
      pu.team_id, pu.branch_id, v_batch, 'purchase_in', it.qty_base_unit, null, 'purchase', pu.id
    );
  END LOOP;

  UPDATE public.purchases SET status = 'received' WHERE id = pu.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_stock_in(p_branch_id uuid, p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  r jsonb;
  v_mid uuid;
  v_batch_no text;
  v_exp date;
  v_qty numeric;
  v_unit_cost numeric;
  v_med_pp numeric;
  v_batch_id uuid;
  v_done int := 0;
BEGIN
  SELECT team_id INTO v_team_id
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'no_profile';
  END IF;

  PERFORM public.assert_team_may_mutate(v_team_id);

  IF NOT EXISTS (
    SELECT 1 FROM public.branches b
    WHERE b.id = p_branch_id AND b.team_id = v_team_id
  ) THEN
    RAISE EXCEPTION 'bad_branch';
  END IF;

  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'bulk_stock_empty';
  END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_mid := (r->>'medicine_id')::uuid;
    v_batch_no := nullif(trim(coalesce(r->>'batch_no', '')), '');
    v_exp := (r->>'expiry_date')::date;
    v_qty := (r->>'qty')::numeric;

    IF v_mid IS NULL OR v_exp IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'bulk_stock_bad_row';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.medicines m
      WHERE m.id = v_mid AND m.team_id = v_team_id
    ) THEN
      RAISE EXCEPTION 'medicine_not_found';
    END IF;

    IF v_exp < CURRENT_DATE THEN
      RAISE EXCEPTION 'expiry_in_past';
    END IF;

    SELECT m.purchase_price INTO v_med_pp
    FROM public.medicines m
    WHERE m.id = v_mid;

    v_unit_cost := (r->>'unit_cost')::numeric;
    v_unit_cost := coalesce(v_unit_cost, v_med_pp, 0);

    INSERT INTO public.medicine_batches (
      team_id, branch_id, medicine_id, batch_no, expiry_date, quantity_in_base_unit, unit_cost_base
    ) VALUES (v_team_id, p_branch_id, v_mid, v_batch_no, v_exp, 0, v_unit_cost)
    RETURNING id INTO v_batch_id;

    PERFORM public.apply_stock_movement(
      v_team_id,
      p_branch_id,
      v_batch_id,
      'purchase_in',
      v_qty,
      'bulk_stock_in',
      'bulk_stock_in',
      NULL
    );

    v_done := v_done + 1;
  END LOOP;

  RETURN jsonb_build_object('rows_applied', v_done);
END;
$$;

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
  SELECT team_id, role
  INTO v_team_id, v_role
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'no_profile';
  END IF;

  PERFORM public.assert_team_may_mutate(v_team_id);

  IF p_client_operation_id IS NOT NULL THEN
    SELECT s.id
    INTO v_existing_sale_id
    FROM public.sales s
    WHERE s.team_id = v_team_id
      AND s.sold_by = auth.uid()
      AND s.client_operation_id = p_client_operation_id
    LIMIT 1;

    IF v_existing_sale_id IS NOT NULL THEN
      RETURN v_existing_sale_id;
    END IF;
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
    WHERE mb.id = v_batch
      AND mb.team_id = v_team_id
      AND mb.branch_id = p_branch_id;

    IF v_exp IS NULL THEN
      RAISE EXCEPTION 'batch_not_found';
    END IF;
    IF v_exp < CURRENT_DATE THEN
      RAISE EXCEPTION 'expired_batch';
    END IF;

    IF v_role IN ('cashier', 'seller') THEN
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

  INSERT INTO public.sales (
    team_id,
    branch_id,
    sold_by,
    subtotal,
    discount_total,
    grand_total,
    gross_profit,
    client_operation_id
  )
  VALUES (
    v_team_id,
    p_branch_id,
    auth.uid(),
    v_subtotal,
    coalesce(p_discount_total, 0),
    v_grand,
    0,
    p_client_operation_id
  )
  RETURNING id INTO v_sale_id;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');

    SELECT mb.medicine_id, m.selling_price, mb.unit_cost_base, m.purchase_price
    INTO v_medicine, v_list_price, v_batch_uc, v_med_pp
    FROM public.medicine_batches mb
    JOIN public.medicines m ON m.id = mb.medicine_id
    WHERE mb.id = v_batch;

    SELECT pi.unit_cost
    INTO v_pi_uc
    FROM public.purchase_items pi
    JOIN public.purchases pu ON pu.id = pi.purchase_id
    JOIN public.medicine_batches mb2 ON mb2.batch_no IS NOT DISTINCT FROM pi.batch_no
                               AND mb2.medicine_id = pi.medicine_id
                               AND mb2.branch_id = pu.branch_id
    WHERE pu.team_id = v_team_id
      AND pu.branch_id = p_branch_id
      AND pu.status = 'received'
      AND mb2.id = v_batch
    ORDER BY pu.created_at DESC, pi.id DESC
    LIMIT 1;

    v_unit_cost := coalesce(v_batch_uc, v_pi_uc, v_med_pp, 0);

    v_line := v_qty * v_price;
    v_line_profit := v_line - (v_qty * v_unit_cost);
    v_gross_profit := v_gross_profit + v_line_profit;

    INSERT INTO public.sale_items (
      sale_id, medicine_batch_id, medicine_id, unit, qty, unit_price, line_total,
      list_unit_price, cost_unit_at_sale, line_profit, price_override_reason
    )
    VALUES (
      v_sale_id, v_batch, v_medicine, 'base', v_qty, v_price, v_line,
      coalesce(v_list_price, 0), v_unit_cost, v_line_profit, v_override_reason
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
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.team_id = p_team_id AND p.is_active
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN jsonb_build_object(
    'today_sales_total', coalesce((
      SELECT sum(s.grand_total)
      FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date = CURRENT_DATE
        AND (
          p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
            SELECT 1
            FROM public.sale_items si
            LEFT JOIN public.medicines m ON m.id = si.medicine_id
            LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
            LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
            WHERE si.sale_id = s.id
              AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
          )
        )
    ), 0),
    'today_sales_count', coalesce((
      SELECT count(*)
      FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date = CURRENT_DATE
        AND (
          p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
            SELECT 1
            FROM public.sale_items si
            LEFT JOIN public.medicines m ON m.id = si.medicine_id
            LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
            LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
            WHERE si.sale_id = s.id
              AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
          )
        )
    ), 0),
    'today_profit_total', coalesce((
      SELECT sum(s.gross_profit)
      FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date = CURRENT_DATE
        AND (
          p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
            SELECT 1
            FROM public.sale_items si
            LEFT JOIN public.medicines m ON m.id = si.medicine_id
            LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
            LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
            WHERE si.sale_id = s.id
              AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
          )
        )
    ), 0),
    'sales_7d_total', coalesce((
      SELECT sum(s.grand_total)
      FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date >= (CURRENT_DATE - 6)
        AND (
          p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
            SELECT 1
            FROM public.sale_items si
            LEFT JOIN public.medicines m ON m.id = si.medicine_id
            LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
            LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
            WHERE si.sale_id = s.id
              AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
          )
        )
    ), 0),
    'sales_mtd_total', coalesce((
      SELECT sum(s.grand_total)
      FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND date_trunc('month', s.created_at) = date_trunc('month', now())
        AND (
          p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
            SELECT 1
            FROM public.sale_items si
            LEFT JOIN public.medicines m ON m.id = si.medicine_id
            LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
            LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
            WHERE si.sale_id = s.id
              AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
          )
        )
    ), 0),
    'stock_value_at_cost', coalesce((
      SELECT sum(sb.qty_base_unit * coalesce(mb.unit_cost_base, m.purchase_price, 0))
      FROM public.stock_balances sb
      JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id
        AND m.is_active
        AND (
          p_category_ids IS NULL OR
          cardinality(p_category_ids) = 0 OR
          m.category_id = ANY(p_category_ids)
        )
    ), 0),
    'low_stock_count', coalesce((
      SELECT count(*)
      FROM public.stock_balances sb
      JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id
        AND sb.qty_base_unit <= m.reorder_level
        AND (
          p_category_ids IS NULL OR
          cardinality(p_category_ids) = 0 OR
          m.category_id = ANY(p_category_ids)
        )
    ), 0),
    'near_expiry_count', coalesce((
      SELECT count(*)
      FROM public.medicine_batches mb
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
        AND mb.expiry_date >= CURRENT_DATE
        AND mb.expiry_date <= CURRENT_DATE + interval '90 days'
        AND (
          p_category_ids IS NULL OR
          cardinality(p_category_ids) = 0 OR
          m.category_id = ANY(p_category_ids)
        )
    ), 0),
    'expired_count', coalesce((
      SELECT count(*)
      FROM public.medicine_batches mb
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
        AND mb.expiry_date < CURRENT_DATE
        AND (
          p_category_ids IS NULL OR
          cardinality(p_category_ids) = 0 OR
          m.category_id = ANY(p_category_ids)
        )
    ), 0),
    'top_sellers_7d', coalesce((
      SELECT jsonb_agg(jsonb_build_object('name', q.name, 'revenue', q.revenue))
      FROM (
        SELECT
          m.name,
          (sum(si.line_total))::numeric(12, 2) AS revenue
        FROM public.sale_items si
        JOIN public.sales s ON s.id = si.sale_id
        JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
        JOIN public.medicines m ON m.id = mb.medicine_id
        WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
          AND s.created_at::date >= (CURRENT_DATE - 6)
          AND m.is_active
          AND (
            p_category_ids IS NULL OR
            cardinality(p_category_ids) = 0 OR
            m.category_id = ANY(p_category_ids)
          )
        GROUP BY m.id, m.name
        ORDER BY revenue DESC
        LIMIT 5
      ) q
    ), '[]'::jsonb),
    'sales_by_staff_7d', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'name', x.seller_name,
          'sale_count', x.cnt,
          'total', x.tot
        ) ORDER BY x.tot DESC NULLS LAST
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
          AND (
            p_category_ids IS NULL OR cardinality(p_category_ids) = 0 OR EXISTS (
              SELECT 1
              FROM public.sale_items si
              LEFT JOIN public.medicines m ON m.id = si.medicine_id
              LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
              LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
              WHERE si.sale_id = s.id
                AND coalesce(m.category_id, mbm.category_id) = ANY(p_category_ids)
            )
          )
        GROUP BY coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member')
      ) x
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dashboard_metrics(uuid, uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dashboard_metrics(uuid, uuid, uuid[]) TO authenticated;

DROP FUNCTION IF EXISTS public.dashboard_metrics(uuid, uuid);

NOTIFY pgrst, 'reload schema';
