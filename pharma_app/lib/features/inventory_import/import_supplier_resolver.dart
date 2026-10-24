import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves an extracted invoice supplier to a saved supplier row.
class ImportSupplierResolver {
  ImportSupplierResolver({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String?> resolveOrCreate({
    required String teamId,
    required String? supplierName,
  }) async {
    final name = supplierName?.trim();
    if (name == null || name.isEmpty) return null;

    final rows = await _client
        .from('suppliers')
        .select('id, name')
        .eq('team_id', teamId)
        .ilike('name', name)
        .limit(5);
    final matches = List<Map<String, dynamic>>.from(rows as List);
    final exact = matches.cast<Map<String, dynamic>?>().firstWhere(
      (row) =>
          (row?['name'] as String? ?? '').trim().toLowerCase() ==
          name.toLowerCase(),
      orElse: () => null,
    );
    if (exact != null) return exact['id'] as String?;
    if (matches.length == 1) return matches.first['id'] as String?;

    final inserted = await _client
        .from('suppliers')
        .insert({'team_id': teamId, 'name': name})
        .select('id')
        .single();
    return inserted['id'] as String?;
  }
}
