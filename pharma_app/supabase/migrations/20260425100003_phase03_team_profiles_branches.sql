-- Phase 3: team_profiles + branches (README_02)

CREATE TABLE IF NOT EXISTS public.team_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL UNIQUE REFERENCES public.teams (id) ON DELETE CASCADE,
  pharmacy_name text NOT NULL,
  phone text,
  address text,
  license_number text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  name text NOT NULL,
  code text NOT NULL,
  address text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (team_id, code)
);

CREATE INDEX IF NOT EXISTS idx_branches_team ON public.branches (team_id);

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_branch_id_fkey;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_branch_id_fkey
  FOREIGN KEY (branch_id) REFERENCES public.branches (id);

ALTER TABLE public.team_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS team_profiles_select_team ON public.team_profiles;
CREATE POLICY team_profiles_select_team
  ON public.team_profiles FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = team_profiles.team_id)
    OR EXISTS (SELECT 1 FROM public.platform_admins pa WHERE pa.auth_user_id = auth.uid() AND pa.is_active)
  );

DROP POLICY IF EXISTS team_profiles_update_admin ON public.team_profiles;
CREATE POLICY team_profiles_update_admin
  ON public.team_profiles FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = team_profiles.team_id AND p.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = team_profiles.team_id AND p.role = 'admin'
    )
  );

DROP POLICY IF EXISTS team_profiles_insert_admin ON public.team_profiles;
CREATE POLICY team_profiles_insert_admin
  ON public.team_profiles FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = team_profiles.team_id AND p.role = 'admin'
    )
  );

DROP POLICY IF EXISTS branches_select_team ON public.branches;
CREATE POLICY branches_select_team
  ON public.branches FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = branches.team_id)
    OR EXISTS (SELECT 1 FROM public.platform_admins pa WHERE pa.auth_user_id = auth.uid() AND pa.is_active)
  );

DROP POLICY IF EXISTS branches_mutate_admin ON public.branches;
CREATE POLICY branches_mutate_admin
  ON public.branches FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = branches.team_id AND p.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = branches.team_id AND p.role = 'admin'
    )
  );
