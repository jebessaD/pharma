-- Index for staff-scoped sales queries
CREATE INDEX IF NOT EXISTS idx_sales_team_branch_sold_by_created
  ON public.sales (team_id, branch_id, sold_by, created_at DESC);

-- Aggregate sales by logged-in staff (profiles) for a date range
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.rpc_report_sales_by_staff(uuid, uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_report_sales_by_staff(uuid, uuid, date, date) TO authenticated;

-- Dashboard: add last-7-days sales by staff (same window as top_sellers_7d)
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
    'sales_7d_total', coalesce((
      SELECT sum(grand_total) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND s.created_at::date >= (CURRENT_DATE - 6)
    ), 0),
    'sales_mtd_total', coalesce((
      SELECT sum(grand_total) FROM public.sales s
      WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
        AND date_trunc('month', s.created_at) = date_trunc('month', now())
    ), 0),
    'stock_value_at_cost', coalesce((
      SELECT sum(sb.qty_base_unit * m.purchase_price) FROM public.stock_balances sb
      JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
      JOIN public.medicines m ON m.id = mb.medicine_id
      WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id
        AND m.is_active
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
        GROUP BY coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member')
      ) x
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dashboard_metrics(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dashboard_metrics(uuid, uuid) TO authenticated;
