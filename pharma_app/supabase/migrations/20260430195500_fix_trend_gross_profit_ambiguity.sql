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
  SELECT
    g.grp AS period_start,
    CASE
      WHEN p_granularity = 'day' THEN to_char(g.grp, 'YYYY-MM-DD')
      WHEN p_granularity = 'month' THEN to_char(g.grp, 'YYYY-MM')
      ELSE to_char(g.grp, 'YYYY')
    END AS period_label,
    g.cnt AS sale_count,
    g.rev AS revenue,
    g.prof AS gross_profit
  FROM grouped g
  ORDER BY g.grp;
END;
$$;
