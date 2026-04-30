-- Team-scoped platform messages + reusable templates (is_template hides rows from members).

ALTER TABLE public.platform_messages
  ADD COLUMN IF NOT EXISTS team_id uuid REFERENCES public.teams(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS is_template boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_platform_messages_team_active
  ON public.platform_messages (team_id, starts_at, ends_at)
  WHERE team_id IS NOT NULL AND NOT is_template;

DROP POLICY IF EXISTS platform_messages_select_member ON public.platform_messages;
CREATE POLICY platform_messages_select_member
  ON public.platform_messages FOR SELECT TO authenticated
  USING (
    is_template = false
    AND starts_at <= now()
    AND (ends_at IS NULL OR ends_at >= now())
    AND (
      team_id IS NULL
      OR team_id IN (
        SELECT p.team_id FROM public.profiles p
        WHERE p.id = auth.uid() AND p.team_id IS NOT NULL
      )
    )
  );

INSERT INTO public.platform_messages (title, body, severity, is_template, starts_at)
SELECT title, body, severity, true, now()
FROM (VALUES
  (
    'Payment reminder',
    'Your account has an outstanding balance. Please settle payment or contact support with your contract reference to avoid service interruption.',
    'warning'
  ),
  (
    'Contract / subscription renewal',
    'Your agreement is up for renewal. Review terms and confirm billing details with your account owner.',
    'info'
  ),
  (
    'Critical: compliance or data action required',
    'Action is required on your account (regulatory, data, or security). Contact your administrator immediately.',
    'critical'
  ),
  (
    'Scheduled maintenance notice',
    'Services may be briefly unavailable during the maintenance window. Sync and save work beforehand.',
    'info'
  )
) AS v(title, body, severity)
WHERE NOT EXISTS (
  SELECT 1 FROM public.platform_messages pm
  WHERE pm.is_template = true AND pm.title = v.title
);
