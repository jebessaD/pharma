import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cached POS read model (medicines + branch stock) for offline search and line add.
class PosCatalogSnapshot {
  PosCatalogSnapshot({
    required this.teamId,
    required this.branchId,
    required this.savedAt,
    required this.medicines,
    required this.stockLines,
  });

  final String teamId;
  final String branchId;
  final DateTime savedAt;
  final List<Map<String, dynamic>> medicines;
  /// Each row: medicine_batch_id, qty_base_unit, plus nested medicine_batches fields.
  final List<Map<String, dynamic>> stockLines;

  Map<String, num> qtyByMedicineId() {
    final m = <String, num>{};
    for (final r in stockLines) {
      final mb = r['medicine_batches'] as Map<String, dynamic>?;
      final mid = mb?['medicine_id'] as String?;
      if (mid == null) continue;
      final q = (r['qty_base_unit'] as num?) ?? 0;
      m[mid] = (m[mid] ?? 0) + q;
    }
    return m;
  }

  List<Map<String, dynamic>> batchesWithQtyForMedicine(String medicineId) {
    final out = <Map<String, dynamic>>[];
    for (final r in stockLines) {
      final mb = r['medicine_batches'] as Map<String, dynamic>?;
      if (mb == null) continue;
      if ((mb['medicine_id'] as String?) != medicineId) continue;
      final bid = (mb['id'] ?? r['medicine_batch_id']) as String?;
      if (bid == null) continue;
      final q = (r['qty_base_unit'] as num?) ?? 0;
      if (q <= 0) continue;
      out.add({
        'id': bid,
        'batch_no': mb['batch_no'],
        'expiry_date': mb['expiry_date'],
        'qty_on_hand': q,
      });
    }
    out.sort((a, b) {
      final da = '${a['expiry_date'] ?? ''}';
      final db = '${b['expiry_date'] ?? ''}';
      return da.compareTo(db);
    });
    return out;
  }

  Map<String, dynamic> toJson() => {
        'team_id': teamId,
        'branch_id': branchId,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'medicines': medicines,
        'stock_lines': stockLines,
      };

  static PosCatalogSnapshot? fromJson(Map<String, dynamic> j) {
    try {
      final teamId = j['team_id'] as String?;
      final branchId = j['branch_id'] as String?;
      final raw = j['saved_at'] as String?;
      if (teamId == null || branchId == null || raw == null) return null;
      return PosCatalogSnapshot(
        teamId: teamId,
        branchId: branchId,
        savedAt: DateTime.parse(raw),
        medicines: (j['medicines'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
        stockLines: (j['stock_lines'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
      );
    } catch (_) {
      return null;
    }
  }
}

class PosCatalogCacheRepository {
  PosCatalogCacheRepository(this._prefs);

  final SharedPreferences _prefs;

  static String _key(String teamId, String branchId) =>
      'pos_catalog_v1_${teamId}_$branchId';

  Future<void> save(PosCatalogSnapshot snap) async {
    await _prefs.setString(
      _key(snap.teamId, snap.branchId),
      jsonEncode(snap.toJson()),
    );
  }

  Future<PosCatalogSnapshot?> load(String teamId, String branchId) async {
    final raw = _prefs.getString(_key(teamId, branchId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      return PosCatalogSnapshot.fromJson(Map<String, dynamic>.from(j));
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String teamId, String branchId) async {
    await _prefs.remove(_key(teamId, branchId));
  }
}
