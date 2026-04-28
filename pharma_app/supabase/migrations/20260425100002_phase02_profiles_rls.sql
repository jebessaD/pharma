-- Phase 2: profiles + team member access to own team (README_03)

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  branch_id uuid,
  full_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('admin', 'pharmacist', 'cashier')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profiles_team ON public.profiles (team_id);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
DROP POLICY IF EXISTS profiles_select_team ON public.profiles;
CREATE POLICY profiles_select_team
  ON public.profiles FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles me
      WHERE me.id = auth.uid() AND me.team_id = profiles.team_id
    )
  );

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own
  ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Team members can read their team row if active and profile active
DROP POLICY IF EXISTS teams_select_platform_admin ON public.teams;
CREATE POLICY teams_select_platform_or_member ON public.teams FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.auth_user_id = auth.uid() AND pa.is_active = true
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_active = true AND p.team_id = teams.id
    )
  );

COMMENT ON TABLE public.profiles IS 'Seed rows after creating auth users: INSERT profiles (id, team_id, full_name, role) ...';
