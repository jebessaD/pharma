-- Hardcoded medicine category keys on medicines + RPC filters by p_category_keys (text[]).

ALTER TABLE public.medicines
  ADD COLUMN IF NOT EXISTS category_key text;

UPDATE public.medicines m
SET category_key = (
  CASE regexp_replace(
    lower(btrim(coalesce(
      (SELECT mc.name FROM public.medicine_categories mc WHERE mc.id = m.category_id),
      nullif(trim(m.category), ''),
      'other'
    ))),
    '[[:space:]]+', ' ', 'g'
  )
    WHEN 'medicine' THEN 'medicine'
    WHEN 'consumable' THEN 'consumable'
    WHEN 'medical device' THEN 'medical_device'
    WHEN 'supplements' THEN 'supplements'
    WHEN 'personal care' THEN 'personal_care'
    WHEN 'diagnostics' THEN 'diagnostics'
    WHEN 'other' THEN 'other'
    ELSE 'other'
  END
);

ALTER TABLE public.medicines
  DROP CONSTRAINT IF EXISTS medicines_category_key_check;

ALTER TABLE public.medicines
  ADD CONSTRAINT medicines_category_key_check
  CHECK (category_key IN (
    'medicine', 'consumable', 'medical_device', 'supplements',
    'personal_care', 'diagnostics', 'other'
  ));

ALTER TABLE public.medicines
  ALTER COLUMN category_key SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_medicines_category_key
  ON public.medicines (team_id, branch_id, category_key);

-- rpc_report_sales_unified
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
  p_category_keys text[] DEFAULT NULL
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
      p_category_keys IS NULL OR
      cardinality(p_category_keys) = 0 OR
      coalesce(m.category_key, mbm.category_key) = ANY(p_category_keys)
    )
    AND EXISTS (
      SELECT 1 FROM public.profiles me
      WHERE me.id = auth.uid() AND me.team_id = p_team_id AND me.is_active
    )
  ORDER BY s.created_at DESC, s.id DESC, si.id ASC;
END;
$$;

-- rpc_report_stock_balance
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
  SELECT m.name, mb.batch_no, sb.qty_base_unit, mb.expiry_date
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

-- rpc_report_expiry_status
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
  SELECT m.name, mb.batch_no, mb.expiry_date,
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

-- dashboard_metrics
CREATE OR REPLACE FUNCTION public.dashboard_metrics(
  p_team_id uuid,
  p_branch_id uuid,
  p_category_keys text[] DEFAULT NULL
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
        AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR EXISTS (
          SELECT 1 FROM public.sale_items si
          LEFT JOIN public.medicines m ON m.id = si.medicine_id
          LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
          LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
          WHERE si.sale_id = s.id AND coalesce(m.category_key, mbm.category_key) = ANY(p_category_keys)
        ))
    ), 0),
    'today_sales_count', coalesce((
      SELECT count(*) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date = CURRENT_DATE
        AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR EXISTS (
          SELECT 1 FROM public.sale_items si
          LEFT JOIN public.medicines m ON m.id = si.medicine_id
          LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
          LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
          WHERE si.sale_id = s.id AND coalesce(m.category_key, mbm.category_key) = ANY(p_category_keys)
        ))
    ), 0),
    'today_profit_total', coalesce((
      SELECT sum(s.gross_profit) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date = CURRENT_DATE
        AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR EXISTS (
          SELECT 1 FROM public.sale_items si
          LEFT JOIN public.medicines m ON m.id = si.medicine_id
          LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
          LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
          WHERE si.sale_id = s.id AND coalesce(m.category_key, mbm.category_key) = ANY(p_category_keys)
        ))
    ), 0),
    'sales_7d_total', coalesce((
      SELECT sum(s.grand_total) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date >= (CURRENT_DATE - 6)
        AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR EXISTS (
          SELECT 1 FROM public.sale_items si
          LEFT JOIN public.medicines m ON m.id = si.medicine_id
          LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
          LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
          WHERE si.sale_id = s.id AND coalesce(m.category_key, mbm.category_key) = ANY(p_category_keys)
        ))
    ), 0),
    'sales_mtd_total', coalesce((
      SELECT sum(s.grand_total) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND date_trunc('month', s.created_at) = date_trunc('month', now())
        AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR EXISTS (
          SELECT 1 FROM public.sale_items si
          LEFT JOIN public.medicines m ON m.id = si.medicine_id
          LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
          LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
          WHERE si.sale_id = s.id AND coalesce(m.category_key, mbm.category_key) = ANY(p_category_keys)
        ))
    ), 0),
    'stock_value_at_cost', coalesce((
      SELECT sum(sb.qty_base_unit * coalesce(mb.unit_cost_base, m.purchase_price, 0))
      FROM public.stock_balances sb
      JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id AND m.is_active
        AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR m.category_key = ANY(p_category_keys))
    ), 0),
    'low_stock_count', coalesce((
      SELECT count(*) FROM public.stock_balances sb
      JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id AND sb.qty_base_unit <= m.reorder_level
        AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR m.category_key = ANY(p_category_keys))
    ), 0),
    'near_expiry_count', coalesce((
      SELECT count(*) FROM public.medicine_batches mb
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
        AND mb.expiry_date >= CURRENT_DATE AND mb.expiry_date <= CURRENT_DATE + interval '90 days'
        AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR m.category_key = ANY(p_category_keys))
    ), 0),
    'expired_count', coalesce((
      SELECT count(*) FROM public.medicine_batches mb
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id AND mb.expiry_date < CURRENT_DATE
        AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR m.category_key = ANY(p_category_keys))
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
          AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR m.category_key = ANY(p_category_keys))
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
          AND (p_category_keys IS NULL OR cardinality(p_category_keys) = 0 OR EXISTS (
            SELECT 1 FROM public.sale_items si
            LEFT JOIN public.medicines m ON m.id = si.medicine_id
            LEFT JOIN public.medicine_batches mb ON mb.id = si.medicine_batch_id
            LEFT JOIN public.medicines mbm ON mbm.id = mb.medicine_id
            WHERE si.sale_id = s.id AND coalesce(m.category_key, mbm.category_key) = ANY(p_category_keys)
          ))
        GROUP BY coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member')
      ) x
    ), '[]'::jsonb)
  );
END;
$$;

DROP FUNCTION IF EXISTS public.dashboard_metrics(uuid, uuid);

NOTIFY pgrst, 'reload schema';
