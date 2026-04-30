import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharma_app/core/providers/sync_status_provider.dart';
import 'package:pharma_app/features/pos/offline/offline_sale_dto.dart';
import 'package:pharma_app/features/pos/offline/pos_outbox_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PosOutboxRepository', () {
    late SharedPreferences prefs;
    late PosOutboxRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      repo = PosOutboxRepository(prefs);
    });

    test('enqueue stores sale as pending', () async {
      final sale = await repo.enqueue(
        branchId: 'branch-1',
        paymentMethod: 'cash',
        discountTotal: 0,
        items: const [
          {'medicine_batch_id': 'batch-1', 'qty': 1, 'unit_price': 10},
        ],
      );

      final pending = await repo.getPending();
      expect(pending, hasLength(1));
      expect(pending.first.localOperationId, sale.localOperationId);
      expect(pending.first.status, OfflineSaleSyncStatus.pending);
    });

    test('clearSynced removes synced entries only', () async {
      final sale = await repo.enqueue(
        branchId: 'branch-1',
        paymentMethod: 'cash',
        discountTotal: 0,
        items: const [
          {'medicine_batch_id': 'batch-1', 'qty': 1, 'unit_price': 10},
        ],
      );
      await repo.update(
        sale.copyWith(
          status: OfflineSaleSyncStatus.synced,
          syncedSaleId: 'server-id',
        ),
      );
      await repo.clearSynced();

      final all = await repo.getAll();
      expect(all, isEmpty);
    });
  });

  group('SyncStatusNotifier', () {
    test('tracks sync lifecycle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final initial = container.read(syncStatusProvider);
      expect(initial.state, SyncState.idle);

      final notifier = container.read(syncStatusProvider.notifier);
      notifier.updatePending(2);
      notifier.markOffline();
      expect(container.read(syncStatusProvider).state, SyncState.offline);
      expect(container.read(syncStatusProvider).pendingCount, 2);

      notifier.markSyncing();
      notifier.markSyncedNow();
      expect(container.read(syncStatusProvider).state, SyncState.idle);
      expect(container.read(syncStatusProvider).lastSyncAt, isNotNull);
    });
  });
}
