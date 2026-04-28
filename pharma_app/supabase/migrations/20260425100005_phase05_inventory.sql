-- Phase 5: stock_balances + stock_movements + apply_stock_movement (README_05)

CREATE TABLE IF NOT EXISTS public.stock_balances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches (id) ON DELETE CASCADE,
  medicine_batch_id uuid NOT NULL REFERENCES public.medicine_batches (id) ON DELETE CASCADE,
  qty_base_unit numeric NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (team_id, branch_id, medicine_batch_id)
);

CREATE TABLE IF NOT EXISTS public.stock_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches (id) ON DELETE CASCADE,
  medicine_batch_id uuid NOT NULL REFERENCES public.medicine_batches (id) ON DELETE CASCADE,
  movement_type text NOT NULL CHECK (movement_type IN ('purchase_in', 'sale_out', 'adjustment')),
  qty_change_base_unit numeric NOT NULL,
  reason text,
  reference_type text,
  reference_id uuid,
  created_by uuid REFERENCES auth.users (id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stock_movements_batch ON public.stock_movements (medicine_batch_id);

ALTER TABLE public.stock_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS stock_balances_team ON public.stock_balances;
CREATE POLICY stock_balances_team ON public.stock_balances FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = stock_balances.team_id))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = stock_balances.team_id));

DROP POLICY IF EXISTS stock_movements_team ON public.stock_movements;
CREATE POLICY stock_movements_team ON public.stock_movements FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = stock_movements.team_id))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = stock_movements.team_id));

CREATE OR REPLACE FUNCTION public.apply_stock_movement(
  p_team_id uuid,
  p_branch_id uuid,
  p_batch_id uuid,
  p_type text,
  p_qty numeric,
  p_reason text,
  p_ref_type text,
  p_ref_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND team_id = p_team_id AND is_active = true
  ) AND NOT EXISTS (
    SELECT 1 FROM public.platform_admins
    WHERE auth_user_id = auth.uid() AND is_active = true
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO public.stock_movements (
    team_id, branch_id, medicine_batch_id, movement_type,
    qty_change_base_unit, reason, reference_type, reference_id, created_by
  ) VALUES (
    p_team_id, p_branch_id, p_batch_id, p_type,
    p_qty, p_reason, p_ref_type, p_ref_id, auth.uid()
  );

  INSERT INTO public.stock_balances (team_id, branch_id, medicine_batch_id, qty_base_unit)
  VALUES (p_team_id, p_branch_id, p_batch_id, p_qty)
  ON CONFLICT (team_id, branch_id, medicine_batch_id)
  DO UPDATE SET
    qty_base_unit = public.stock_balances.qty_base_unit + EXCLUDED.qty_base_unit,
    updated_at = now();

  IF (
    SELECT qty_base_unit FROM public.stock_balances
    WHERE team_id = p_team_id AND branch_id = p_branch_id AND medicine_batch_id = p_batch_id
  ) < 0 THEN
    RAISE EXCEPTION 'insufficient_stock';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_stock_movement(uuid, uuid, uuid, text, numeric, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_stock_movement(uuid, uuid, uuid, text, numeric, text, text, uuid) TO authenticated;
