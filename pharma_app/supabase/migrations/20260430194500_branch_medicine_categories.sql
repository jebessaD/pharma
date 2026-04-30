-- Branch-scoped medicine categories with hybrid backfill.

CREATE TABLE IF NOT EXISTS public.medicine_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches (id) ON DELETE CASCADE,
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT medicine_categories_name_not_blank CHECK (char_length(btrim(name)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_medicine_categories_team_branch_normalized_unique
  ON public.medicine_categories (
    team_id,
    branch_id,
    (regexp_replace(lower(btrim(name)), '\s+', ' ', 'g'))
  );

CREATE INDEX IF NOT EXISTS idx_medicine_categories_lookup
  ON public.medicine_categories (team_id, branch_id, is_active, name);

ALTER TABLE public.medicines
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES public.medicine_categories (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_medicines_category_id
  ON public.medicines (category_id);

ALTER TABLE public.medicine_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS medicine_categories_team_rw ON public.medicine_categories;
CREATE POLICY medicine_categories_team_rw ON public.medicine_categories FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = medicine_categories.team_id
    )
    AND EXISTS (
      SELECT 1
      FROM public.branches b
      WHERE b.id = medicine_categories.branch_id AND b.team_id = medicine_categories.team_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = medicine_categories.team_id
    )
    AND EXISTS (
      SELECT 1
      FROM public.branches b
      WHERE b.id = medicine_categories.branch_id AND b.team_id = medicine_categories.team_id
    )
  );

-- 1) Seed defaults for every branch.
INSERT INTO public.medicine_categories (team_id, branch_id, name, is_active)
SELECT
  b.team_id,
  b.id AS branch_id,
  v.name,
  true
FROM public.branches b
CROSS JOIN (
  VALUES
    ('Medicine'),
    ('Consumable'),
    ('Medical Device'),
    ('Supplements'),
    ('Personal Care'),
    ('Diagnostics'),
    ('Other')
) AS v(name)
ON CONFLICT DO NOTHING;

-- 2) Map known aliases from legacy text values to seeded categories.
WITH known_aliases AS (
  SELECT * FROM (
    VALUES
      ('medicine', 'Medicine'),
      ('medicines', 'Medicine'),
      ('drug', 'Medicine'),
      ('drugs', 'Medicine'),
      ('analgesic', 'Medicine'),
      ('analgesics', 'Medicine'),
      ('antibiotic', 'Medicine'),
      ('antibiotics', 'Medicine'),
      ('painkiller', 'Medicine'),
      ('painkillers', 'Medicine'),
      ('painkiler', 'Medicine'),
      ('painkilers', 'Medicine'),
      ('otc', 'Medicine'),
      ('prescription', 'Medicine'),
      ('pharmaceutical', 'Medicine'),
      ('consumable', 'Consumable'),
      ('consumables', 'Consumable'),
      ('consmo', 'Consumable'),
      ('suppliment', 'Supplements'),
      ('supplement', 'Supplements'),
      ('supplements', 'Supplements'),
      ('device', 'Medical Device'),
      ('medical device', 'Medical Device'),
      ('medical devices', 'Medical Device'),
      ('equipment', 'Medical Device'),
      ('equipments', 'Medical Device'),
      ('personal care', 'Personal Care'),
      ('personalcare', 'Personal Care'),
      ('diagnostic', 'Diagnostics'),
      ('diagnostics', 'Diagnostics'),
      ('other', 'Other')
  ) AS t(alias_normalized, target_name)
),
mapped AS (
  SELECT
    m.id AS medicine_id,
    tc.id AS category_id
  FROM public.medicines m
  JOIN known_aliases ka
    ON ka.alias_normalized = regexp_replace(lower(btrim(coalesce(m.category, ''))), '\s+', ' ', 'g')
  JOIN public.medicine_categories tc
    ON tc.team_id = m.team_id
   AND tc.branch_id = m.branch_id
   AND regexp_replace(lower(btrim(tc.name)), '\s+', ' ', 'g') =
       regexp_replace(lower(btrim(ka.target_name)), '\s+', ' ', 'g')
  WHERE m.category_id IS NULL
)
UPDATE public.medicines m
SET category_id = mapped.category_id
FROM mapped
WHERE mapped.medicine_id = m.id;

-- 3) Auto-create unknown categories from legacy text as inactive for review.
WITH known_aliases AS (
  SELECT * FROM (
    VALUES
      ('medicine'),
      ('medicines'),
      ('drug'),
      ('drugs'),
      ('analgesic'),
      ('analgesics'),
      ('antibiotic'),
      ('antibiotics'),
      ('painkiller'),
      ('painkillers'),
      ('painkiler'),
      ('painkilers'),
      ('otc'),
      ('prescription'),
      ('pharmaceutical'),
      ('consumable'),
      ('consumables'),
      ('consmo'),
      ('suppliment'),
      ('supplement'),
      ('supplements'),
      ('device'),
      ('medical device'),
      ('medical devices'),
      ('equipment'),
      ('equipments'),
      ('personal care'),
      ('personalcare'),
      ('diagnostic'),
      ('diagnostics'),
      ('other')
  ) AS t(alias_normalized)
),
unknown_legacy AS (
  SELECT
    m.team_id,
    m.branch_id,
    initcap(regexp_replace(btrim(m.category), '\s+', ' ', 'g')) AS display_name
  FROM public.medicines m
  LEFT JOIN known_aliases ka
    ON ka.alias_normalized = regexp_replace(lower(btrim(coalesce(m.category, ''))), '\s+', ' ', 'g')
  WHERE m.category_id IS NULL
    AND btrim(coalesce(m.category, '')) <> ''
    AND ka.alias_normalized IS NULL
  GROUP BY
    m.team_id,
    m.branch_id,
    initcap(regexp_replace(btrim(m.category), '\s+', ' ', 'g'))
)
INSERT INTO public.medicine_categories (team_id, branch_id, name, is_active)
SELECT
  u.team_id,
  u.branch_id,
  u.display_name,
  false
FROM unknown_legacy u
ON CONFLICT DO NOTHING;

-- 4) Fill remaining matches by normalized text.
WITH matched AS (
  SELECT
    m.id AS medicine_id,
    mc.id AS category_id
  FROM public.medicines m
  JOIN public.medicine_categories mc
    ON mc.team_id = m.team_id
   AND mc.branch_id = m.branch_id
   AND regexp_replace(lower(btrim(mc.name)), '\s+', ' ', 'g') =
       regexp_replace(lower(btrim(coalesce(m.category, ''))), '\s+', ' ', 'g')
  WHERE m.category_id IS NULL
    AND btrim(coalesce(m.category, '')) <> ''
)
UPDATE public.medicines m
SET category_id = matched.category_id
FROM matched
WHERE matched.medicine_id = m.id;

-- 5) Final fallback to branch "Other".
WITH fallback AS (
  SELECT
    m.id AS medicine_id,
    mc.id AS category_id
  FROM public.medicines m
  JOIN public.medicine_categories mc
    ON mc.team_id = m.team_id
   AND mc.branch_id = m.branch_id
   AND regexp_replace(lower(btrim(mc.name)), '\s+', ' ', 'g') = 'other'
  WHERE m.category_id IS NULL
)
UPDATE public.medicines m
SET category_id = fallback.category_id
FROM fallback
WHERE fallback.medicine_id = m.id;

-- 6) Replace duplication RPC to preserve category mapping.
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
    WITH source_categories AS (
      SELECT DISTINCT
        v_team_id AS team_id,
        p_target_branch_id AS branch_id,
        coalesce(sc.name, m.category, 'Other') AS category_name
      FROM public.medicines m
      LEFT JOIN public.medicine_categories sc ON sc.id = m.category_id
      WHERE m.team_id = v_team_id
        AND m.branch_id = p_source_branch_id
    ),
    ensure_categories AS (
      INSERT INTO public.medicine_categories (
        team_id,
        branch_id,
        name,
        is_active
      )
      SELECT
        s.team_id,
        s.branch_id,
        s.category_name,
        true
      FROM source_categories s
      ON CONFLICT DO NOTHING
      RETURNING id
    ),
    src AS (
      SELECT
        m.team_id,
        p_target_branch_id AS branch_id,
        m.name,
        m.generic_name,
        m.manual_code,
        m.barcode,
        coalesce(sc.name, m.category, 'Other') AS category_name,
        tc.id AS category_id,
        m.purchase_price,
        m.selling_price,
        m.reorder_level,
        m.is_active
      FROM public.medicines m
      LEFT JOIN public.medicine_categories sc ON sc.id = m.category_id
      JOIN public.medicine_categories tc
        ON tc.team_id = v_team_id
       AND tc.branch_id = p_target_branch_id
       AND regexp_replace(lower(btrim(tc.name)), '\s+', ' ', 'g') =
           regexp_replace(lower(btrim(coalesce(sc.name, m.category, 'Other'))), '\s+', ' ', 'g')
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
        category_id,
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
        s.category_name,
        s.category_id,
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
