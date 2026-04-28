-- Staff login username (per team). Auth email is derived as {username}.{team_id}@staff.internal

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS username text;

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_team_username_lower
  ON public.profiles (team_id, lower(username))
  WHERE username IS NOT NULL;

COMMENT ON COLUMN public.profiles.username IS
  'Login handle for staff; paired with team_id forms auth email username.teamuuid@staff.internal';
