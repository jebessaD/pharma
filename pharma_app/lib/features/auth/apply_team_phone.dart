import 'package:supabase_flutter/supabase_flutter.dart';

/// Writes pharmacy phone onto team_profiles after bootstrap.
Future<void> applyTeamProfilePhone({
  required String teamId,
  required String? phone,
  SupabaseClient? client,
}) async {
  final normalized = phone?.trim() ?? '';
  if (teamId.isEmpty || normalized.isEmpty) return;

  final supabase = client ?? Supabase.instance.client;
  await supabase
      .from('team_profiles')
      .update({'phone': normalized})
      .eq('team_id', teamId);
}
