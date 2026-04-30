CREATE UNIQUE INDEX IF NOT EXISTS idx_medicines_team_barcode_unique
ON public.medicines (team_id, barcode)
WHERE barcode IS NOT NULL AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_medicines_team_barcode_lookup
ON public.medicines (team_id, barcode);
