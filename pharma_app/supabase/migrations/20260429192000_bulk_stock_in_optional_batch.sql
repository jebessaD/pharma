-- Allow bulk stock-in rows with no batch number (NULL in medicine_batches).

CREATE OR REPLACE FUNCTION public.bulk_stock_in(p_branch_id uuid, p_items jsonb)
RETURNS jsonb
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
  v_batch_id uuid;
  v_done int := 0;
BEGIN
  SELECT team_id INTO v_team_id
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'no_profile';
  END IF;

  IF EXISTS (SELECT 1 FROM public.teams t WHERE t.id = v_team_id AND t.status <> 'active') THEN
    RAISE EXCEPTION 'team_suspended';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.branches b
    WHERE b.id = p_branch_id AND b.team_id = v_team_id
  ) THEN
    RAISE EXCEPTION 'bad_branch';
  END IF;

  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'bulk_stock_empty';
  END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_mid := (r->>'medicine_id')::uuid;
    v_batch_no := nullif(trim(coalesce(r->>'batch_no', '')), '');
    v_exp := (r->>'expiry_date')::date;
    v_qty := (r->>'qty')::numeric;

    IF v_mid IS NULL OR v_exp IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'bulk_stock_bad_row';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.medicines m
      WHERE m.id = v_mid AND m.team_id = v_team_id
    ) THEN
      RAISE EXCEPTION 'medicine_not_found';
    END IF;

    IF v_exp < CURRENT_DATE THEN
      RAISE EXCEPTION 'expiry_in_past';
    END IF;

    INSERT INTO public.medicine_batches (
      team_id, branch_id, medicine_id, batch_no, expiry_date, quantity_in_base_unit
    ) VALUES (v_team_id, p_branch_id, v_mid, v_batch_no, v_exp, 0)
    RETURNING id INTO v_batch_id;

    PERFORM public.apply_stock_movement(
      v_team_id,
      p_branch_id,
      v_batch_id,
      'purchase_in',
      v_qty,
      'bulk_stock_in',
      'bulk_stock_in',
      NULL
    );

    v_done := v_done + 1;
  END LOOP;

  RETURN jsonb_build_object('rows_applied', v_done);
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_stock_in(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bulk_stock_in(uuid, jsonb) TO authenticated;
