-- App update config, team billing gate, platform ops messages, and unified mutate guard.

-- ---------------------------------------------------------------------------
-- 1) Client config (single row, id = 1)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_client_config (
  id smallint PRIMARY KEY DEFAULT 1,
  CONSTRAINT app_client_config_singleton CHECK (id = 1),
  min_supported_version text NOT NULL DEFAULT '1.0.0',
  update_message text,
  store_url_ios text,
  store_url_android text,
  store_url_web text,
  force_update boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.app_client_config (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.app_client_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_client_config_select_anon ON public.app_client_config;
CREATE POLICY app_client_config_select_anon
  ON public.app_client_config FOR SELECT TO anon
  USING (true);

DROP POLICY IF EXISTS app_client_config_select_auth ON public.app_client_config;
CREATE POLICY app_client_config_select_auth
  ON public.app_client_config FOR SELECT TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- 2) Team billing (subscription / contact gate)
-- ---------------------------------------------------------------------------
ALTER TABLE public.teams
  ADD COLUMN IF NOT EXISTS billing_status text NOT NULL DEFAULT 'trial'
    CHECK (billing_status IN (
      'trial', 'active', 'grace', 'past_due', 'suspended_billing', 'churned'
    ));

ALTER TABLE public.teams
  ADD COLUMN IF NOT EXISTS billing_grace_ends_at timestamptz;

UPDATE public.teams
SET billing_status = CASE
  WHEN trial_ends_at IS NULL THEN 'active'
  ELSE 'trial'
END
WHERE billing_status = 'trial';

-- ---------------------------------------------------------------------------
-- 3) Platform messages (global ops / warnings)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.platform_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  body text NOT NULL DEFAULT '',
  severity text NOT NULL DEFAULT 'info'
    CHECK (severity IN ('info', 'warning', 'critical')),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  min_app_version text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_platform_messages_window
  ON public.platform_messages (starts_at, ends_at);

ALTER TABLE public.platform_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS platform_messages_select_member ON public.platform_messages;
CREATE POLICY platform_messages_select_member
  ON public.platform_messages FOR SELECT TO authenticated
  USING (
    starts_at <= now()
    AND (ends_at IS NULL OR ends_at >= now())
  );

DROP POLICY IF EXISTS platform_messages_admin_all ON public.platform_messages;
CREATE POLICY platform_messages_admin_all
  ON public.platform_messages FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.auth_user_id = auth.uid() AND pa.is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.auth_user_id = auth.uid() AND pa.is_active = true
    )
  );

CREATE TABLE IF NOT EXISTS public.platform_message_reads (
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES public.platform_messages (id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, message_id)
);

ALTER TABLE public.platform_message_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS platform_message_reads_own ON public.platform_message_reads;
CREATE POLICY platform_message_reads_own
  ON public.platform_message_reads FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 4) Assert team may perform mutating operations (status + billing)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_team_may_mutate(p_team_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  st text;
  bs text;
  te timestamptz;
  ge timestamptz;
BEGIN
  SELECT status, billing_status, trial_ends_at, billing_grace_ends_at
  INTO st, bs, te, ge
  FROM public.teams
  WHERE id = p_team_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'team_not_found';
  END IF;
  IF st <> 'active' THEN
    RAISE EXCEPTION 'team_suspended';
  END IF;
  IF bs = 'active' THEN
    RETURN;
  END IF;
  IF bs IN ('past_due', 'suspended_billing', 'churned') THEN
    RAISE EXCEPTION 'billing_blocked';
  END IF;
  IF bs = 'trial' AND te IS NOT NULL AND te < now() THEN
    RAISE EXCEPTION 'billing_blocked';
  END IF;
  IF bs = 'grace' AND ge IS NOT NULL AND ge < now() THEN
    RAISE EXCEPTION 'billing_blocked';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_team_may_mutate(uuid) FROM PUBLIC;

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
  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND team_id = p_team_id AND is_active = true
  ) THEN
    PERFORM public.assert_team_may_mutate(p_team_id);
  ELSIF NOT EXISTS (
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

CREATE OR REPLACE FUNCTION public.create_sale(
  p_branch_id uuid,
  p_items jsonb,
  p_method text,
  p_reference_no text,
  p_discount_total numeric,
  p_client_operation_id text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  v_role text;
  v_sale_id uuid;
  v_existing_sale_id uuid;
  v_subtotal numeric := 0;
  v_gross_profit numeric := 0;
  v_grand numeric;
  r jsonb;
  v_batch uuid;
  v_medicine uuid;
  v_qty numeric;
  v_price numeric;
  v_line numeric;
  v_exp date;
  v_list_price numeric;
  v_unit_cost numeric;
  v_line_profit numeric;
  v_override_reason text;
BEGIN
  SELECT team_id, role
  INTO v_team_id, v_role
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'no_profile';
  END IF;

  PERFORM public.assert_team_may_mutate(v_team_id);

  IF p_client_operation_id IS NOT NULL THEN
    SELECT s.id
    INTO v_existing_sale_id
    FROM public.sales s
    WHERE s.team_id = v_team_id
      AND s.sold_by = auth.uid()
      AND s.client_operation_id = p_client_operation_id
    LIMIT 1;

    IF v_existing_sale_id IS NOT NULL THEN
      RETURN v_existing_sale_id;
    END IF;
  END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');

    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'bad_qty';
    END IF;
    IF v_price IS NULL OR v_price < 0 THEN
      RAISE EXCEPTION 'bad_price';
    END IF;

    SELECT mb.expiry_date, mb.medicine_id, m.selling_price
    INTO v_exp, v_medicine, v_list_price
    FROM public.medicine_batches mb
    JOIN public.medicines m ON m.id = mb.medicine_id
    WHERE mb.id = v_batch
      AND mb.team_id = v_team_id
      AND mb.branch_id = p_branch_id;

    IF v_exp IS NULL THEN
      RAISE EXCEPTION 'batch_not_found';
    END IF;
    IF v_exp < CURRENT_DATE THEN
      RAISE EXCEPTION 'expired_batch';
    END IF;

    IF v_role IN ('cashier', 'seller') THEN
      IF v_list_price IS NULL THEN
        RAISE EXCEPTION 'missing_list_price';
      END IF;
      IF v_price < (v_list_price * 0.95) OR v_price > (v_list_price * 1.05) THEN
        RAISE EXCEPTION 'cashier_price_override_out_of_range';
      END IF;
    END IF;

    v_line := v_qty * v_price;
    v_subtotal := v_subtotal + v_line;
  END LOOP;

  v_grand := v_subtotal - coalesce(p_discount_total, 0);
  IF v_grand < 0 THEN
    RAISE EXCEPTION 'bad_discount';
  END IF;

  INSERT INTO public.sales (
    team_id,
    branch_id,
    sold_by,
    subtotal,
    discount_total,
    grand_total,
    gross_profit,
    client_operation_id
  )
  VALUES (
    v_team_id,
    p_branch_id,
    auth.uid(),
    v_subtotal,
    coalesce(p_discount_total, 0),
    v_grand,
    0,
    p_client_operation_id
  )
  RETURNING id INTO v_sale_id;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_batch := (r->>'medicine_batch_id')::uuid;
    v_qty := (r->>'qty')::numeric;
    v_price := (r->>'unit_price')::numeric;
    v_override_reason := nullif(trim(coalesce(r->>'price_override_reason', '')), '');

    SELECT mb.medicine_id, m.selling_price
    INTO v_medicine, v_list_price
    FROM public.medicine_batches mb
    JOIN public.medicines m ON m.id = mb.medicine_id
    WHERE mb.id = v_batch;

    SELECT pi.unit_cost
    INTO v_unit_cost
    FROM public.purchase_items pi
    JOIN public.purchases pu ON pu.id = pi.purchase_id
    JOIN public.medicine_batches mb ON mb.batch_no = pi.batch_no
                               AND mb.medicine_id = pi.medicine_id
                               AND mb.branch_id = pu.branch_id
    WHERE pu.team_id = v_team_id
      AND pu.branch_id = p_branch_id
      AND pu.status = 'received'
      AND mb.id = v_batch
    ORDER BY pu.created_at DESC, pi.id DESC
    LIMIT 1;

    v_line := v_qty * v_price;
    v_line_profit := v_line - (v_qty * coalesce(v_unit_cost, 0));
    v_gross_profit := v_gross_profit + v_line_profit;

    INSERT INTO public.sale_items (
      sale_id, medicine_batch_id, medicine_id, unit, qty, unit_price, line_total,
      list_unit_price, cost_unit_at_sale, line_profit, price_override_reason
    )
    VALUES (
      v_sale_id, v_batch, v_medicine, 'base', v_qty, v_price, v_line,
      coalesce(v_list_price, 0), coalesce(v_unit_cost, 0), v_line_profit, v_override_reason
    );

    PERFORM public.apply_stock_movement(
      v_team_id, p_branch_id, v_batch, 'sale_out', -v_qty, null, 'sale', v_sale_id
    );
  END LOOP;

  UPDATE public.sales
  SET gross_profit = v_gross_profit
  WHERE id = v_sale_id;

  INSERT INTO public.payments (sale_id, method, amount, reference_no)
  VALUES (v_sale_id, p_method, v_grand, p_reference_no);

  INSERT INTO public.activity_logs (
    team_id, branch_id, user_id, action_type, entity_type, entity_id, meta
  )
  VALUES (
    v_team_id,
    p_branch_id,
    auth.uid(),
    'sale_created',
    'sale',
    v_sale_id,
    jsonb_build_object('items', jsonb_array_length(p_items), 'grand_total', v_grand)
  );

  RETURN v_sale_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_stock_in(p_branch_id uuid, p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  r jsonb;
  v_mid uuid;
  v_batch_no text;
  v_exp date;
  v_qty numeric;
  v_batch_id uuid;
  v_done int := 0;
BEGIN
  SELECT team_id INTO v_team_id
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'no_profile';
  END IF;

  PERFORM public.assert_team_may_mutate(v_team_id);

  IF NOT EXISTS (
    SELECT 1 FROM public.branches b
    WHERE b.id = p_branch_id AND b.team_id = v_team_id
  ) THEN
    RAISE EXCEPTION 'bad_branch';
  END IF;

  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'bulk_stock_empty';
  END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_mid := (r->>'medicine_id')::uuid;
    v_batch_no := nullif(trim(coalesce(r->>'batch_no', '')), '');
    v_exp := (r->>'expiry_date')::date;
    v_qty := (r->>'qty')::numeric;

    IF v_mid IS NULL OR v_exp IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'bulk_stock_bad_row';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.medicines m
      WHERE m.id = v_mid AND m.team_id = v_team_id
    ) THEN
      RAISE EXCEPTION 'medicine_not_found';
    END IF;

    IF v_exp < CURRENT_DATE THEN
      RAISE EXCEPTION 'expiry_in_past';
    END IF;

    INSERT INTO public.medicine_batches (
      team_id, branch_id, medicine_id, batch_no, expiry_date, quantity_in_base_unit
    ) VALUES (v_team_id, p_branch_id, v_mid, v_batch_no, v_exp, 0)
    RETURNING id INTO v_batch_id;

    PERFORM public.apply_stock_movement(
      v_team_id,
      p_branch_id,
      v_batch_id,
      'purchase_in',
      v_qty,
      'bulk_stock_in',
      'bulk_stock_in',
      NULL
    );

    v_done := v_done + 1;
  END LOOP;

  RETURN jsonb_build_object('rows_applied', v_done);
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_stock_in(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bulk_stock_in(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_sale(
  p_branch_id uuid,
  p_items jsonb,
  p_method text,
  p_reference_no text,
  p_discount_total numeric
) RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.create_sale(
    p_branch_id,
    p_items,
    p_method,
    p_reference_no,
    p_discount_total,
    NULL
  );
$$;

REVOKE ALL ON FUNCTION public.apply_stock_movement(uuid, uuid, uuid, text, numeric, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_stock_movement(uuid, uuid, uuid, text, numeric, text, text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.create_sale(uuid, jsonb, text, text, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_sale(uuid, jsonb, text, text, numeric, text) TO authenticated;
REVOKE ALL ON FUNCTION public.create_sale(uuid, jsonb, text, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_sale(uuid, jsonb, text, text, numeric) TO authenticated;
