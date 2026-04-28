-- Phase 8: suppliers + purchases (README_08)

CREATE TABLE IF NOT EXISTS public.suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  name text NOT NULL,
  phone text,
  address text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches (id) ON DELETE CASCADE,
  supplier_id uuid NOT NULL REFERENCES public.suppliers (id) ON DELETE RESTRICT,
  invoice_reference text,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'received')),
  created_by uuid REFERENCES auth.users (id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id uuid NOT NULL REFERENCES public.purchases (id) ON DELETE CASCADE,
  medicine_id uuid NOT NULL REFERENCES public.medicines (id) ON DELETE CASCADE,
  batch_no text NOT NULL,
  expiry_date date NOT NULL,
  qty_base_unit numeric NOT NULL,
  unit_cost numeric(12, 2) NOT NULL
);

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS suppliers_team ON public.suppliers;
CREATE POLICY suppliers_team ON public.suppliers FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = suppliers.team_id))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = suppliers.team_id));

DROP POLICY IF EXISTS purchases_team ON public.purchases;
CREATE POLICY purchases_team ON public.purchases FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = purchases.team_id))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = purchases.team_id));

DROP POLICY IF EXISTS purchase_items_team ON public.purchase_items;
CREATE POLICY purchase_items_team ON public.purchase_items FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.purchases pu
      JOIN public.profiles p ON p.team_id = pu.team_id AND p.id = auth.uid()
      WHERE pu.id = purchase_items.purchase_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.purchases pu
      JOIN public.profiles p ON p.team_id = pu.team_id AND p.id = auth.uid()
      WHERE pu.id = purchase_items.purchase_id
    )
  );

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
BEGIN
  SELECT * INTO pu FROM public.purchases WHERE id = p_purchase_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND team_id = pu.team_id AND is_active) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF pu.status = 'received' THEN
    RETURN;
  END IF;

  FOR it IN SELECT * FROM public.purchase_items WHERE purchase_id = pu.id
  LOOP
    INSERT INTO public.medicine_batches (
      team_id, branch_id, medicine_id, batch_no, expiry_date, quantity_in_base_unit
    ) VALUES (
      pu.team_id, pu.branch_id, it.medicine_id, it.batch_no, it.expiry_date, 0
    )
    RETURNING id INTO v_batch;

    PERFORM public.apply_stock_movement(
      pu.team_id, pu.branch_id, v_batch, 'purchase_in', it.qty_base_unit, null, 'purchase', pu.id
    );
  END LOOP;

  UPDATE public.purchases SET status = 'received' WHERE id = pu.id;
END;
$$;

REVOKE ALL ON FUNCTION public.receive_purchase(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.receive_purchase(uuid) TO authenticated;
