import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'branch_change_guard_provider.dart';
import 'branches_list_provider.dart';
import 'pharmacy_profile_provider.dart';
import 'pharmacy_redirect_cache_provider.dart';
import 'platform_messages_provider.dart';
import 'selected_branch_provider.dart';
import 'team_shell_meta_provider.dart';

/// Clears persisted branch selection and drops team-scoped caches so a new
/// login does not reuse the previous account's shell metadata or router gate.
///
/// Use a [ProviderContainer] (from [ProviderScope.containerOf] while the
/// scope is still mounted) — not [WidgetRef] — when calling after async gaps
/// such as [auth.signOut], because the originating widget may unmount first.
Future<void> resetPharmacySessionProviders(
  ProviderContainer container, {
  String? teamId,
}) async {
  container.invalidate(pharmacyRedirectCacheProvider);
  container.read(branchChangeGuardProvider.notifier).discardAll();
  await container.read(selectedBranchIdProvider.notifier).setBranch(null);
  container.invalidate(pharmacyProfileProvider);
  container.invalidate(platformOpsProvider);
  if (teamId != null && teamId.isNotEmpty) {
    container.invalidate(teamShellMetaProvider(teamId));
    container.invalidate(branchesListProvider(teamId));
  }
}
