-- Optional batch number: allow NULL where product packaging has no batch code.

ALTER TABLE public.medicine_batches
  ALTER COLUMN batch_no DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_medicine_batches_team_branch_med_batch_unique
  ON public.medicine_batches (team_id, branch_id, medicine_id, batch_no)
  WHERE batch_no IS NOT NULL;
