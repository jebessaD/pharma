-- Branch medicine_categories removed; medicines carry category_key only.

CREATE OR REPLACE FUNCTION public.duplicate_branch_medicines(
  p_source_branch_id uuid,
  p_target_branch_id uuid,
  p_skip_existing boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  v_source_team uuid;
  v_target_team uuid;
  v_inserted int := 0;
  v_skipped int := 0;
BEGIN
  SELECT team_id INTO v_team_id
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'no_profile';
  END IF;

  SELECT team_id INTO v_source_team
  FROM public.branches
  WHERE id = p_source_branch_id;

  SELECT team_id INTO v_target_team
  FROM public.branches
  WHERE id = p_target_branch_id;

  IF v_source_team IS NULL OR v_target_team IS NULL THEN
    RAISE EXCEPTION 'branch_not_found';
  END IF;

  IF v_source_team <> v_target_team OR v_source_team <> v_team_id THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF p_source_branch_id = p_target_branch_id THEN
    RAISE EXCEPTION 'same_branch';
  END IF;

  IF p_skip_existing THEN
    WITH src AS (
      SELECT
        m.team_id,
        p_target_branch_id AS branch_id,
        m.name,
        m.generic_name,
        m.manual_code,
        m.barcode,
        m.category_key,
        m.purchase_price,
        m.selling_price,
        m.reorder_level,
        m.is_active
      FROM public.medicines m
      WHERE m.team_id = v_team_id
        AND m.branch_id = p_source_branch_id
    ),
    ins AS (
      INSERT INTO public.medicines (
        team_id,
        branch_id,
        name,
        generic_name,
        manual_code,
        barcode,
        category,
        category_key,
        purchase_price,
        selling_price,
        reorder_level,
        is_active
      )
      SELECT
        s.team_id,
        s.branch_id,
        s.name,
        s.generic_name,
        s.manual_code,
        s.barcode,
        NULL::text,
        s.category_key,
        s.purchase_price,
        s.selling_price,
        s.reorder_level,
        s.is_active
      FROM src s
      ON CONFLICT (team_id, branch_id, manual_code) DO NOTHING
      RETURNING 1
    )
    SELECT count(*) INTO v_inserted FROM ins;

    SELECT count(*) INTO v_skipped
    FROM public.medicines m
    WHERE m.team_id = v_team_id
      AND m.branch_id = p_source_branch_id
      AND EXISTS (
        SELECT 1
        FROM public.medicines t
        WHERE t.team_id = v_team_id
          AND t.branch_id = p_target_branch_id
          AND t.manual_code = m.manual_code
      );
  ELSE
    RAISE EXCEPTION 'conflict_mode_not_supported';
  END IF;

  RETURN jsonb_build_object(
    'copied_count', v_inserted,
    'skipped_count', v_skipped
  );
END;
$$;

REVOKE ALL ON FUNCTION public.duplicate_branch_medicines(uuid, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.duplicate_branch_medicines(uuid, uuid, boolean) TO authenticated;

ALTER TABLE public.medicines
  DROP COLUMN IF EXISTS category_id CASCADE;

DROP INDEX IF EXISTS public.idx_medicines_category_id;

DROP POLICY IF EXISTS medicine_categories_team_rw ON public.medicine_categories;

DROP TABLE IF EXISTS public.medicine_categories;

NOTIFY pgrst, 'reload schema';
