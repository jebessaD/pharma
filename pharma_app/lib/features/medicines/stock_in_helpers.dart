import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/refresh_alerts_silent.dart';

/// Creates a batch and records initial stock via [apply_stock_movement].
Future<String> stockInNewBatch({
  required SupabaseClient client,
  required String teamId,
  required String branchId,
  required String medicineId,
  String? batchNo,
  required String expiryIso,
  required num qty,
  num? unitCost,
  num? sellPrice,
  String refType = 'manual',
  String reason = 'manual_stock_in',
}) async {
  if (qty <= 0) {
    throw ArgumentError('Quantity must be greater than 0');
  }
  final ins = await client
      .from('medicine_batches')
      .insert({
        'team_id': teamId,
        'branch_id': branchId,
        'medicine_id': medicineId,
        'batch_no': (batchNo == null || batchNo.trim().isEmpty)
            ? null
            : batchNo.trim(),
        'expiry_date': expiryIso,
        'quantity_in_base_unit': 0,
        'unit_cost_base': unitCost,
        'sell_price_base': sellPrice,
      })
      .select('id')
      .single();
  final batchId = ins['id'] as String;
  await client.rpc(
    'apply_stock_movement',
    params: {
      'p_team_id': teamId,
      'p_branch_id': branchId,
      'p_batch_id': batchId,
      'p_type': 'purchase_in',
      'p_qty': qty,
      'p_reason': reason,
      'p_ref_type': refType,
      'p_ref_id': null,
    },
  );
  await refreshAlertsSilent(teamId: teamId, branchId: branchId);
  return batchId;
}
