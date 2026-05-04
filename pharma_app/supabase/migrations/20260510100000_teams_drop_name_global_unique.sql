-- Pharmacy / org display names are not globally unique; unrelated tenants can
-- choose the same name. Identity is teams.id (UUID). The old UNIQUE(name)
-- caused bootstrap_owner_team to fail silently on /callback when a name
-- collided, leaving auth users without a profiles row.
ALTER TABLE public.teams DROP CONSTRAINT IF EXISTS teams_name_key;
