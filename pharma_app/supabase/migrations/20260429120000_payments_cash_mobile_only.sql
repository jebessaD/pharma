-- Drop bank_transfer: map existing rows to mobile_banking; POS uses Cash + Mobile only.

UPDATE public.payments
SET method = 'mobile_banking'
WHERE method = 'bank_transfer';

ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_method_check
  CHECK (method IN ('cash', 'mobile_banking'));
