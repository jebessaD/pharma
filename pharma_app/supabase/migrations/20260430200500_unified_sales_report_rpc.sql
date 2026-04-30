CREATE OR REPLACE FUNCTION public.rpc_report_sales_unified(
  p_team_id uuid,
  p_branch_id uuid,
  p_from date,
  p_to date,
  p_sold_by uuid DEFAULT NULL,
  p_min_amount numeric DEFAULT NULL,
  p_max_amount numeric DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_overrides_only boolean DEFAULT false
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.created_at AS sold_at,
    s.id AS sale_id,
    coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member') AS seller_name,
    m.name AS medicine_name,
    coalesce(m.manual_code, '') AS medicine_code,
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
  LEFT JOIN public.profiles p ON p.id = s.sold_by AND p.team_id = p_team_id
  LEFT JOIN public.payments pay ON pay.sale_id = s.id
  WHERE s.team_id = p_team_id
    AND s.branch_id = p_branch_id
    AND s.created_at::date BETWEEN p_from AND p_to
    AND (p_sold_by IS NULL OR s.sold_by = p_sold_by)
    AND (p_min_amount IS NULL OR s.grand_total >= p_min_amount)
    AND (p_max_amount IS NULL OR s.grand_total <= p_max_amount)
    AND (p_payment_method IS NULL OR pay.method = p_payment_method)
    AND (NOT p_overrides_only OR si.price_override_reason IS NOT NULL)
    AND EXISTS (
      SELECT 1
      FROM public.profiles me
      WHERE me.id = auth.uid() AND me.team_id = p_team_id AND me.is_active
    )
  ORDER BY s.created_at DESC, s.id DESC, si.id ASC;
$$;

REVOKE ALL ON FUNCTION public.rpc_report_sales_unified(
  uuid, uuid, date, date, uuid, numeric, numeric, text, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_report_sales_unified(
  uuid, uuid, date, date, uuid, numeric, numeric, text, boolean
) TO authenticated;
