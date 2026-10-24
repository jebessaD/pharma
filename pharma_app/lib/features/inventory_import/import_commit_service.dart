import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/refresh_alerts_silent.dart';
import '../../core/widgets/slash_dd_mm_yyyy_input.dart';
import 'import_medicine_similarity.dart';
import 'import_models.dart';
import 'import_review_row.dart';

/// A single committable row resolved to a medicine id with valid fields.
class _CommitRow {
  const _CommitRow({
    required this.medicineId,
    required this.batchNo,
    required this.expiryIso,
    required this.qty,
    this.unitCost,
    this.sellPrice,
    this.medicineCreated = false,
    this.sourceRowIndex,
  });

  final String medicineId;
  final String? batchNo;
  final String expiryIso;
  final num qty;
  final num? unitCost;
  final num? sellPrice;
  final bool medicineCreated;
  final int? sourceRowIndex;
}

class ImportCommitResult {
  const ImportCommitResult({
    required this.committed,
    required this.skipped,
    this.purchaseId,
    this.importBatchId,
  });

  final int committed;
  final int skipped;

  /// Set when a purchase draft was created.
  final String? purchaseId;

  /// Set when stock-in was tracked for undo history.
  final String? importBatchId;
}

/// Commits reviewed import rows to either a purchase draft or direct stock-in.
class ImportCommitService {
  ImportCommitService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  List<_CommitRow> _collect(List<ImportReviewRow> rows, DateTime today) {
    final out = <_CommitRow>[];
    for (final r in rows) {
      if (r.removed) continue;
      if (!r.isCommittable(today)) continue;
      final mid = r.medicineId;
      if (mid == null) continue;
      final iso = slashDdMmYyyyToIso(r.expiry.text.trim());
      final qty = parseImportQty(r.qty.text);
      if (iso == null || qty == null || qty <= 0) continue;
      final batch = r.batchNo.text.trim();
      out.add(
        _CommitRow(
          medicineId: mid,
          batchNo: batch.isEmpty ? null : batch,
          expiryIso: iso,
          qty: qty,
          unitCost: num.tryParse(r.unitCost.text.trim()),
          sellPrice: num.tryParse(r.sellPrice.text.trim()),
          medicineCreated: r.medicineCreated,
          sourceRowIndex: r.source.rowIndex,
        ),
      );
    }
    return out;
  }

  int _remaining(List<ImportReviewRow> rows, DateTime today, int committed) {
    final total =
        rows.where((r) => !r.removed).length;
    return (total - committed).clamp(0, total);
  }

  /// Direct stock-in through `bulk_stock_in` (or tracked RPC when meta given).
  Future<ImportCommitResult> commitStockIn({
    required String teamId,
    required String branchId,
    required List<ImportReviewRow> rows,
    required DateTime today,
    String? sourceKind,
    String? sourceFilename,
    String? sheetName,
    Map<String, dynamic>? meta,
  }) async {
    final ready = _collect(rows, today);
    if (ready.isEmpty) {
      return ImportCommitResult(
        committed: 0,
        skipped: _remaining(rows, today, 0),
      );
    }
    final track = sourceKind != null && sourceKind.isNotEmpty;
    final items = ready
        .map(
          (r) => <String, dynamic>{
            'medicine_id': r.medicineId,
            if (r.batchNo != null) 'batch_no': r.batchNo,
            'expiry_date': r.expiryIso,
            'qty': r.qty,
            if (r.unitCost != null) 'unit_cost': r.unitCost,
            if (r.sellPrice != null) 'sell_price': r.sellPrice,
            if (track) 'medicine_created': r.medicineCreated,
            if (track && r.sourceRowIndex != null)
              'source_row_index': r.sourceRowIndex,
          },
        )
        .toList();

    String? importBatchId;
    if (track) {
      final data = await _client.rpc(
        'bulk_stock_in_tracked',
        params: {
          'p_branch_id': branchId,
          'p_items': items,
          'p_source_kind': sourceKind,
          'p_source_filename': sourceFilename,
          'p_sheet_name': sheetName,
          'p_meta': meta,
        },
      );
      if (data is Map && data['import_batch_id'] != null) {
        importBatchId = '${data['import_batch_id']}';
      }
    } else {
      await _client.rpc(
        'bulk_stock_in',
        params: {'p_branch_id': branchId, 'p_items': items},
      );
    }
    await refreshAlertsSilent(teamId: teamId, branchId: branchId);
    return ImportCommitResult(
      committed: ready.length,
      skipped: _remaining(rows, today, ready.length),
      importBatchId: importBatchId,
    );
  }

  /// Creates a `purchases` draft plus `purchase_items`. Does not receive it;
  /// the user reviews and receives on the purchase draft screen.
  Future<ImportCommitResult> commitPurchaseDraft({
    required String teamId,
    required String branchId,
    required List<ImportReviewRow> rows,
    required DateTime today,
    String? supplierId,
    String? invoiceReference,
  }) async {
    final ready = _collect(rows, today);
    if (ready.isEmpty) {
      return ImportCommitResult(
        committed: 0,
        skipped: _remaining(rows, today, 0),
      );
    }
    final purchase = await _client
        .from('purchases')
        .insert({
          'team_id': teamId,
          'branch_id': branchId,
          'supplier_id': supplierId,
          'invoice_reference':
              (invoiceReference == null || invoiceReference.trim().isEmpty)
              ? null
              : invoiceReference.trim(),
          'status': 'draft',
        })
        .select('id')
        .single();
    final purchaseId = purchase['id'] as String;

    // purchase_items.batch_no is NOT NULL; fall back to empty string.
    final itemRows = ready
        .map(
          (r) => <String, dynamic>{
            'purchase_id': purchaseId,
            'medicine_id': r.medicineId,
            'batch_no': r.batchNo ?? '',
            'expiry_date': r.expiryIso,
            'qty_base_unit': r.qty,
            'unit_cost': r.unitCost ?? 0,
            if (r.sellPrice != null) 'sell_price': r.sellPrice,
          },
        )
        .toList();
    await _client.from('purchase_items').insert(itemRows);

    return ImportCommitResult(
      committed: ready.length,
      skipped: _remaining(rows, today, ready.length),
      purchaseId: purchaseId,
    );
  }

  /// Committing to [ImportMode] convenience wrapper.
  Future<ImportCommitResult> commit({
    required ImportMode mode,
    required String teamId,
    required String branchId,
    required List<ImportReviewRow> rows,
    required DateTime today,
    String? supplierId,
    String? invoiceReference,
    String? sourceKind,
    String? sourceFilename,
    String? sheetName,
    Map<String, dynamic>? meta,
  }) {
    if (mode == ImportMode.directStockIn) {
      return commitStockIn(
        teamId: teamId,
        branchId: branchId,
        rows: rows,
        today: today,
        sourceKind: sourceKind,
        sourceFilename: sourceFilename,
        sheetName: sheetName,
        meta: meta,
      );
    }
    return commitPurchaseDraft(
      teamId: teamId,
      branchId: branchId,
      rows: rows,
      today: today,
      supplierId: supplierId,
      invoiceReference: invoiceReference,
    );
  }
}
