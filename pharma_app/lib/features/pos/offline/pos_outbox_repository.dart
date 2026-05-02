import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'offline_sale_dto.dart';

class PosOutboxRepository {
  PosOutboxRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _storageKey = 'pos_outbox_v1';
  static const _uuid = Uuid();

  Future<OfflineSaleDto> enqueue({
    required String branchId,
    required String paymentMethod,
    required num discountTotal,
    required List<Map<String, dynamic>> items,
    String? referenceNo,
  }) async {
    final sale = OfflineSaleDto(
      localOperationId: _uuid.v4(),
      branchId: branchId,
      paymentMethod: paymentMethod,
      referenceNo: referenceNo,
      discountTotal: discountTotal,
      items: items,
      createdAt: DateTime.now().toUtc(),
      retryCount: 0,
      status: OfflineSaleSyncStatus.pending,
    );
    final list = await _readAll();
    list.add(sale);
    await _writeAll(list);
    return sale;
  }

  Future<List<OfflineSaleDto>> getAll() => _readAll();

  /// Sales waiting for upload. Terminal [failed] rows are excluded so sync does not retry forever.
  Future<List<OfflineSaleDto>> getPending() async {
    final list = await _readAll();
    return list
        .where((e) => e.status == OfflineSaleSyncStatus.pending)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<int> failedSalesCount() async {
    final list = await _readAll();
    return list
        .where((e) => e.status == OfflineSaleSyncStatus.failed)
        .length;
  }

  Future<void> clearFailedSales() async {
    final list = await _readAll();
    list.removeWhere((e) => e.status == OfflineSaleSyncStatus.failed);
    await _writeAll(list);
  }

  Future<void> update(OfflineSaleDto sale) async {
    final list = await _readAll();
    final idx = list.indexWhere(
      (e) => e.localOperationId == sale.localOperationId,
    );
    if (idx == -1) return;
    list[idx] = sale;
    await _writeAll(list);
  }

  Future<void> clearSynced() async {
    final list = await _readAll();
    list.removeWhere((e) => e.status == OfflineSaleSyncStatus.synced);
    await _writeAll(list);
  }

  Future<void> clearAll() async {
    await _prefs.remove(_storageKey);
  }

  /// Pending + failed rows (anything that still needs user attention in the queue UI).
  Future<int> pendingCount() async {
    final list = await _readAll();
    return list
        .where(
          (e) =>
              e.status == OfflineSaleSyncStatus.pending ||
              e.status == OfflineSaleSyncStatus.failed,
        )
        .length;
  }

  Future<List<OfflineSaleDto>> _readAll() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => OfflineSaleDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _writeAll(List<OfflineSaleDto> list) async {
    final raw = jsonEncode(list.map((e) => e.toJson()).toList());
    await _prefs.setString(_storageKey, raw);
  }
}
