-- platform_messages_admin_all was FOR ALL with USING (is_platform_admin only).
-- In Postgres RLS, multiple PERMISSIVE policies OR together: admins matched the
-- admin policy and could SELECT every row (templates, other teams, out of window)
-- with no row-level filter — only that account saw "everything" in the pharmacy app.
-- Keep admin INSERT/UPDATE/DELETE; let SELECT use platform_messages_select_member only.

DROP POLICY IF EXISTS platform_messages_admin_all ON public.platform_messages;

CREATE POLICY platform_messages_admin_insert ON public.platform_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.auth_user_id = auth.uid() AND pa.is_active = true
    )
  );

CREATE POLICY platform_messages_admin_update ON public.platform_messages
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.auth_user_id = auth.uid() AND pa.is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.auth_user_id = auth.uid() AND pa.is_active = true
    )
  );

CREATE POLICY platform_messages_admin_delete ON public.platform_messages
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.auth_user_id = auth.uid() AND pa.is_active = true
    )
  );
