-- Add mobile_banking; map legacy mobile_money rows if any.

UPDATE public.payments
SET method = 'mobile_banking'
WHERE method = 'mobile_money';

ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_method_check
  CHECK (method IN ('cash', 'bank_transfer', 'mobile_banking'));
