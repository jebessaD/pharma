-- Repair drift: some DBs still have payments_method_check (cash, bank_transfer) while the app uses mobile_banking.
-- Idempotent with 20260429120000_payments_cash_mobile_only.sql

UPDATE public.payments
SET method = 'mobile_banking'
WHERE method = 'bank_transfer';

ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_method_check
  CHECK (method IN ('cash', 'mobile_banking'));
