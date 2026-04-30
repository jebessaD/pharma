import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/forms/form_error_mapper.dart';
import '../../../core/providers/sync_status_provider.dart';
import 'offline_sale_dto.dart';
import 'pos_outbox_repository.dart';

class PosSyncService {
  PosSyncService(this._ref, this._repo);

  final Ref _ref;
  final PosOutboxRepository _repo;
  Timer? _pollTimer;
  bool _inFlight = false;

  void start() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(syncPending(isOnline: true));
    });
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> syncPending({required bool isOnline}) async {
    final notifier = _ref.read(syncStatusProvider.notifier);
    if (!isOnline) {
      notifier.markOffline();
      notifier.updatePending(await _repo.pendingCount());
      return;
    }
    if (_inFlight) return;
    _inFlight = true;
    try {
      notifier.markSyncing();
      final pending = await _repo.getPending();
      notifier.updatePending(pending.length);
      for (final sale in pending) {
        await _syncOne(sale);
      }
      await _repo.clearSynced();
      notifier.updatePending(await _repo.pendingCount());
      notifier.markSyncedNow();
    } catch (e) {
      notifier.markFailed(userFacingError(e));
    } finally {
      _inFlight = false;
      if (_ref.read(syncStatusProvider).pendingCount == 0) {
        notifier.markIdle();
      }
    }
  }

  Future<String?> syncSingleQueuedSale(
    OfflineSaleDto sale, {
    required bool isOnline,
  }) async {
    final notifier = _ref.read(syncStatusProvider.notifier);
    if (!isOnline) {
      notifier.markOffline();
      notifier.updatePending(await _repo.pendingCount());
      return null;
    }
    notifier.markSyncing();
    final syncedId = await _syncOne(sale);
    await _repo.clearSynced();
    notifier.updatePending(await _repo.pendingCount());
    notifier.markSyncedNow();
    return syncedId;
  }

  bool _isTransient(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection');
  }

  bool _isMissingCreateSaleSignature(Object error) {
    if (error is! PostgrestException) return false;
    final lower = error.message.toLowerCase();
    return error.code == 'PGRST202' ||
        lower.contains('could not find the function public.create_sale');
  }

  Future<dynamic> _createSaleRpc(OfflineSaleDto sale) async {
    try {
      return await Supabase.instance.client.rpc(
        'create_sale',
        params: {
          'p_branch_id': sale.branchId,
          'p_items': sale.items,
          'p_method': sale.paymentMethod,
          'p_reference_no': sale.referenceNo,
          'p_discount_total': sale.discountTotal,
          'p_client_operation_id': sale.localOperationId,
        },
      );
    } catch (error) {
      if (!_isMissingCreateSaleSignature(error)) rethrow;
      // Backward-compatible fallback for databases that still expose
      // the legacy 5-argument RPC signature in schema cache.
      return Supabase.instance.client.rpc(
        'create_sale',
        params: {
          'p_branch_id': sale.branchId,
          'p_items': sale.items,
          'p_method': sale.paymentMethod,
          'p_reference_no': sale.referenceNo,
          'p_discount_total': sale.discountTotal,
        },
      );
    }
  }

  Future<String?> _syncOne(OfflineSaleDto sale) async {
    final inProgress = sale.copyWith(
      status: OfflineSaleSyncStatus.syncing,
      lastError: null,
    );
    await _repo.update(inProgress);
    try {
      final saleId = await _createSaleRpc(sale);
      final synced = sale.copyWith(
        status: OfflineSaleSyncStatus.synced,
        syncedSaleId: saleId?.toString(),
        lastError: null,
      );
      await _repo.update(synced);
      return saleId?.toString();
    } catch (error) {
      final transient = _isTransient(error);
      final failed = sale.copyWith(
        status: transient
            ? OfflineSaleSyncStatus.pending
            : OfflineSaleSyncStatus.failed,
        retryCount: sale.retryCount + 1,
        lastError: userFacingError(error),
      );
      await _repo.update(failed);
      if (!transient) rethrow;
      return null;
    }
  }
}
