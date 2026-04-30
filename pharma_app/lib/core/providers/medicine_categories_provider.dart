import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pharmacy_profile_provider.dart';
import 'selected_branch_provider.dart';

List<Map<String, dynamic>> _sortCategoriesWithOtherLast(
  List<Map<String, dynamic>> rows,
) {
  final sorted = List<Map<String, dynamic>>.from(rows);
  sorted.sort((a, b) {
    final aName = (a['name'] as String? ?? '').trim();
    final bName = (b['name'] as String? ?? '').trim();
    final aIsOther = aName.toLowerCase() == 'other';
    final bIsOther = bName.toLowerCase() == 'other';
    if (aIsOther && !bIsOther) return 1;
    if (!aIsOther && bIsOther) return -1;
    return aName.toLowerCase().compareTo(bName.toLowerCase());
  });
  return sorted;
}

final branchMedicineCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final branchId = ref.watch(selectedBranchIdProvider);
      final profile = await ref.watch(pharmacyProfileProvider.future);
      final teamId = profile?['team_id'] as String?;
      if (branchId == null || teamId == null || teamId.isEmpty) return const [];

      final rows = await Supabase.instance.client
          .from('medicine_categories')
          .select('id, name, is_active')
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .order('name');
      return _sortCategoriesWithOtherLast(
        List<Map<String, dynamic>>.from(rows as List),
      );
    });

final activeBranchMedicineCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final categories = await ref.watch(
        branchMedicineCategoriesProvider.future,
      );
      return _sortCategoriesWithOtherLast(
        categories.where((row) => row['is_active'] == true).toList(),
      );
    });
