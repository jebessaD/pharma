-- Phase 11: team-admin profile management policy

DROP POLICY IF EXISTS profiles_mutate_team_admin ON public.profiles;
CREATE POLICY profiles_mutate_team_admin
  ON public.profiles FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles me
      WHERE me.id = auth.uid()
        AND me.team_id = profiles.team_id
        AND me.role = 'admin'
        AND me.is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.profiles me
      WHERE me.id = auth.uid()
        AND me.team_id = profiles.team_id
        AND me.role = 'admin'
        AND me.is_active = true
    )
  );
