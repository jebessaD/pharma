-- Profit summary joined sales to sale_items then summed grand_total / gross_profit,
-- duplicating each sale once per line. Sum sale totals and line COGS separately.

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
    SELECT s.id, s.grand_total, s.gross_profit
    FROM public.sales s
    WHERE s.team_id = p_team_id
      AND s.branch_id = p_branch_id
      AND s.created_at::date BETWEEN p_from AND p_to
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid() AND p.team_id = p_team_id AND p.is_active
      )
  ),
  revenue_agg AS (
    SELECT
      coalesce(sum(ss.grand_total), 0) AS revenue_sum,
      coalesce(sum(ss.gross_profit), 0) AS profit_sum,
      count(*)::bigint AS sale_count_sum
    FROM scoped_sales ss
  ),
  cogs_agg AS (
    SELECT coalesce(sum(si.qty * si.cost_unit_at_sale), 0) AS cogs_sum
    FROM public.sale_items si
    WHERE si.sale_id IN (SELECT id FROM scoped_sales)
  )
  SELECT
    r.revenue_sum AS revenue,
    c.cogs_sum AS cogs,
    r.profit_sum AS gross_profit,
    CASE
      WHEN r.revenue_sum = 0 THEN 0::numeric
      ELSE round((r.profit_sum / r.revenue_sum) * 100, 2)
    END AS gross_margin_pct,
    r.sale_count_sum AS sale_count
  FROM revenue_agg r
  CROSS JOIN cogs_agg c;
END;
$$;

NOTIFY pgrst, 'reload schema';
