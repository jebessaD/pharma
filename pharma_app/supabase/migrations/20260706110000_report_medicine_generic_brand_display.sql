-- Reports: show generic + brand in medicine_name (generic · brand).

CREATE OR REPLACE FUNCTION public.medicine_report_display_name(
  p_brand_name text,
  p_generic_name text
) RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE
    WHEN coalesce(nullif(btrim(p_generic_name), ''), '') <> ''
         AND coalesce(nullif(btrim(p_brand_name), ''), '') <> ''
         AND lower(btrim(p_brand_name)) <> lower(btrim(p_generic_name))
      THEN btrim(p_generic_name) || ' · ' || btrim(p_brand_name)
    WHEN coalesce(nullif(btrim(p_generic_name), ''), '') <> ''
      THEN btrim(p_generic_name)
    ELSE coalesce(nullif(btrim(p_brand_name), ''), 'Unknown medicine')
  END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_report_stock_balance(
  p_team_id uuid,
  p_branch_id uuid,
  p_category_keys text[] DEFAULT NULL
) RETURNS TABLE (medicine_name text, batch_no text, qty numeric, expiry_date date)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  RETURN QUERY
  SELECT
    public.medicine_report_display_name(m.name, m.generic_name),
    mb.batch_no,
    sb.qty_base_unit,
    mb.expiry_date
  FROM public.stock_balances sb
  JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id
    AND (
      p_category_keys IS NULL OR
      cardinality(p_category_keys) = 0 OR
      m.category_key = ANY(p_category_keys)
    )
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = p_team_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_report_expiry_status(
  p_team_id uuid,
  p_branch_id uuid,
  p_threshold_days int,
  p_category_keys text[] DEFAULT NULL
) RETURNS TABLE (medicine_name text, batch_no text, expiry_date date, days_left int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  RETURN QUERY
  SELECT
    public.medicine_report_display_name(m.name, m.generic_name),
    mb.batch_no,
    mb.expiry_date,
    (mb.expiry_date - CURRENT_DATE)::int
  FROM public.medicine_batches mb
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
    AND mb.expiry_date <= CURRENT_DATE + (p_threshold_days || ' days')::interval
    AND (
      p_category_keys IS NULL OR
      cardinality(p_category_keys) = 0 OR
      m.category_key = ANY(p_category_keys)
    )
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = p_team_id
    );
END;
$$;

DROP FUNCTION IF EXISTS public.rpc_report_sales_unified(
  uuid, uuid, date, date, uuid, numeric, numeric, text, boolean, text[], text, integer, integer
);

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
  p_category_keys text[] DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT NULL,
  p_offset integer DEFAULT 0
) RETURNS TABLE (
  sold_at timestamptz,
  sale_id uuid,
  seller_name text,
  medicine_name text,
  medicine_code text,
  qty numeric,
  unit_price numeric,
  line_total numeric,
  net_line_total numeric,
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
  v_search text;
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid() AND is_active LIMIT 1;
  v_eff_sold_by := p_sold_by;
  IF v_role IN ('cashier', 'seller') THEN
    v_eff_sold_by := auth.uid();
  END IF;

  v_search := nullif(btrim(coalesce(p_search, '')), '');

  RETURN QUERY
  SELECT
    s.created_at AS sold_at,
    s.id AS sale_id,
    coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member') AS seller_name,
    public.medicine_report_display_name(
      coalesce(m.name, mbm.name),
      coalesce(m.generic_name, mbm.generic_name)
    ) AS medicine_name,
    coalesce(m.manual_code, mbm.manual_code, '') AS medicine_code,
    si.qty,
    si.unit_price,
    si.line_total,
    (si.line_total - coalesce(si.discount_alloc, 0)) AS net_line_total,
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
      p_category_keys IS NULL OR
      cardinality(p_category_keys) = 0 OR
      coalesce(m.category_key, mbm.category_key) = ANY(p_category_keys)
    )
    AND (
      v_search IS NULL OR
      coalesce(m.name, mbm.name, '') ILIKE ('%' || v_search || '%') OR
      coalesce(m.generic_name, mbm.generic_name, '') ILIKE ('%' || v_search || '%') OR
      coalesce(m.manual_code, mbm.manual_code, '') ILIKE ('%' || v_search || '%') OR
      coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), '') ILIKE ('%' || v_search || '%')
    )
    AND EXISTS (
      SELECT 1 FROM public.profiles me
      WHERE me.id = auth.uid() AND me.team_id = p_team_id AND me.is_active
    )
  ORDER BY s.created_at DESC, s.id DESC, si.id ASC
  LIMIT p_limit
  OFFSET coalesce(p_offset, 0);
END;
$$;

DROP FUNCTION IF EXISTS public.rpc_report_sales_unified_stats(
  uuid, uuid, date, date, uuid, numeric, numeric, text, boolean, text[], text
);

CREATE OR REPLACE FUNCTION public.rpc_report_sales_unified_stats(
  p_team_id uuid,
  p_branch_id uuid,
  p_from date,
  p_to date,
  p_sold_by uuid DEFAULT NULL,
  p_min_amount numeric DEFAULT NULL,
  p_max_amount numeric DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_overrides_only boolean DEFAULT false,
  p_category_keys text[] DEFAULT NULL,
  p_search text DEFAULT NULL
) RETURNS TABLE (
  line_count bigint,
  qty_sum numeric,
  line_total_sum numeric,
  net_line_total_sum numeric,
  discount_total_sum numeric,
  grand_total_sum numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_eff_sold_by uuid;
  v_search text;
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid() AND is_active LIMIT 1;
  v_eff_sold_by := p_sold_by;
  IF v_role IN ('cashier', 'seller') THEN
    v_eff_sold_by := auth.uid();
  END IF;

  v_search := nullif(btrim(coalesce(p_search, '')), '');

  RETURN QUERY
  WITH base AS (
    SELECT
      si.qty,
      si.line_total,
      coalesce(si.discount_alloc, 0) AS discount_alloc,
      s.id AS sale_id,
      s.discount_total,
      s.grand_total
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
        p_category_keys IS NULL OR
        cardinality(p_category_keys) = 0 OR
        coalesce(m.category_key, mbm.category_key) = ANY(p_category_keys)
      )
      AND (
        v_search IS NULL OR
        coalesce(m.name, mbm.name, '') ILIKE ('%' || v_search || '%') OR
        coalesce(m.generic_name, mbm.generic_name, '') ILIKE ('%' || v_search || '%') OR
        coalesce(m.manual_code, mbm.manual_code, '') ILIKE ('%' || v_search || '%') OR
        coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), '') ILIKE ('%' || v_search || '%')
      )
      AND EXISTS (
        SELECT 1 FROM public.profiles me
        WHERE me.id = auth.uid() AND me.team_id = p_team_id AND me.is_active
      )
  ),
  per_sale AS (
    SELECT DISTINCT sale_id, discount_total, grand_total
    FROM base
  )
  SELECT
    (SELECT count(*)::bigint FROM base),
    (SELECT coalesce(sum(qty), 0) FROM base),
    (SELECT coalesce(sum(line_total), 0) FROM base),
    (SELECT coalesce(sum(line_total - discount_alloc), 0) FROM base),
    (SELECT coalesce(sum(discount_total), 0) FROM per_sale),
    (SELECT coalesce(sum(grand_total), 0) FROM per_sale);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_report_sales_unified(
  uuid, uuid, date, date, uuid, numeric, numeric, text, boolean, text[], text, integer, integer
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_report_sales_unified(
  uuid, uuid, date, date, uuid, numeric, numeric, text, boolean, text[], text, integer, integer
) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_report_sales_unified_stats(
  uuid, uuid, date, date, uuid, numeric, numeric, text, boolean, text[], text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_report_sales_unified_stats(
  uuid, uuid, date, date, uuid, numeric, numeric, text, boolean, text[], text
) TO authenticated;
