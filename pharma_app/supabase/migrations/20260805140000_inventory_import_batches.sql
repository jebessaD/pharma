-- Track spreadsheet stock imports so users can review history and undo safely.

CREATE TABLE IF NOT EXISTS public.inventory_import_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches (id) ON DELETE CASCADE,
  created_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  source_kind text NOT NULL CHECK (source_kind = ANY (ARRAY['xlsx'::text, 'csv'::text, 'photo'::text])),
  source_filename text,
  sheet_name text,
  status text NOT NULL DEFAULT 'committed'
    CHECK (status = ANY (ARRAY['committed'::text, 'undone'::text])),
  row_count int NOT NULL DEFAULT 0,
  meta jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  undone_at timestamptz,
  undone_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  undo_error text
);

CREATE TABLE IF NOT EXISTS public.inventory_import_batch_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  import_batch_id uuid NOT NULL REFERENCES public.inventory_import_batches (id) ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  medicine_id uuid NOT NULL REFERENCES public.medicines (id) ON DELETE CASCADE,
  medicine_batch_id uuid NOT NULL REFERENCES public.medicine_batches (id) ON DELETE CASCADE,
  qty_base_unit numeric NOT NULL CHECK (qty_base_unit > 0),
  medicine_created boolean NOT NULL DEFAULT false,
  source_row_index int,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_inventory_import_batches_team_created
  ON public.inventory_import_batches (team_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_import_batch_items_import
  ON public.inventory_import_batch_items (import_batch_id);

CREATE INDEX IF NOT EXISTS idx_inventory_import_batch_items_batch
  ON public.inventory_import_batch_items (medicine_batch_id);

ALTER TABLE public.inventory_import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_import_batch_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS inventory_import_batches_select_team ON public.inventory_import_batches;
CREATE POLICY inventory_import_batches_select_team
  ON public.inventory_import_batches FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = inventory_import_batches.team_id AND p.is_active = true
    )
  );

DROP POLICY IF EXISTS inventory_import_batch_items_select_team ON public.inventory_import_batch_items;
CREATE POLICY inventory_import_batch_items_select_team
  ON public.inventory_import_batch_items FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.team_id = inventory_import_batch_items.team_id AND p.is_active = true
    )
  );

-- Tracked stock-in: same as bulk_stock_in, plus import batch rows for undo.
CREATE OR REPLACE FUNCTION public.bulk_stock_in_tracked(
  p_branch_id uuid,
  p_items jsonb,
  p_source_kind text DEFAULT 'xlsx',
  p_source_filename text DEFAULT NULL,
  p_sheet_name text DEFAULT NULL,
  p_meta jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  r jsonb;
  v_mid uuid;
  v_batch_no text;
  v_exp date;
  v_qty numeric;
  v_unit_cost numeric;
  v_sell_price numeric;
  v_prev_uc numeric;
  v_prev_sp numeric;
  v_med_pp numeric;
  v_med_sp numeric;
  v_batch_id uuid;
  v_done int := 0;
  v_import_id uuid;
  v_kind text := lower(coalesce(nullif(trim(p_source_kind), ''), 'xlsx'));
  v_medicine_created boolean;
  v_row_index int;
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  SELECT team_id INTO v_team_id FROM public.profiles WHERE id = auth.uid() AND is_active = true;
  IF v_team_id IS NULL THEN RAISE EXCEPTION 'no_profile'; END IF;
  PERFORM public.assert_team_may_mutate(v_team_id);
  IF NOT EXISTS (SELECT 1 FROM public.branches b WHERE b.id = p_branch_id AND b.team_id = v_team_id) THEN
    RAISE EXCEPTION 'bad_branch';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'bulk_stock_empty';
  END IF;
  IF v_kind NOT IN ('xlsx', 'csv', 'photo') THEN
    v_kind := 'xlsx';
  END IF;

  INSERT INTO public.inventory_import_batches (
    team_id, branch_id, created_by, source_kind, source_filename, sheet_name, status, row_count, meta
  ) VALUES (
    v_team_id, p_branch_id, auth.uid(), v_kind, nullif(trim(coalesce(p_source_filename, '')), ''),
    nullif(trim(coalesce(p_sheet_name, '')), ''), 'committed', 0, p_meta
  )
  RETURNING id INTO v_import_id;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_mid := (r->>'medicine_id')::uuid;
    v_batch_no := nullif(trim(coalesce(r->>'batch_no', '')), '');
    v_exp := (r->>'expiry_date')::date;
    v_qty := (r->>'qty')::numeric;
    v_medicine_created := coalesce((r->>'medicine_created')::boolean, false);
    v_row_index := (r->>'source_row_index')::int;

    IF v_mid IS NULL OR v_exp IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'bulk_stock_bad_row';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.medicines m WHERE m.id = v_mid AND m.team_id = v_team_id) THEN
      RAISE EXCEPTION 'medicine_not_found';
    END IF;
    IF v_exp < CURRENT_DATE THEN RAISE EXCEPTION 'expiry_in_past'; END IF;

    SELECT mb.unit_cost_base, mb.sell_price_base
    INTO v_prev_uc, v_prev_sp
    FROM public.medicine_batches mb
    WHERE mb.medicine_id = v_mid AND mb.branch_id = p_branch_id AND mb.team_id = v_team_id
    ORDER BY mb.created_at DESC
    LIMIT 1;

    SELECT m.purchase_price, m.selling_price INTO v_med_pp, v_med_sp
    FROM public.medicines m WHERE m.id = v_mid;

    v_unit_cost := coalesce((r->>'unit_cost')::numeric, v_prev_uc, v_med_pp, 0);
    v_sell_price := coalesce((r->>'sell_price')::numeric, v_prev_sp, v_med_sp, 0);

    INSERT INTO public.medicine_batches (
      team_id, branch_id, medicine_id, batch_no, expiry_date,
      quantity_in_base_unit, unit_cost_base, sell_price_base
    )
    VALUES (
      v_team_id, p_branch_id, v_mid, v_batch_no, v_exp, 0, v_unit_cost, v_sell_price
    )
    RETURNING id INTO v_batch_id;

    PERFORM public.apply_stock_movement(
      v_team_id, p_branch_id, v_batch_id, 'purchase_in', v_qty,
      'bulk_stock_in', 'inventory_import', v_import_id
    );

    INSERT INTO public.inventory_import_batch_items (
      import_batch_id, team_id, medicine_id, medicine_batch_id,
      qty_base_unit, medicine_created, source_row_index
    ) VALUES (
      v_import_id, v_team_id, v_mid, v_batch_id, v_qty, v_medicine_created, v_row_index
    );

    v_done := v_done + 1;
  END LOOP;

  UPDATE public.inventory_import_batches
  SET row_count = v_done
  WHERE id = v_import_id;

  RETURN jsonb_build_object(
    'rows_applied', v_done,
    'import_batch_id', v_import_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_stock_in_tracked(uuid, jsonb, text, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bulk_stock_in_tracked(uuid, jsonb, text, text, text, jsonb) TO authenticated;

-- Undo an import only when none of its batches appear on sale_items.
CREATE OR REPLACE FUNCTION public.undo_inventory_import(p_import_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  v_branch_id uuid;
  v_status text;
  v_item record;
  v_sold_qty numeric;
  v_sold_names text[] := ARRAY[]::text[];
  v_balance numeric;
  v_undone int := 0;
  v_med_name text;
BEGIN
  SELECT team_id INTO v_team_id FROM public.profiles WHERE id = auth.uid() AND is_active = true;
  IF v_team_id IS NULL THEN RAISE EXCEPTION 'no_profile'; END IF;
  PERFORM public.assert_team_may_mutate(v_team_id);

  SELECT b.team_id, b.branch_id, b.status
  INTO v_team_id, v_branch_id, v_status
  FROM public.inventory_import_batches b
  WHERE b.id = p_import_batch_id;

  IF v_team_id IS NULL THEN RAISE EXCEPTION 'import_not_found'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.team_id = v_team_id AND p.is_active = true
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  PERFORM public.assert_branch_access(v_branch_id);

  IF v_status = 'undone' THEN
    RAISE EXCEPTION 'import_already_undone';
  END IF;

  FOR v_item IN
    SELECT i.*, m.name AS medicine_name
    FROM public.inventory_import_batch_items i
    JOIN public.medicines m ON m.id = i.medicine_id
    WHERE i.import_batch_id = p_import_batch_id
  LOOP
    SELECT coalesce(sum(si.qty), 0) INTO v_sold_qty
    FROM public.sale_items si
    WHERE si.medicine_batch_id = v_item.medicine_batch_id;

    IF v_sold_qty > 0 THEN
      v_sold_names := array_append(
        v_sold_names,
        format('%s: %s unit(s) sold', v_item.medicine_name, trim(to_char(v_sold_qty, 'FM999999990.######')))
      );
    END IF;
  END LOOP;

  IF coalesce(array_length(v_sold_names, 1), 0) > 0 THEN
    UPDATE public.inventory_import_batches
    SET undo_error = 'Cannot undo: stock from this import was already sold. ' || array_to_string(v_sold_names, '; ')
    WHERE id = p_import_batch_id;

    RAISE EXCEPTION 'import_undo_blocked: %', array_to_string(v_sold_names, '; ');
  END IF;

  FOR v_item IN
    SELECT * FROM public.inventory_import_batch_items
    WHERE import_batch_id = p_import_batch_id
  LOOP
    SELECT qty_base_unit INTO v_balance
    FROM public.stock_balances
    WHERE team_id = v_team_id
      AND branch_id = v_branch_id
      AND medicine_batch_id = v_item.medicine_batch_id;

    IF coalesce(v_balance, 0) < v_item.qty_base_unit THEN
      SELECT m.name INTO v_med_name FROM public.medicines m WHERE m.id = v_item.medicine_id;
      RAISE EXCEPTION 'import_undo_blocked: remaining stock for % is less than imported qty', coalesce(v_med_name, 'item');
    END IF;

    PERFORM public.apply_stock_movement(
      v_team_id, v_branch_id, v_item.medicine_batch_id, 'adjustment',
      -v_item.qty_base_unit, 'undo_inventory_import', 'inventory_import', p_import_batch_id
    );
    v_undone := v_undone + 1;
  END LOOP;

  UPDATE public.inventory_import_batches
  SET status = 'undone',
      undone_at = now(),
      undone_by = auth.uid(),
      undo_error = NULL
  WHERE id = p_import_batch_id;

  RETURN jsonb_build_object('undone_rows', v_undone, 'import_batch_id', p_import_batch_id);
END;
$$;

REVOKE ALL ON FUNCTION public.undo_inventory_import(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.undo_inventory_import(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
