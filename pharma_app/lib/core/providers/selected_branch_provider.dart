import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared_preferences_provider.dart';

const _kBranchId = 'selected_branch_id';

class SelectedBranchId extends Notifier<String?> {
  @override
  String? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getString(_kBranchId);
  }

  Future<void> setBranch(String? branchId) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (branchId == null || branchId.isEmpty) {
      await prefs.remove(_kBranchId);
      state = null;
    } else {
      await prefs.setString(_kBranchId, branchId);
      state = branchId;
    }
  }
}

final selectedBranchIdProvider =
    NotifierProvider<SelectedBranchId, String?>(SelectedBranchId.new);
