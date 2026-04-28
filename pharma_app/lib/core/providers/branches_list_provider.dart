import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final branchesListProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, teamId) async {
    if (teamId.isEmpty) return [];
    final rows = await Supabase.instance.client
        .from('branches')
        .select()
        .eq('team_id', teamId)
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(rows as List);
  },
);
