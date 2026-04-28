-- Single banking path: bank_transfer only (optional reference). Cash unchanged.

UPDATE public.payments
SET method = 'bank_transfer'
WHERE method IN ('mobile_money', 'mobile_banking');

ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_method_check
  CHECK (method IN ('cash', 'bank_transfer'));
