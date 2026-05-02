import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared_preferences_provider.dart';
import 'pharmacy_profile_provider.dart';

const _kBranchId = 'selected_branch_id';

const _branchLockedRoles = {'pharmacist', 'cashier', 'seller'};

bool isBranchLocked(String? role) =>
    role != null && _branchLockedRoles.contains(role);

class SelectedBranchId extends Notifier<String?> {
  @override
  String? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final profile = ref.watch(pharmacyProfileProvider).asData?.value;
    final role = (profile?['role'] as String? ?? '').trim().toLowerCase();

    if (isBranchLocked(role)) {
      final assigned = profile?['branch_id'] as String?;
      if (assigned != null && assigned.isNotEmpty) return assigned;
    }

    return prefs.getString(_kBranchId);
  }

  Future<void> setBranch(String? branchId) async {
    final profile = ref.read(pharmacyProfileProvider).asData?.value;
    final role = (profile?['role'] as String? ?? '').trim().toLowerCase();
    if (isBranchLocked(role)) return;

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
