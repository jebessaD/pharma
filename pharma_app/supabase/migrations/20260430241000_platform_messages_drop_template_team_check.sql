-- Previously, platform_messages_template_team_ck required team_id IS NULL when is_template.
-- That blocked saving team-scoped drafts in the Table Editor (template + team_id).
-- RLS already hides is_template rows from members; the check is unnecessary.

ALTER TABLE public.platform_messages
  DROP CONSTRAINT IF EXISTS platform_messages_template_team_ck;
