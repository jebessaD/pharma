-- Phase 4: medicines + batches + conversions (README_04 + search indexes README_13)

CREATE TABLE IF NOT EXISTS public.medicines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  name text NOT NULL,
  generic_name text,
  manual_code text NOT NULL,
  barcode text,
  category text,
  purchase_price numeric(12, 2) NOT NULL DEFAULT 0,
  selling_price numeric(12, 2) NOT NULL DEFAULT 0,
  reorder_level numeric NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (team_id, manual_code)
);

CREATE TABLE IF NOT EXISTS public.medicine_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches (id) ON DELETE CASCADE,
  medicine_id uuid NOT NULL REFERENCES public.medicines (id) ON DELETE CASCADE,
  batch_no text NOT NULL,
  expiry_date date NOT NULL,
  quantity_in_base_unit numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.unit_conversions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams (id) ON DELETE CASCADE,
  medicine_id uuid NOT NULL REFERENCES public.medicines (id) ON DELETE CASCADE,
  from_unit text NOT NULL,
  to_unit text NOT NULL,
  multiplier numeric NOT NULL CHECK (multiplier > 0)
);

CREATE INDEX IF NOT EXISTS idx_medicines_team ON public.medicines (team_id);
CREATE INDEX IF NOT EXISTS idx_batches_branch ON public.medicine_batches (branch_id);
CREATE INDEX IF NOT EXISTS idx_medicines_name_lower ON public.medicines (lower(name));
CREATE INDEX IF NOT EXISTS idx_medicines_generic_lower ON public.medicines (lower(generic_name));
CREATE INDEX IF NOT EXISTS idx_medicines_manual_lower ON public.medicines (lower(manual_code));

ALTER TABLE public.medicines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medicine_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unit_conversions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS medicines_team_rw ON public.medicines;
DROP POLICY IF EXISTS medicine_batches_team_rw ON public.medicine_batches;
DROP POLICY IF EXISTS unit_conversions_team_rw ON public.unit_conversions;

CREATE POLICY medicines_team_rw ON public.medicines FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = medicines.team_id))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = medicines.team_id));

CREATE POLICY medicine_batches_team_rw ON public.medicine_batches FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = medicine_batches.team_id))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = medicine_batches.team_id));

CREATE POLICY unit_conversions_team_rw ON public.unit_conversions FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = unit_conversions.team_id))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.team_id = unit_conversions.team_id));
