-- Use stock_balances as the source of truth for expiry and stock alerts.
-- medicine_batches.quantity_in_base_unit is legacy/stale for movement-driven stock.

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
  PERFORM public.assert_branch_access(p_branch_id);

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND team_id = p_team_id AND is_active
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Expiring today through 30 days.
  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT
    p_team_id,
    p_branch_id,
    'near_expiry_30',
    'Expires within 30 days',
    m.name || ' · batch ' || coalesce(nullif(mb.batch_no, ''), 'No batch')
      || ' · exp ' || mb.expiry_date::text || ' · qty ' || sb.qty_base_unit::text,
    'medicine_batch',
    mb.id
  FROM public.stock_balances sb
  JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE sb.team_id = p_team_id
    AND sb.branch_id = p_branch_id
    AND sb.qty_base_unit > 0
    AND mb.team_id = p_team_id
    AND mb.branch_id = p_branch_id
    AND mb.expiry_date >= CURRENT_DATE
    AND mb.expiry_date <= CURRENT_DATE + interval '30 days'
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id
        AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'near_expiry_30'
        AND n.entity_type = 'medicine_batch'
        AND n.entity_id = mb.id
        AND n.created_at > CURRENT_DATE - interval '7 days'
    );

  -- Expiring after 30 days through 90 days.
  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT
    p_team_id,
    p_branch_id,
    'near_expiry_90',
    'Expires within 90 days',
    m.name || ' · batch ' || coalesce(nullif(mb.batch_no, ''), 'No batch')
      || ' · exp ' || mb.expiry_date::text || ' · qty ' || sb.qty_base_unit::text,
    'medicine_batch',
    mb.id
  FROM public.stock_balances sb
  JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE sb.team_id = p_team_id
    AND sb.branch_id = p_branch_id
    AND sb.qty_base_unit > 0
    AND mb.team_id = p_team_id
    AND mb.branch_id = p_branch_id
    AND mb.expiry_date > CURRENT_DATE + interval '30 days'
    AND mb.expiry_date <= CURRENT_DATE + interval '90 days'
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id
        AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'near_expiry_90'
        AND n.entity_type = 'medicine_batch'
        AND n.entity_id = mb.id
        AND n.created_at > CURRENT_DATE - interval '7 days'
    );

  -- Already expired batches that still have stock on hand.
  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT
    p_team_id,
    p_branch_id,
    'expired',
    'Batch expired',
    m.name || ' · batch ' || coalesce(nullif(mb.batch_no, ''), 'No batch')
      || ' · exp ' || mb.expiry_date::text || ' · qty ' || sb.qty_base_unit::text,
    'medicine_batch',
    mb.id
  FROM public.stock_balances sb
  JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE sb.team_id = p_team_id
    AND sb.branch_id = p_branch_id
    AND sb.qty_base_unit > 0
    AND mb.team_id = p_team_id
    AND mb.branch_id = p_branch_id
    AND mb.expiry_date < CURRENT_DATE
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id
        AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'expired'
        AND n.entity_type = 'medicine_batch'
        AND n.entity_id = mb.id
        AND n.created_at > CURRENT_DATE - interval '7 days'
    );

  -- Low stock at batch level.
  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT
    p_team_id,
    p_branch_id,
    'low_stock',
    'Low stock',
    m.name || ': ' || sb.qty_base_unit::text || ' left (reorder at ' || m.reorder_level::text || ')',
    'medicine',
    m.id
  FROM public.stock_balances sb
  JOIN public.medicine_batches mb ON mb.id = sb.medicine_batch_id
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE sb.team_id = p_team_id
    AND sb.branch_id = p_branch_id
    AND sb.qty_base_unit > 0
    AND coalesce(m.reorder_level, 0) > 0
    AND sb.qty_base_unit <= m.reorder_level
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id
        AND n.branch_id IS NOT DISTINCT FROM p_branch_id
        AND n.type = 'low_stock'
        AND n.entity_type = 'medicine'
        AND n.entity_id = m.id
        AND n.created_at > CURRENT_DATE - interval '1 day'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_alerts(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_alerts(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
