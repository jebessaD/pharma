-- SMS OTP abuse protection: per-phone and per-IP daily/hourly caps.
-- Logged when request-phone-otp edge function approves a send.

CREATE TABLE IF NOT EXISTS public.sms_otp_send_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  msisdn text NOT NULL,
  ip_hash text NOT NULL DEFAULT 'unknown',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sms_otp_send_log_msisdn_created
  ON public.sms_otp_send_log (msisdn, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sms_otp_send_log_ip_created
  ON public.sms_otp_send_log (ip_hash, created_at DESC);

ALTER TABLE public.sms_otp_send_log ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.sms_otp_send_log IS
  'Audit log for phone OTP SMS requests (msisdn + hashed IP).';

CREATE OR REPLACE FUNCTION public.assert_sms_otp_rate_limit(
  p_msisdn text,
  p_ip_hash text DEFAULT 'unknown',
  p_record boolean DEFAULT true,
  p_max_per_phone_day int DEFAULT 10,
  p_max_per_ip_day int DEFAULT 30,
  p_max_per_phone_hour int DEFAULT 5
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_msisdn text := regexp_replace(trim(coalesce(p_msisdn, '')), '\D', '', 'g');
  v_ip text := nullif(trim(coalesce(p_ip_hash, '')), '');
  v_phone_day int;
  v_ip_day int;
  v_phone_hour int;
BEGIN
  IF length(v_msisdn) < 9 THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'invalid_msisdn');
  END IF;

  IF v_ip IS NULL THEN
    v_ip := 'unknown';
  END IF;

  SELECT count(*)::int INTO v_phone_day
  FROM public.sms_otp_send_log
  WHERE msisdn = v_msisdn
    AND created_at > now() - interval '1 day';

  IF v_phone_day >= greatest(p_max_per_phone_day, 1) THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'phone_daily_limit',
      'retry_after_seconds', 3600
    );
  END IF;

  SELECT count(*)::int INTO v_phone_hour
  FROM public.sms_otp_send_log
  WHERE msisdn = v_msisdn
    AND created_at > now() - interval '1 hour';

  IF v_phone_hour >= greatest(p_max_per_phone_hour, 1) THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'phone_hourly_limit',
      'retry_after_seconds', 3600
    );
  END IF;

  IF v_ip <> 'unknown' THEN
    SELECT count(*)::int INTO v_ip_day
    FROM public.sms_otp_send_log
    WHERE ip_hash = v_ip
      AND created_at > now() - interval '1 day';

    IF v_ip_day >= greatest(p_max_per_ip_day, 1) THEN
      RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'ip_daily_limit',
        'retry_after_seconds', 3600
      );
    END IF;
  END IF;

  IF p_record THEN
    INSERT INTO public.sms_otp_send_log (msisdn, ip_hash)
    VALUES (v_msisdn, v_ip);
  END IF;

  RETURN jsonb_build_object('allowed', true);
END;
$$;

REVOKE ALL ON FUNCTION public.assert_sms_otp_rate_limit(
  text, text, boolean, int, int, int
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.assert_sms_otp_rate_limit(
  text, text, boolean, int, int, int
) TO service_role;
