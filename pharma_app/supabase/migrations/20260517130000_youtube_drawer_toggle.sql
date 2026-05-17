-- Separate drawer "How to use" toggle from first-time popup.

ALTER TABLE public.app_client_config
  ADD COLUMN IF NOT EXISTS youtube_drawer_enabled boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_client_config.youtube_onboarding_enabled IS
  'When true, shows first-time onboarding popup after login (if URL set).';
COMMENT ON COLUMN public.app_client_config.youtube_drawer_enabled IS
  'When true, shows "How to use" in the navigation drawer (if URL set).';

-- Keep existing installs in sync when only onboarding was enabled.
UPDATE public.app_client_config
SET youtube_drawer_enabled = youtube_onboarding_enabled
WHERE id = 1
  AND youtube_drawer_enabled = false
  AND youtube_onboarding_enabled = true;
