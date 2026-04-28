-- Phase 6: sales + sale_items + payments + create_sale (README_07)

CREATE TABLE IF NOT EXISTS public.sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches (id) ON DELETE CASCADE,
  sold_by uuid REFERENCES auth.users (id),
  subtotal numeric(12, 2) NOT NULL DEFAULT 0,
  discount_total numeric(12, 2) NOT NULL DEFAULT 0,
  grand_total numeric(12, 2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL REFERENCES public.sales (id) ON DELETE CASCADE,
  medicine_batch_id uuid NOT NULL REFERENCES public.medicine_batches (id),
  unit text NOT NULL,
  qty numeric NOT NULL,
  unit_price numeric(12, 2) NOT NULL,
  line_total numeric(12, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL REFERENCES public.sales (id) ON DELETE CASCADE,
  method text NOT NULL CHECK (method IN ('cash', 'bank_transfer')),
  amount numeric(12, 2) NOT NULL,
  reference_no text
);

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sales_team ON public.sales;
CREATE POLICY sales_team ON public.sales FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = sales.team_id))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = sales.team_id));

DROP POLICY IF EXISTS sale_items_team ON public.sale_items;
CREATE POLICY sale_items_team ON public.sale_items FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.sales s
      JOIN public.profiles p ON p.team_id = s.team_id AND p.id = auth.uid()
      WHERE s.id = sale_items.sale_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.sales s
      JOIN public.profiles p ON p.team_id = s.team_id AND p.id = auth.uid()
      WHERE s.id = sale_items.sale_id
    )
  );

DROP POLICY IF EXISTS payments_team ON public.payments;
CREATE POLICY payments_team ON public.payments FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.sales s
      JOIN public.profiles p ON p.team_id = s.team_id AND p.id = auth.uid()
      WHERE s.id = payments.sale_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.sales s
      JOIN public.profiles p ON p.team_id = s.team_id AND p.id = auth.uid()
      WHERE s.id = payments.sale_id
    )
  );

CREATE OR REPLACE FUNCTION public.create_sale(
  p_branch_id uuid,
  p_items jsonb,
  p_method text,
  p_reference_no text,
  p_discount_total numeric
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  v_sale_id uuid;
  v_subtotal numeric := 0;
  v_grand numeric;
  r jsonb;
  v_batch uuid;
  v_qty numeric;
  v_price numeric;
  v_line numeric;
  v_exp date;
BEGIN
  SELECT team_id INTO v_team_id FROM public.profiles WHERE id = auth.uid() AND is_active = true;
  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'no_profile';
  END IF;

  IF EXISTS (SELECT 1 FROM public.teams t WHERE t.id = v_team_id AND t.status <> 'active') THEN
    RAISE EXCEPTION 'team_suspended';
  END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'bad_qty';
    END IF;
    SELECT expiry_date INTO v_exp FROM public.medicine_batches mb
    WHERE mb.id = v_batch AND mb.team_id = v_team_id AND mb.branch_id = p_branch_id;
    IF v_exp IS NULL THEN
      RAISE EXCEPTION 'batch_not_found';
    END IF;
    IF v_exp < CURRENT_DATE THEN
      RAISE EXCEPTION 'expired_batch';
    END IF;
    v_line := v_qty * v_price;
    v_subtotal := v_subtotal + v_line;
  END LOOP;

  v_grand := v_subtotal - coalesce(p_discount_total, 0);
  IF v_grand < 0 THEN
    RAISE EXCEPTION 'bad_discount';
  END IF;

  INSERT INTO public.sales (team_id, branch_id, sold_by, subtotal, discount_total, grand_total)
  VALUES (v_team_id, p_branch_id, auth.uid(), v_subtotal, coalesce(p_discount_total, 0), v_grand)
  RETURNING id INTO v_sale_id;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_line := v_qty * v_price;
    INSERT INTO public.sale_items (sale_id, medicine_batch_id, unit, qty, unit_price, line_total)
    VALUES (v_sale_id, v_batch, 'base', v_qty, v_price, v_line);
    PERFORM public.apply_stock_movement(
      v_team_id, p_branch_id, v_batch, 'sale_out', -v_qty, null, 'sale', v_sale_id
    );
  END LOOP;

  INSERT INTO public.payments (sale_id, method, amount, reference_no)
  VALUES (v_sale_id, p_method, v_grand, p_reference_no);

  RETURN v_sale_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_sale(uuid, jsonb, text, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_sale(uuid, jsonb, text, text, numeric) TO authenticated;
