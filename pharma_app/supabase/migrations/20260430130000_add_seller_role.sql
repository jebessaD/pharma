ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('admin', 'pharmacist', 'cashier', 'seller'));

CREATE OR REPLACE FUNCTION public.create_sale(
  p_branch_id uuid,
  p_items jsonb,
  p_method text,
  p_reference_no text,
  p_discount_total numeric,
  p_client_operation_id text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  v_role text;
  v_sale_id uuid;
  v_existing_sale_id uuid;
  v_subtotal numeric := 0;
  v_gross_profit numeric := 0;
  v_grand numeric;
  r jsonb;
  v_batch uuid;
  v_medicine uuid;
  v_qty numeric;
  v_price numeric;
  v_line numeric;
  v_exp date;
  v_list_price numeric;
  v_unit_cost numeric;
  v_line_profit numeric;
  v_override_reason text;
BEGIN
  SELECT team_id, role
  INTO v_team_id, v_role
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'no_profile';
  END IF;

  IF EXISTS (SELECT 1 FROM public.teams t WHERE t.id = v_team_id AND t.status <> 'active') THEN
    RAISE EXCEPTION 'team_suspended';
  END IF;

  IF p_client_operation_id IS NOT NULL THEN
    SELECT s.id
    INTO v_existing_sale_id
    FROM public.sales s
    WHERE s.team_id = v_team_id
      AND s.sold_by = auth.uid()
      AND s.client_operation_id = p_client_operation_id
    LIMIT 1;

    IF v_existing_sale_id IS NOT NULL THEN
      RETURN v_existing_sale_id;
    END IF;
  END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');

    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'bad_qty';
    END IF;
    IF v_price IS NULL OR v_price < 0 THEN
      RAISE EXCEPTION 'bad_price';
    END IF;

    SELECT mb.expiry_date, mb.medicine_id, m.selling_price
    INTO v_exp, v_medicine, v_list_price
    FROM public.medicine_batches mb
    JOIN public.medicines m ON m.id = mb.medicine_id
    WHERE mb.id = v_batch AND mb.team_id = v_team_id AND mb.branch_id = p_branch_id;

    IF v_exp IS NULL THEN
      RAISE EXCEPTION 'batch_not_found';
    END IF;
    IF v_exp < CURRENT_DATE THEN
      RAISE EXCEPTION 'expired_batch';
    END IF;

    IF v_price <> coalesce(v_list_price, 0) AND v_override_reason IS NULL THEN
      RAISE EXCEPTION 'price_override_reason_required';
    END IF;

    IF v_role IN ('cashier', 'seller') THEN
      IF v_list_price IS NULL THEN
        RAISE EXCEPTION 'missing_list_price';
      END IF;
      IF v_price < (v_list_price * 0.95) OR v_price > (v_list_price * 1.05) THEN
        RAISE EXCEPTION 'cashier_price_override_out_of_range';
      END IF;
    END IF;

    v_line := v_qty * v_price;
    v_subtotal := v_subtotal + v_line;
  END LOOP;

  v_grand := v_subtotal - coalesce(p_discount_total, 0);
  IF v_grand < 0 THEN
    RAISE EXCEPTION 'bad_discount';
  END IF;

  INSERT INTO public.sales (
    team_id,
    branch_id,
    sold_by,
    subtotal,
    discount_total,
    grand_total,
    gross_profit,
    client_operation_id
  )
  VALUES (
    v_team_id,
    p_branch_id,
    auth.uid(),
    v_subtotal,
    coalesce(p_discount_total, 0),
    v_grand,
    0,
    p_client_operation_id
  )
  RETURNING id INTO v_sale_id;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');

    SELECT mb.medicine_id, m.selling_price
    INTO v_medicine, v_list_price
    FROM public.medicine_batches mb
    JOIN public.medicines m ON m.id = mb.medicine_id
    WHERE mb.id = v_batch;

    SELECT pi.unit_cost
    INTO v_unit_cost
    FROM public.purchase_items pi
    JOIN public.purchases pu ON pu.id = pi.purchase_id
    JOIN public.medicine_batches mb ON mb.batch_no = pi.batch_no
                               AND mb.medicine_id = pi.medicine_id
                               AND mb.branch_id = pu.branch_id
    WHERE pu.team_id = v_team_id
      AND pu.branch_id = p_branch_id
      AND pu.status = 'received'
      AND mb.id = v_batch
    ORDER BY pu.created_at DESC, pi.id DESC
    LIMIT 1;

    v_line := v_qty * v_price;
    v_line_profit := v_line - (v_qty * coalesce(v_unit_cost, 0));
    v_gross_profit := v_gross_profit + v_line_profit;

    INSERT INTO public.sale_items (
      sale_id, medicine_batch_id, medicine_id, unit, qty, unit_price, line_total,
      list_unit_price, cost_unit_at_sale, line_profit, price_override_reason
    )
    VALUES (
      v_sale_id, v_batch, v_medicine, 'base', v_qty, v_price, v_line,
      coalesce(v_list_price, 0), coalesce(v_unit_cost, 0), v_line_profit, v_override_reason
    );

    PERFORM public.apply_stock_movement(
      v_team_id, p_branch_id, v_batch, 'sale_out', -v_qty, null, 'sale', v_sale_id
    );
  END LOOP;

  UPDATE public.sales
  SET gross_profit = v_gross_profit
  WHERE id = v_sale_id;

  INSERT INTO public.payments (sale_id, method, amount, reference_no)
  VALUES (v_sale_id, p_method, v_grand, p_reference_no);

  INSERT INTO public.activity_logs (
    team_id, branch_id, user_id, action_type, entity_type, entity_id, meta
  )
  VALUES (
    v_team_id,
    p_branch_id,
    auth.uid(),
    'sale_created',
    'sale',
    v_sale_id,
    jsonb_build_object('items', jsonb_array_length(p_items), 'grand_total', v_grand)
  );

  RETURN v_sale_id;
END;
$$;
