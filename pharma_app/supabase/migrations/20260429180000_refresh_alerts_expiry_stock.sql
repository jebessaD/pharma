-- Richer alerts: 30d / 90d near-expiry, expired batches, low stock; keep legacy near_expiry valid.

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (
    type IN (
      'low_stock',
      'near_expiry',
      'near_expiry_30',
      'near_expiry_90',
      'expired'
    )
  );

CREATE OR REPLACE FUNCTION public.refresh_alerts(p_team_id uuid, p_branch_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND team_id = p_team_id AND is_active
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Near expiry: 1–30 days (urgent window)
  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT
    p_team_id,
    p_branch_id,
    'near_expiry_30',
    'Expires within 30 days',
    m.name || ' · batch ' || mb.batch_no || ' · exp ' || mb.expiry_date::text,
    'medicine_batch',
    mb.id
  FROM public.medicine_batches mb
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE mb.team_id = p_team_id
    AND mb.branch_id = p_branch_id
    AND mb.expiry_date > CURRENT_DATE
    AND mb.expiry_date <= CURRENT_DATE + interval '30 days'
    AND mb.quantity_in_base_unit > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id
        AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'near_expiry_30'
        AND n.entity_id = mb.id
        AND n.created_at::date = CURRENT_DATE
    );

  -- Near expiry: 31–90 days
  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT
    p_team_id,
    p_branch_id,
    'near_expiry_90',
    'Expires within 90 days',
    m.name || ' · batch ' || mb.batch_no || ' · exp ' || mb.expiry_date::text,
    'medicine_batch',
    mb.id
  FROM public.medicine_batches mb
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE mb.team_id = p_team_id
    AND mb.branch_id = p_branch_id
    AND mb.expiry_date > CURRENT_DATE + interval '30 days'
    AND mb.expiry_date <= CURRENT_DATE + interval '90 days'
    AND mb.quantity_in_base_unit > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id
        AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'near_expiry_90'
        AND n.entity_id = mb.id
        AND n.created_at::date = CURRENT_DATE
    );

  -- Legacy bucket: same as old migration (0–90) as type near_expiry (optional daily digest)
  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT
    p_team_id,
    p_branch_id,
    'near_expiry',
    'Near expiry',
    m.name || ' · batch ' || mb.batch_no || ' · exp ' || mb.expiry_date::text,
    'medicine_batch',
    mb.id
  FROM public.medicine_batches mb
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE mb.team_id = p_team_id
    AND mb.branch_id = p_branch_id
    AND mb.expiry_date >= CURRENT_DATE
    AND mb.expiry_date <= CURRENT_DATE + interval '90 days'
    AND mb.quantity_in_base_unit > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id
        AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'near_expiry'
        AND n.entity_id = mb.id
        AND n.created_at::date = CURRENT_DATE
    );

  -- Expired batches still holding quantity
  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT
    p_team_id,
    p_branch_id,
    'expired',
    'Expired batch',
    m.name || ' · batch ' || mb.batch_no || ' expired ' || mb.expiry_date::text
      || CASE
        WHEN coalesce(sb.qty_base_unit, 0) <= 0 THEN ' (out of stock)'
        ELSE ' (qty ' || sb.qty_base_unit::text || ')'
      END,
    'medicine_batch',
    mb.id
  FROM public.medicine_batches mb
  JOIN public.medicines m ON m.id = mb.medicine_id
  LEFT JOIN public.stock_balances sb
    ON sb.medicine_batch_id = mb.id
    AND sb.team_id = mb.team_id
    AND sb.branch_id = mb.branch_id
  WHERE mb.team_id = p_team_id
    AND mb.branch_id = p_branch_id
    AND mb.expiry_date < CURRENT_DATE
    AND (
      coalesce(sb.qty_base_unit, 0) > 0
      OR mb.quantity_in_base_unit > 0
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id
        AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'expired'
        AND n.entity_id = mb.id
        AND n.created_at::date = CURRENT_DATE
    );

  -- Low stock at batch level (qty at or below reorder on parent medicine)
  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT
    p_team_id,
    p_branch_id,
    'low_stock',
    'Low stock',
    m.name || ' · batch ' || mb.batch_no || ' · qty ' || coalesce(sb.qty_base_unit, 0)::text
      || ' (reorder at ' || m.reorder_level::text || ')',
    'medicine_batch',
    mb.id
  FROM public.stock_balances sb
  JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE sb.team_id = p_team_id
    AND sb.branch_id = p_branch_id
    AND coalesce(m.reorder_level, 0) > 0
    AND coalesce(sb.qty_base_unit, 0) <= m.reorder_level
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id
        AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'low_stock'
        AND n.entity_id = mb.id
        AND n.created_at::date = CURRENT_DATE
    );
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_alerts(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_alerts(uuid, uuid) TO authenticated;
