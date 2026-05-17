-- YouTube onboarding: global toggle + URL on app_client_config; per-user seen timestamp.

ALTER TABLE public.app_client_config
  ADD COLUMN IF NOT EXISTS youtube_onboarding_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS youtube_onboarding_url text;

COMMENT ON COLUMN public.app_client_config.youtube_onboarding_enabled IS
  'When true, app shows first-time onboarding CTA and drawer "How to use" (if URL set).';
COMMENT ON COLUMN public.app_client_config.youtube_onboarding_url IS
  'YouTube (or external) tutorial URL opened from onboarding CTA and drawer.';

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS youtube_onboarding_seen_at timestamptz;

COMMENT ON COLUMN public.profiles.youtube_onboarding_seen_at IS
  'Set when user opens or dismisses the first-time YouTube onboarding prompt.';

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own
  ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Ops: set youtube_onboarding_enabled = true and youtube_onboarding_url on id = 1.
