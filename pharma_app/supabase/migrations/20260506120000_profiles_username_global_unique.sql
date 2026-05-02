-- Staff usernames are globally unique (case-insensitive). Auth email: {username}@staff.internal
-- Resolve duplicate usernames across teams before applying in production.

DROP INDEX IF EXISTS public.idx_profiles_team_username_lower;

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_username_lower_global
  ON public.profiles (lower(trim(username)))
  WHERE username IS NOT NULL AND trim(username) <> '';

COMMENT ON COLUMN public.profiles.username IS
  'Globally unique staff login handle; Auth email is {username}@staff.internal';
