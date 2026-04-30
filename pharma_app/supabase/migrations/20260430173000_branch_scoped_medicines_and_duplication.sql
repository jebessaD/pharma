-- Branch-scope medicine catalog and add branch-to-branch duplication RPC.

ALTER TABLE public.medicines
  ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES public.branches (id) ON DELETE CASCADE;

WITH primary_branch AS (
  SELECT DISTINCT ON (b.team_id)
    b.team_id,
    b.id AS branch_id
  FROM public.branches b
  ORDER BY
    b.team_id,
    CASE WHEN upper(coalesce(b.code, '')) = 'MAIN' THEN 0 ELSE 1 END,
    b.created_at,
    b.id
)
UPDATE public.medicines m
SET branch_id = pb.branch_id
FROM primary_branch pb
WHERE m.branch_id IS NULL
  AND pb.team_id = m.team_id;

ALTER TABLE public.medicines
  ALTER COLUMN branch_id SET NOT NULL;

ALTER TABLE public.medicines
  DROP CONSTRAINT IF EXISTS medicines_team_id_manual_code_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_medicines_team_branch_manual_unique
  ON public.medicines (team_id, branch_id, manual_code);

DROP INDEX IF EXISTS public.idx_medicines_team_barcode_unique;
CREATE UNIQUE INDEX IF NOT EXISTS idx_medicines_team_branch_barcode_unique
  ON public.medicines (team_id, branch_id, barcode)
  WHERE barcode IS NOT NULL AND is_active = true;

DROP INDEX IF EXISTS public.idx_medicines_team_barcode_lookup;
CREATE INDEX IF NOT EXISTS idx_medicines_team_branch_barcode_lookup
  ON public.medicines (team_id, branch_id, barcode);

DROP POLICY IF EXISTS medicines_team_rw ON public.medicines;
CREATE POLICY medicines_team_rw ON public.medicines FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = medicines.team_id
    )
    AND EXISTS (
      SELECT 1
      FROM public.branches b
      WHERE b.id = medicines.branch_id AND b.team_id = medicines.team_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = medicines.team_id
    )
    AND EXISTS (
      SELECT 1
      FROM public.branches b
      WHERE b.id = medicines.branch_id AND b.team_id = medicines.team_id
    )
  );

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
        m.category,
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
        s.category,
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
