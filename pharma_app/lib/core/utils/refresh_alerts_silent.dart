import 'package:supabase_flutter/supabase_flutter.dart';

/// Best-effort [refresh_alerts] after stock changes (non-fatal on failure).
Future<void> refreshAlertsSilent({
  required String teamId,
  required String branchId,
}) async {
  try {
    await Supabase.instance.client.rpc(
      'refresh_alerts',
      params: {'p_team_id': teamId, 'p_branch_id': branchId},
    );
  } catch (_) {}
}
