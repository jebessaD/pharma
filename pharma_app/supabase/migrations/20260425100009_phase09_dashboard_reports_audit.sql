-- Phase 9: activity_logs + dashboard + reports (README_10 + README_12 + README_14)

CREATE TABLE IF NOT EXISTS public.activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  branch_id uuid REFERENCES public.branches (id) ON DELETE SET NULL,
  user_id uuid REFERENCES auth.users (id),
  action_type text NOT NULL,
  entity_type text,
  entity_id uuid,
  meta jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_activity_team ON public.activity_logs (team_id);

ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS activity_logs_team ON public.activity_logs;
CREATE POLICY activity_logs_team ON public.activity_logs FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = activity_logs.team_id));

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

CREATE OR REPLACE FUNCTION public.rpc_report_sales_summary(
  p_team_id uuid,
  p_branch_id uuid,
  p_from date,
  p_to date
) RETURNS TABLE (sale_id uuid, sold_at timestamptz, grand_total numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.id, s.created_at, s.grand_total
  FROM public.sales s
  WHERE s.team_id = p_team_id AND s.branch_id = p_branch_id
    AND s.created_at::date BETWEEN p_from AND p_to
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = p_team_id);
$$;

CREATE OR REPLACE FUNCTION public.rpc_report_stock_balance(
  p_team_id uuid,
  p_branch_id uuid
) RETURNS TABLE (medicine_name text, batch_no text, qty numeric, expiry_date date)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT m.name, mb.batch_no, sb.qty_base_unit, mb.expiry_date
  FROM public.stock_balances sb
  JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE sb.team_id = p_team_id AND sb.branch_id = p_branch_id
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = p_team_id);
$$;

CREATE OR REPLACE FUNCTION public.rpc_report_expiry_status(
  p_team_id uuid,
  p_branch_id uuid,
  p_threshold_days int
) RETURNS TABLE (medicine_name text, batch_no text, expiry_date date, days_left int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT m.name, mb.batch_no, mb.expiry_date,
    (mb.expiry_date - CURRENT_DATE)::int
  FROM public.medicine_batches mb
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
    AND mb.expiry_date <= CURRENT_DATE + (p_threshold_days || ' days')::interval
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = p_team_id);
$$;

REVOKE ALL ON FUNCTION public.rpc_report_sales_summary(uuid, uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_report_sales_summary(uuid, uuid, date, date) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_report_stock_balance(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_report_stock_balance(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_report_expiry_status(uuid, uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_report_expiry_status(uuid, uuid, int) TO authenticated;
