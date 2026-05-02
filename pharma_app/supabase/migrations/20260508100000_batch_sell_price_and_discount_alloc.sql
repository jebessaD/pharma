-- Batch-level sell price + proportional discount allocation in profit.
--
-- 1. medicine_batches.sell_price_base — intended selling price set at stock-in.
-- 2. sale_items.discount_alloc — proportional share of cart discount per line.
-- 3. Rewrite bulk_stock_in, receive_purchase, create_sale to use new columns.
-- 4. purchase_items.sell_price — optional sell price captured at purchase entry.

--------------------------------------------------------------------
-- Schema additions
--------------------------------------------------------------------

ALTER TABLE public.medicine_batches
  ADD COLUMN IF NOT EXISTS sell_price_base numeric(12, 2);

COMMENT ON COLUMN public.medicine_batches.sell_price_base IS
  'Intended selling price per base unit for this batch. Set at stock-in/receive. POS uses as default list price.';

ALTER TABLE public.sale_items
  ADD COLUMN IF NOT EXISTS discount_alloc numeric(12, 2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.sale_items.discount_alloc IS
  'Proportional share of the cart-level discount allocated to this line for profit calculation.';

ALTER TABLE public.purchase_items
  ADD COLUMN IF NOT EXISTS sell_price numeric(12, 2);

COMMENT ON COLUMN public.purchase_items.sell_price IS
  'Optional intended selling price per base unit captured at purchase entry.';

--------------------------------------------------------------------
-- Backfill sell_price_base from medicines.selling_price for existing batches
--------------------------------------------------------------------

UPDATE public.medicine_batches mb
SET sell_price_base = m.selling_price
FROM public.medicines m
WHERE mb.medicine_id = m.id
  AND mb.sell_price_base IS NULL
  AND m.selling_price IS NOT NULL
  AND m.selling_price > 0;

--------------------------------------------------------------------
-- bulk_stock_in — accepts sell_price per item, inherits from prev batch
--------------------------------------------------------------------

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
  v_unit_cost numeric;
  v_sell_price numeric;
  v_prev_uc numeric;
  v_prev_sp numeric;
  v_med_pp numeric;
  v_med_sp numeric;
  v_batch_id uuid;
  v_done int := 0;
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

  FOR r IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_mid := (r->>'medicine_id')::uuid;
    v_batch_no := nullif(trim(coalesce(r->>'batch_no', '')), '');
    v_exp := (r->>'expiry_date')::date;
    v_qty := (r->>'qty')::numeric;

    IF v_mid IS NULL OR v_exp IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'bulk_stock_bad_row';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.medicines m WHERE m.id = v_mid AND m.team_id = v_team_id) THEN
      RAISE EXCEPTION 'medicine_not_found';
    END IF;
    IF v_exp < CURRENT_DATE THEN RAISE EXCEPTION 'expiry_in_past'; END IF;

    -- Fetch previous batch prices (most recent at same branch)
    SELECT mb.unit_cost_base, mb.sell_price_base
    INTO v_prev_uc, v_prev_sp
    FROM public.medicine_batches mb
    WHERE mb.medicine_id = v_mid AND mb.branch_id = p_branch_id AND mb.team_id = v_team_id
    ORDER BY mb.created_at DESC
    LIMIT 1;

    -- Medicine-level fallbacks
    SELECT m.purchase_price, m.selling_price INTO v_med_pp, v_med_sp
    FROM public.medicines m WHERE m.id = v_mid;

    -- Resolve unit_cost: payload -> prev batch -> medicine -> 0
    v_unit_cost := coalesce((r->>'unit_cost')::numeric, v_prev_uc, v_med_pp, 0);

    -- Resolve sell_price: payload -> prev batch -> medicine -> 0
    v_sell_price := coalesce((r->>'sell_price')::numeric, v_prev_sp, v_med_sp, 0);

    INSERT INTO public.medicine_batches (team_id, branch_id, medicine_id, batch_no, expiry_date, quantity_in_base_unit, unit_cost_base, sell_price_base)
    VALUES (v_team_id, p_branch_id, v_mid, v_batch_no, v_exp, 0, v_unit_cost, v_sell_price)
    RETURNING id INTO v_batch_id;

    PERFORM public.apply_stock_movement(v_team_id, p_branch_id, v_batch_id, 'purchase_in', v_qty, 'bulk_stock_in', 'bulk_stock_in', NULL);
    v_done := v_done + 1;
  END LOOP;

  RETURN jsonb_build_object('rows_applied', v_done);
END;
$$;

--------------------------------------------------------------------
-- receive_purchase — writes sell_price_base from purchase_items.sell_price
--------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.receive_purchase(p_purchase_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pu RECORD;
  it RECORD;
  v_batch uuid;
  v_sell_price numeric;
  v_prev_sp numeric;
  v_med_sp numeric;
BEGIN
  SELECT * INTO pu FROM public.purchases WHERE id = p_purchase_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  PERFORM public.assert_branch_access(pu.branch_id);

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND team_id = pu.team_id AND is_active) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF pu.status = 'received' THEN RETURN; END IF;

  FOR it IN SELECT * FROM public.purchase_items WHERE purchase_id = pu.id LOOP
    -- Determine sell price: purchase_item -> prev batch at same branch -> medicine
    SELECT mb.sell_price_base INTO v_prev_sp
    FROM public.medicine_batches mb
    WHERE mb.medicine_id = it.medicine_id AND mb.branch_id = pu.branch_id AND mb.team_id = pu.team_id
    ORDER BY mb.created_at DESC LIMIT 1;

    SELECT m.selling_price INTO v_med_sp
    FROM public.medicines m WHERE m.id = it.medicine_id;

    v_sell_price := coalesce(it.sell_price, v_prev_sp, v_med_sp, 0);

    INSERT INTO public.medicine_batches (team_id, branch_id, medicine_id, batch_no, expiry_date, quantity_in_base_unit, unit_cost_base, sell_price_base)
    VALUES (pu.team_id, pu.branch_id, it.medicine_id, it.batch_no, it.expiry_date, 0, it.unit_cost, v_sell_price)
    RETURNING id INTO v_batch;

    PERFORM public.apply_stock_movement(pu.team_id, pu.branch_id, v_batch, 'purchase_in', it.qty_base_unit, null, 'purchase', pu.id);
  END LOOP;

  UPDATE public.purchases SET status = 'received' WHERE id = pu.id;
END;
$$;

--------------------------------------------------------------------
-- create_sale — use batch sell_price_base for list price check,
--               allocate discount proportionally into line profit
--------------------------------------------------------------------

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
  v_discount numeric;
  r jsonb;
  v_batch uuid;
  v_medicine uuid;
  v_qty numeric;
  v_price numeric;
  v_line numeric;
  v_exp date;
  v_list_price numeric;
  v_batch_sp numeric;
  v_batch_uc numeric;
  v_med_pp numeric;
  v_med_sp numeric;
  v_pi_uc numeric;
  v_unit_cost numeric;
  v_line_profit numeric;
  v_discount_alloc numeric;
  v_override_reason text;
BEGIN
  PERFORM public.assert_branch_access(p_branch_id);

  SELECT team_id, role INTO v_team_id, v_role
  FROM public.profiles WHERE id = auth.uid() AND is_active = true;
  IF v_team_id IS NULL THEN RAISE EXCEPTION 'no_profile'; END IF;

  PERFORM public.assert_team_may_mutate(v_team_id);

  IF p_client_operation_id IS NOT NULL THEN
    SELECT s.id INTO v_existing_sale_id FROM public.sales s
    WHERE s.team_id = v_team_id AND s.sold_by = auth.uid()
      AND s.client_operation_id = p_client_operation_id LIMIT 1;
    IF v_existing_sale_id IS NOT NULL THEN RETURN v_existing_sale_id; END IF;
  END IF;

  v_discount := coalesce(p_discount_total, 0);

  -- First pass: validate items and compute subtotal
  FOR r IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');
    IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'bad_qty'; END IF;
    IF v_price IS NULL OR v_price < 0 THEN RAISE EXCEPTION 'bad_price'; END IF;

    SELECT mb.expiry_date, mb.medicine_id, mb.sell_price_base, m.selling_price
    INTO v_exp, v_medicine, v_batch_sp, v_med_sp
    FROM public.medicine_batches mb JOIN public.medicines m ON m.id = mb.medicine_id
    WHERE mb.id = v_batch AND mb.team_id = v_team_id AND mb.branch_id = p_branch_id;

    IF v_exp IS NULL THEN RAISE EXCEPTION 'batch_not_found'; END IF;
    IF v_exp < CURRENT_DATE THEN RAISE EXCEPTION 'expired_batch'; END IF;

    -- List price for cashier/seller band check: batch sell price first, then medicine
    v_list_price := coalesce(v_batch_sp, v_med_sp);

    IF v_role IN ('cashier', 'seller') THEN
      IF v_list_price IS NULL THEN RAISE EXCEPTION 'missing_list_price'; END IF;
      IF v_price < (v_list_price * 0.95) OR v_price > (v_list_price * 1.05) THEN
        RAISE EXCEPTION 'cashier_price_override_out_of_range';
      END IF;
    END IF;

    v_line := v_qty * v_price;
    v_subtotal := v_subtotal + v_line;
  END LOOP;

  v_grand := v_subtotal - v_discount;
  IF v_grand < 0 THEN RAISE EXCEPTION 'bad_discount'; END IF;

  INSERT INTO public.sales (team_id, branch_id, sold_by, subtotal, discount_total, grand_total, gross_profit, client_operation_id)
  VALUES (v_team_id, p_branch_id, auth.uid(), v_subtotal, v_discount, v_grand, 0, p_client_operation_id)
  RETURNING id INTO v_sale_id;

  -- Second pass: insert sale_items with COGS and stock movements
  FOR r IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');

    SELECT mb.medicine_id, mb.sell_price_base, mb.unit_cost_base, m.selling_price, m.purchase_price
    INTO v_medicine, v_batch_sp, v_batch_uc, v_med_sp, v_med_pp
    FROM public.medicine_batches mb JOIN public.medicines m ON m.id = mb.medicine_id WHERE mb.id = v_batch;

    -- COGS fallback: batch unit_cost_base -> purchase_items -> medicine purchase_price
    SELECT pi.unit_cost INTO v_pi_uc
    FROM public.purchase_items pi
    JOIN public.purchases pu ON pu.id = pi.purchase_id
    JOIN public.medicine_batches mb2 ON mb2.batch_no IS NOT DISTINCT FROM pi.batch_no
      AND mb2.medicine_id = pi.medicine_id AND mb2.branch_id = pu.branch_id
    WHERE pu.team_id = v_team_id AND pu.branch_id = p_branch_id AND pu.status = 'received' AND mb2.id = v_batch
    ORDER BY pu.created_at DESC, pi.id DESC LIMIT 1;

    v_unit_cost := coalesce(v_batch_uc, v_pi_uc, v_med_pp, 0);
    v_list_price := coalesce(v_batch_sp, v_med_sp, 0);
    v_line := v_qty * v_price;

    -- Proportional discount allocation
    v_discount_alloc := CASE WHEN v_subtotal > 0 THEN round((v_line / v_subtotal) * v_discount, 2) ELSE 0 END;

    -- Profit = (line revenue - allocated discount) - COGS
    v_line_profit := (v_line - v_discount_alloc) - (v_qty * v_unit_cost);
    v_gross_profit := v_gross_profit + v_line_profit;

    INSERT INTO public.sale_items (sale_id, medicine_batch_id, medicine_id, unit, qty, unit_price, line_total,
      list_unit_price, cost_unit_at_sale, line_profit, discount_alloc, price_override_reason)
    VALUES (v_sale_id, v_batch, v_medicine, 'base', v_qty, v_price, v_line,
      v_list_price, v_unit_cost, v_line_profit, v_discount_alloc, v_override_reason);

    PERFORM public.apply_stock_movement(v_team_id, p_branch_id, v_batch, 'sale_out', -v_qty, null, 'sale', v_sale_id);
  END LOOP;

  UPDATE public.sales SET gross_profit = v_gross_profit WHERE id = v_sale_id;
  INSERT INTO public.payments (sale_id, method, amount, reference_no) VALUES (v_sale_id, p_method, v_grand, p_reference_no);
  INSERT INTO public.activity_logs (team_id, branch_id, user_id, action_type, entity_type, entity_id, meta)
  VALUES (v_team_id, p_branch_id, auth.uid(), 'sale_created', 'sale', v_sale_id,
    jsonb_build_object('items', jsonb_array_length(p_items), 'grand_total', v_grand));
  RETURN v_sale_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
