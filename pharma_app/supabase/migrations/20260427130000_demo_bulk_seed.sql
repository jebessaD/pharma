-- Demo bulk seed data for pharmacy app.
-- Purpose: populate all major relational tables with coherent data for demo/testing.
-- Safe to re-run: uses deterministic demo keys/codes and upsert patterns where possible.

DO $$
DECLARE
  v_team_id uuid;
  v_branch_id uuid;
  v_admin_id uuid;
  v_pharm1_id uuid;
  v_pharm2_id uuid;

  v_supplier_a uuid;
  v_supplier_b uuid;

  v_med_para uuid;
  v_med_amox uuid;
  v_med_vitc uuid;

  v_batch_para_1 uuid;
  v_batch_para_2 uuid;
  v_batch_amox_1 uuid;
  v_batch_vitc_1 uuid;

  v_purchase_1 uuid;
  v_purchase_2 uuid;

  v_sale_1 uuid;
  v_sale_2 uuid;
  v_sale_3 uuid;
  v_sale_4 uuid;
  v_sale_5 uuid;
  v_sale_6 uuid;
BEGIN
  -- Pick existing org context (avoids creating auth.users rows).
  SELECT id INTO v_team_id
  FROM public.teams
  ORDER BY created_at
  LIMIT 1;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'No team found. Create a team first.';
  END IF;

  SELECT id INTO v_branch_id
  FROM public.branches
  WHERE team_id = v_team_id
  ORDER BY created_at
  LIMIT 1;

  IF v_branch_id IS NULL THEN
    RAISE EXCEPTION 'No branch found for team %', v_team_id;
  END IF;

  SELECT id INTO v_admin_id
  FROM public.profiles
  WHERE team_id = v_team_id AND is_active AND role = 'admin'
  ORDER BY created_at
  LIMIT 1;

  SELECT id INTO v_pharm1_id
  FROM public.profiles
  WHERE team_id = v_team_id AND is_active AND role = 'pharmacist'
  ORDER BY created_at
  LIMIT 1;

  SELECT id INTO v_pharm2_id
  FROM public.profiles
  WHERE team_id = v_team_id AND is_active AND role = 'pharmacist' AND id <> v_pharm1_id
  ORDER BY created_at
  LIMIT 1;

  IF v_admin_id IS NULL OR v_pharm1_id IS NULL THEN
    RAISE EXCEPTION 'Need at least 1 active admin and 1 active pharmacist in profiles.';
  END IF;

  IF v_pharm2_id IS NULL THEN
    v_pharm2_id := v_pharm1_id;
  END IF;

  -- Guard against duplicate demo runs.
  IF EXISTS (
    SELECT 1
    FROM public.purchases
    WHERE team_id = v_team_id
      AND branch_id = v_branch_id
      AND invoice_reference = 'DEMO-INV-001'
  ) THEN
    RAISE NOTICE 'Demo seed already applied for this branch. Skipping.';
    RETURN;
  END IF;

  -- Team profile
  INSERT INTO public.team_profiles (team_id, pharmacy_name, phone, address, license_number)
  VALUES (v_team_id, 'Demo Care Pharmacy', '+251911000111', 'Addis Ababa, Bole', 'LIC-DEMO-2026')
  ON CONFLICT (team_id) DO UPDATE
  SET pharmacy_name = EXCLUDED.pharmacy_name,
      phone = EXCLUDED.phone,
      address = EXCLUDED.address,
      license_number = EXCLUDED.license_number,
      updated_at = now();

  -- Suppliers
  INSERT INTO public.suppliers (team_id, name, phone, address, is_active)
  VALUES
    (v_team_id, 'DemoMed Wholesale', '+251911100200', 'Addis Ababa, Mercato', true),
    (v_team_id, 'Ethio Pharma Trade', '+251911100300', 'Addis Ababa, Kazanchis', true)
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_supplier_a
  FROM public.suppliers
  WHERE team_id = v_team_id AND name = 'DemoMed Wholesale'
  ORDER BY created_at
  LIMIT 1;

  SELECT id INTO v_supplier_b
  FROM public.suppliers
  WHERE team_id = v_team_id AND name = 'Ethio Pharma Trade'
  ORDER BY created_at
  LIMIT 1;

  -- Medicines (idempotent by deterministic manual_code)
  INSERT INTO public.medicines (
    team_id, name, generic_name, manual_code, barcode, category,
    purchase_price, selling_price, reorder_level, is_active
  ) VALUES
    (v_team_id, 'Paracetamol 500mg', 'Paracetamol', 'DEMO-PARA-500', '1111111111111', 'Analgesic', 100.00, 200.00, 8, true),
    (v_team_id, 'Amoxicillin 500mg', 'Amoxicillin', 'DEMO-AMOX-500', '2222222222222', 'Antibiotic', 100.00, 150.00, 5, true),
    (v_team_id, 'Vitamin C 1000mg', 'Ascorbic Acid', 'DEMO-VITC-1000', '3333333333333', 'Supplement', 60.00, 120.00, 10, true)
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_med_para FROM public.medicines WHERE team_id = v_team_id AND manual_code = 'DEMO-PARA-500' LIMIT 1;
  SELECT id INTO v_med_amox FROM public.medicines WHERE team_id = v_team_id AND manual_code = 'DEMO-AMOX-500' LIMIT 1;
  SELECT id INTO v_med_vitc FROM public.medicines WHERE team_id = v_team_id AND manual_code = 'DEMO-VITC-1000' LIMIT 1;

  -- Unit conversions
  INSERT INTO public.unit_conversions (team_id, medicine_id, from_unit, to_unit, multiplier)
  VALUES
    (v_team_id, v_med_para, 'box', 'base', 10),
    (v_team_id, v_med_amox, 'box', 'base', 10),
    (v_team_id, v_med_vitc, 'box', 'base', 20)
  ON CONFLICT DO NOTHING;

  -- Purchases
  INSERT INTO public.purchases (team_id, branch_id, supplier_id, invoice_reference, status, created_by, created_at)
  VALUES
    (v_team_id, v_branch_id, v_supplier_a, 'DEMO-INV-001', 'received', v_admin_id, now() - interval '8 days'),
    (v_team_id, v_branch_id, v_supplier_b, 'DEMO-INV-002', 'received', v_admin_id, now() - interval '4 days')
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_purchase_1
  FROM public.purchases
  WHERE team_id = v_team_id AND branch_id = v_branch_id AND invoice_reference = 'DEMO-INV-001'
  ORDER BY created_at
  LIMIT 1;

  SELECT id INTO v_purchase_2
  FROM public.purchases
  WHERE team_id = v_team_id AND branch_id = v_branch_id AND invoice_reference = 'DEMO-INV-002'
  ORDER BY created_at
  LIMIT 1;

  INSERT INTO public.purchase_items (purchase_id, medicine_id, batch_no, expiry_date, qty_base_unit, unit_cost)
  VALUES
    (v_purchase_1, v_med_para, 'DEMO-PARA-B1', current_date + 365, 40, 100.00),
    (v_purchase_1, v_med_amox, 'DEMO-AMOX-B1', current_date + 300, 20, 100.00),
    (v_purchase_2, v_med_para, 'DEMO-PARA-B2', current_date + 420, 30, 100.00),
    (v_purchase_2, v_med_vitc, 'DEMO-VITC-B1', current_date + 540, 50, 60.00)
  ON CONFLICT DO NOTHING;

  -- Medicine batches
  INSERT INTO public.medicine_batches (team_id, branch_id, medicine_id, batch_no, expiry_date, quantity_in_base_unit, created_at)
  VALUES
    (v_team_id, v_branch_id, v_med_para, 'DEMO-PARA-B1', current_date + 365, 40, now() - interval '8 days'),
    (v_team_id, v_branch_id, v_med_para, 'DEMO-PARA-B2', current_date + 420, 30, now() - interval '4 days'),
    (v_team_id, v_branch_id, v_med_amox, 'DEMO-AMOX-B1', current_date + 300, 20, now() - interval '8 days'),
    (v_team_id, v_branch_id, v_med_vitc, 'DEMO-VITC-B1', current_date + 540, 50, now() - interval '4 days')
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_batch_para_1 FROM public.medicine_batches WHERE team_id = v_team_id AND branch_id = v_branch_id AND batch_no = 'DEMO-PARA-B1' LIMIT 1;
  SELECT id INTO v_batch_para_2 FROM public.medicine_batches WHERE team_id = v_team_id AND branch_id = v_branch_id AND batch_no = 'DEMO-PARA-B2' LIMIT 1;
  SELECT id INTO v_batch_amox_1 FROM public.medicine_batches WHERE team_id = v_team_id AND branch_id = v_branch_id AND batch_no = 'DEMO-AMOX-B1' LIMIT 1;
  SELECT id INTO v_batch_vitc_1 FROM public.medicine_batches WHERE team_id = v_team_id AND branch_id = v_branch_id AND batch_no = 'DEMO-VITC-B1' LIMIT 1;

  -- Stock balances
  INSERT INTO public.stock_balances (team_id, branch_id, medicine_batch_id, qty_base_unit, updated_at)
  VALUES
    (v_team_id, v_branch_id, v_batch_para_1, 24, now()),
    (v_team_id, v_branch_id, v_batch_para_2, 25, now()),
    (v_team_id, v_branch_id, v_batch_amox_1, 14, now()),
    (v_team_id, v_branch_id, v_batch_vitc_1, 42, now())
  ON CONFLICT DO NOTHING;

  -- Stock movements for incoming stock and adjustment
  INSERT INTO public.stock_movements (
    team_id, branch_id, medicine_batch_id, movement_type, qty_change_base_unit,
    reason, reference_type, reference_id, created_by, created_at
  ) VALUES
    (v_team_id, v_branch_id, v_batch_para_1, 'purchase_in', 40, 'Demo stock-in', 'purchase', v_purchase_1, v_admin_id, now() - interval '8 days'),
    (v_team_id, v_branch_id, v_batch_amox_1, 'purchase_in', 20, 'Demo stock-in', 'purchase', v_purchase_1, v_admin_id, now() - interval '8 days'),
    (v_team_id, v_branch_id, v_batch_para_2, 'purchase_in', 30, 'Demo stock-in', 'purchase', v_purchase_2, v_admin_id, now() - interval '4 days'),
    (v_team_id, v_branch_id, v_batch_vitc_1, 'purchase_in', 50, 'Demo stock-in', 'purchase', v_purchase_2, v_admin_id, now() - interval '4 days'),
    (v_team_id, v_branch_id, v_batch_amox_1, 'adjustment', -1, 'Demo damaged strip', 'manual_adjustment', null, v_admin_id, now() - interval '1 day')
  ON CONFLICT DO NOTHING;

  -- Sales
  INSERT INTO public.sales (team_id, branch_id, sold_by, subtotal, discount_total, grand_total, gross_profit, created_at)
  VALUES
    (v_team_id, v_branch_id, v_pharm1_id, 800.00, 50.00, 750.00, 350.00, now() - interval '6 days'),
    (v_team_id, v_branch_id, v_pharm2_id, 450.00, 0.00, 450.00, 230.00, now() - interval '4 days'),
    (v_team_id, v_branch_id, v_pharm1_id, 560.00, 10.00, 550.00, 260.00, now() - interval '3 days'),
    (v_team_id, v_branch_id, v_pharm2_id, 300.00, 0.00, 300.00, 150.00, now() - interval '2 days'),
    (v_team_id, v_branch_id, v_pharm1_id, 240.00, 0.00, 240.00, 120.00, now() - interval '1 day'),
    (v_team_id, v_branch_id, v_admin_id, 360.00, 20.00, 340.00, 170.00, now() - interval '4 hours')
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_sale_1 FROM public.sales WHERE team_id = v_team_id AND branch_id = v_branch_id AND created_at::date = (current_date - 6) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_sale_2 FROM public.sales WHERE team_id = v_team_id AND branch_id = v_branch_id AND created_at::date = (current_date - 4) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_sale_3 FROM public.sales WHERE team_id = v_team_id AND branch_id = v_branch_id AND created_at::date = (current_date - 3) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_sale_4 FROM public.sales WHERE team_id = v_team_id AND branch_id = v_branch_id AND created_at::date = (current_date - 2) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_sale_5 FROM public.sales WHERE team_id = v_team_id AND branch_id = v_branch_id AND created_at::date = (current_date - 1) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_sale_6 FROM public.sales WHERE team_id = v_team_id AND branch_id = v_branch_id AND created_at::date = current_date ORDER BY created_at DESC LIMIT 1;

  -- Sale items
  INSERT INTO public.sale_items (
    sale_id, medicine_batch_id, unit, qty, unit_price, line_total,
    medicine_id, list_unit_price, cost_unit_at_sale, line_profit, price_override_reason
  ) VALUES
    (v_sale_1, v_batch_para_1, 'base', 3, 200.00, 600.00, v_med_para, 200.00, 100.00, 300.00, null),
    (v_sale_1, v_batch_amox_1, 'base', 1, 200.00, 200.00, v_med_amox, 150.00, 100.00, 100.00, 'Urgent sale override'),

    (v_sale_2, v_batch_amox_1, 'base', 2, 150.00, 300.00, v_med_amox, 150.00, 100.00, 100.00, null),
    (v_sale_2, v_batch_vitc_1, 'base', 1.25, 120.00, 150.00, v_med_vitc, 120.00, 60.00, 75.00, null),

    (v_sale_3, v_batch_para_2, 'base', 2, 200.00, 400.00, v_med_para, 200.00, 100.00, 200.00, null),
    (v_sale_3, v_batch_vitc_1, 'base', 1.3333, 120.00, 160.00, v_med_vitc, 120.00, 60.00, 80.00, null),

    (v_sale_4, v_batch_para_1, 'base', 1.5, 200.00, 300.00, v_med_para, 200.00, 100.00, 150.00, null),

    (v_sale_5, v_batch_vitc_1, 'base', 2, 120.00, 240.00, v_med_vitc, 120.00, 60.00, 120.00, null),

    (v_sale_6, v_batch_para_2, 'base', 1, 200.00, 200.00, v_med_para, 200.00, 100.00, 100.00, null),
    (v_sale_6, v_batch_amox_1, 'base', 1, 160.00, 160.00, v_med_amox, 150.00, 100.00, 60.00, 'Senior customer loyalty price')
  ON CONFLICT DO NOTHING;

  -- Payments
  INSERT INTO public.payments (sale_id, method, amount, reference_no)
  VALUES
    (v_sale_1, 'cash', 750.00, null),
    (v_sale_2, 'mobile_banking', 450.00, 'MB-DEMO-450'),
    (v_sale_3, 'cash', 550.00, null),
    (v_sale_4, 'cash', 300.00, null),
    (v_sale_5, 'mobile_banking', 240.00, 'MB-DEMO-240'),
    (v_sale_6, 'cash', 340.00, null)
  ON CONFLICT DO NOTHING;

  -- Stock movements for sold items
  INSERT INTO public.stock_movements (
    team_id, branch_id, medicine_batch_id, movement_type, qty_change_base_unit,
    reason, reference_type, reference_id, created_by, created_at
  ) VALUES
    (v_team_id, v_branch_id, v_batch_para_1, 'sale_out', -3, null, 'sale', v_sale_1, v_pharm1_id, now() - interval '6 days'),
    (v_team_id, v_branch_id, v_batch_amox_1, 'sale_out', -1, null, 'sale', v_sale_1, v_pharm1_id, now() - interval '6 days'),
    (v_team_id, v_branch_id, v_batch_amox_1, 'sale_out', -2, null, 'sale', v_sale_2, v_pharm2_id, now() - interval '4 days'),
    (v_team_id, v_branch_id, v_batch_vitc_1, 'sale_out', -1.25, null, 'sale', v_sale_2, v_pharm2_id, now() - interval '4 days'),
    (v_team_id, v_branch_id, v_batch_para_2, 'sale_out', -2, null, 'sale', v_sale_3, v_pharm1_id, now() - interval '3 days'),
    (v_team_id, v_branch_id, v_batch_vitc_1, 'sale_out', -1.3333, null, 'sale', v_sale_3, v_pharm1_id, now() - interval '3 days'),
    (v_team_id, v_branch_id, v_batch_para_1, 'sale_out', -1.5, null, 'sale', v_sale_4, v_pharm2_id, now() - interval '2 days'),
    (v_team_id, v_branch_id, v_batch_vitc_1, 'sale_out', -2, null, 'sale', v_sale_5, v_pharm1_id, now() - interval '1 day'),
    (v_team_id, v_branch_id, v_batch_para_2, 'sale_out', -1, null, 'sale', v_sale_6, v_admin_id, now() - interval '4 hours'),
    (v_team_id, v_branch_id, v_batch_amox_1, 'sale_out', -1, null, 'sale', v_sale_6, v_admin_id, now() - interval '4 hours')
  ON CONFLICT DO NOTHING;

  -- Notifications
  INSERT INTO public.notifications (
    team_id, branch_id, type, title, message, entity_type, entity_id, is_read, created_at
  ) VALUES
    (v_team_id, v_branch_id, 'low_stock', 'Low stock: Amoxicillin 500mg', 'Stock is approaching reorder level for DEMO-AMOX-500.', 'medicine', v_med_amox, false, now() - interval '3 hours'),
    (v_team_id, v_branch_id, 'near_expiry', 'Near expiry batch', 'Batch DEMO-AMOX-B1 expires within 10 months.', 'medicine_batch', v_batch_amox_1, false, now() - interval '2 hours'),
    (v_team_id, v_branch_id, 'expired', 'Expired sample alert', 'Use this expired alert row for UI testing only.', 'medicine_batch', v_batch_para_1, true, now() - interval '30 minutes')
  ON CONFLICT DO NOTHING;

  -- Activity logs
  INSERT INTO public.activity_logs (
    team_id, branch_id, user_id, action_type, entity_type, entity_id, meta, created_at
  ) VALUES
    (v_team_id, v_branch_id, v_admin_id, 'purchase_received', 'purchase', v_purchase_1, jsonb_build_object('invoice', 'DEMO-INV-001', 'supplier', 'DemoMed Wholesale'), now() - interval '8 days'),
    (v_team_id, v_branch_id, v_admin_id, 'purchase_received', 'purchase', v_purchase_2, jsonb_build_object('invoice', 'DEMO-INV-002', 'supplier', 'Ethio Pharma Trade'), now() - interval '4 days'),
    (v_team_id, v_branch_id, v_pharm1_id, 'sale_completed', 'sale', v_sale_3, jsonb_build_object('grand_total', 550.00, 'items', 2), now() - interval '3 days'),
    (v_team_id, v_branch_id, v_pharm2_id, 'sale_completed', 'sale', v_sale_2, jsonb_build_object('grand_total', 450.00, 'items', 2), now() - interval '4 days'),
    (v_team_id, v_branch_id, v_admin_id, 'price_override', 'sale_item', null, jsonb_build_object('reason', 'Senior customer loyalty price', 'sale_id', v_sale_6), now() - interval '4 hours')
  ON CONFLICT DO NOTHING;
END $$;

-- Verification snapshots
SELECT 'teams' AS table_name, count(*) AS rows FROM public.teams
UNION ALL SELECT 'team_profiles', count(*) FROM public.team_profiles
UNION ALL SELECT 'branches', count(*) FROM public.branches
UNION ALL SELECT 'profiles', count(*) FROM public.profiles
UNION ALL SELECT 'suppliers', count(*) FROM public.suppliers
UNION ALL SELECT 'medicines', count(*) FROM public.medicines
UNION ALL SELECT 'unit_conversions', count(*) FROM public.unit_conversions
UNION ALL SELECT 'purchases', count(*) FROM public.purchases
UNION ALL SELECT 'purchase_items', count(*) FROM public.purchase_items
UNION ALL SELECT 'medicine_batches', count(*) FROM public.medicine_batches
UNION ALL SELECT 'stock_balances', count(*) FROM public.stock_balances
UNION ALL SELECT 'stock_movements', count(*) FROM public.stock_movements
UNION ALL SELECT 'sales', count(*) FROM public.sales
UNION ALL SELECT 'sale_items', count(*) FROM public.sale_items
UNION ALL SELECT 'payments', count(*) FROM public.payments
UNION ALL SELECT 'notifications', count(*) FROM public.notifications
UNION ALL SELECT 'activity_logs', count(*) FROM public.activity_logs
ORDER BY table_name;

SELECT
  coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.username), ''), 'Team member') AS seller_name,
  count(*) AS sale_count,
  sum(s.grand_total) AS total_sales
FROM public.sales s
LEFT JOIN public.profiles p ON p.id = s.sold_by
GROUP BY 1
ORDER BY total_sales DESC;
