-- Phase 7: expiry views + notifications + refresh_alerts (README_06 + README_11)

CREATE OR REPLACE VIEW public.v_near_expiry_batches AS
SELECT mb.*, m.name AS medicine_name
FROM public.medicine_batches mb
JOIN public.medicines m ON m.id = mb.medicine_id
WHERE mb.expiry_date >= CURRENT_DATE
  AND mb.expiry_date <= CURRENT_DATE + interval '90 days';

CREATE OR REPLACE VIEW public.v_expired_batches AS
SELECT mb.*, m.name AS medicine_name
FROM public.medicine_batches mb
JOIN public.medicines m ON m.id = mb.medicine_id
WHERE mb.expiry_date < CURRENT_DATE;

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  branch_id uuid REFERENCES public.branches (id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('low_stock', 'near_expiry', 'expired')),
  title text NOT NULL,
  message text NOT NULL,
  entity_type text,
  entity_id uuid,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_team ON public.notifications (team_id);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notifications_team ON public.notifications;
CREATE POLICY notifications_team ON public.notifications FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = notifications.team_id))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = notifications.team_id));

CREATE OR REPLACE FUNCTION public.refresh_alerts(p_team_id uuid, p_branch_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND team_id = p_team_id AND is_active
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO public.notifications (team_id, branch_id, type, title, message, entity_type, entity_id)
  SELECT p_team_id, p_branch_id, 'near_expiry', 'Near expiry',
    m.name || ' batch ' || mb.batch_no,
    'medicine_batch', mb.id
  FROM public.medicine_batches mb
  JOIN public.medicines m ON m.id = mb.medicine_id
  WHERE mb.team_id = p_team_id AND mb.branch_id = p_branch_id
    AND mb.expiry_date >= CURRENT_DATE
    AND mb.expiry_date <= CURRENT_DATE + interval '90 days'
    AND mb.quantity_in_base_unit > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.team_id = p_team_id
        AND (n.branch_id = p_branch_id OR (n.branch_id IS NULL AND p_branch_id IS NULL))
        AND n.type = 'near_expiry'
        AND n.entity_id = mb.id
        AND (n.created_at::date = CURRENT_DATE)
    );

END;
$$;

REVOKE ALL ON FUNCTION public.refresh_alerts(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_alerts(uuid, uuid) TO authenticated;
