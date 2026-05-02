import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/sync_status_provider.dart';
import '../../../core/shared_preferences_provider.dart';
import 'pos_catalog_cache_repository.dart';
import 'pos_outbox_repository.dart';
import 'pos_sync_service.dart';

final posOutboxRepositoryProvider = Provider<PosOutboxRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PosOutboxRepository(prefs);
});

final posCatalogCacheRepositoryProvider = Provider<PosCatalogCacheRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PosCatalogCacheRepository(prefs);
});

final posSyncServiceProvider = Provider<PosSyncService>((ref) {
  final repo = ref.watch(posOutboxRepositoryProvider);
  final service = PosSyncService(ref, repo)..start();

  ref.listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
    final online = next.value ?? false;
    unawaited(service.syncPending(isOnline: online));
  });
  ref.onDispose(service.stop);
  return service;
});

final posPendingCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(posOutboxRepositoryProvider);
  final count = await repo.pendingCount();
  ref.read(syncStatusProvider.notifier).updatePending(count);
  return count;
});

final posFailedSalesCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(posOutboxRepositoryProvider);
  return repo.failedSalesCount();
});
