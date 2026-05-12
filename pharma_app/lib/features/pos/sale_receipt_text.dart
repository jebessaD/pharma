import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/date_formatters.dart';
import '../../core/utils/etb_amount_display.dart';

String _receiptMoney(Object? v) {
  if (v is num) return formatEtbAmount(v);
  final n = num.tryParse(v?.toString().trim() ?? '');
  if (n != null) return formatEtbAmount(n);
  return v?.toString() ?? '';
}

String salePaymentMethodLabel(String method) {
  return switch (method) {
    'mobile_banking' => 'Mobile banking',
    'bank_transfer' => 'Bank',
    'cash' => 'Cash',
    _ => method,
  };
}

String formatSaleReceiptText({
  required Map<String, dynamic> sale,
  String? branchName,
  String? sellerDisplayName,
}) {
  final created = sale['created_at'];
  DateTime? dt;
  if (created is String) {
    dt = DateTime.tryParse(created);
  }
  final buf = StringBuffer();
  buf.writeln('Pharma Shelf');
  buf.writeln('Sales receipt');
  if (dt != null) buf.writeln('Date: ${formatDdMmYyyyHm(dt)}');
  if (branchName != null && branchName.trim().isNotEmpty) {
    buf.writeln('Branch: ${branchName.trim()}');
  }
  if (sellerDisplayName != null && sellerDisplayName.trim().isNotEmpty) {
    buf.writeln('Served by: ${sellerDisplayName.trim()}');
  }
  buf.writeln('---');
  final items = sale['sale_items'] as List? ?? [];
  for (final raw in items) {
    final it = Map<String, dynamic>.from(raw as Map);
    final mb = it['medicine_batches'] as Map?;
    final med = mb?['medicines'] as Map?;
    final name = med?['name'] as String? ?? 'Item';
    final batch = mb?['batch_no'] as String? ?? '';
    final qty = it['qty'];
    final up = it['unit_price'];
    final lt = it['line_total'];
    buf.writeln('$name (batch $batch)');
    buf.writeln('  $qty × ${_receiptMoney(up)} ETB = ${_receiptMoney(lt)} ETB');
  }
  buf.writeln('---');
  buf.writeln('Subtotal: ${_receiptMoney(sale['subtotal'])} ETB');
  final disc = sale['discount_total'] as num? ?? 0;
  if (disc > 0) {
    buf.writeln('Discount: -${_receiptMoney(disc)} ETB');
  }
  buf.writeln('TOTAL: ${_receiptMoney(sale['grand_total'])} ETB');
  final pays = sale['payments'] as List? ?? [];
  for (final raw in pays) {
    final p = Map<String, dynamic>.from(raw as Map);
    final m = p['method'] as String? ?? '';
    buf.writeln(
      'Paid: ${salePaymentMethodLabel(m)} ${_receiptMoney(p['amount'])} ETB',
    );
    final ref = p['reference_no'] as String?;
    if (ref != null && ref.isNotEmpty) buf.writeln('Ref: $ref');
  }
  buf.writeln('Thank you.');
  return buf.toString();
}

/// Loads sale + branch + seller and returns plain-text receipt, or null if unavailable.
Future<String?> loadSaleReceiptPlainText(
  SupabaseClient client,
  String saleId,
) async {
  final sale = await client
      .from('sales')
      .select(
        'id, created_at, subtotal, discount_total, grand_total, branch_id, sold_by, '
        'sale_items(qty, unit_price, line_total, medicine_batches(batch_no, medicines(name))), '
        'payments(method, amount, reference_no)',
      )
      .eq('id', saleId)
      .maybeSingle();
  if (sale == null) return null;
  final row = Map<String, dynamic>.from(sale);
  final branchId = row['branch_id'] as String?;
  String? bname;
  if (branchId != null) {
    final b = await client
        .from('branches')
        .select('name')
        .eq('id', branchId)
        .maybeSingle();
    bname = b?['name'] as String?;
  }
  final soldBy = row['sold_by'] as String?;
  String? sellerName;
  if (soldBy != null && soldBy.isNotEmpty) {
    final prof = await client
        .from('profiles')
        .select('full_name, username')
        .eq('id', soldBy)
        .maybeSingle();
    if (prof != null) {
      final fn = (prof['full_name'] as String?)?.trim() ?? '';
      final un = (prof['username'] as String?)?.trim() ?? '';
      sellerName = fn.isNotEmpty ? fn : (un.isNotEmpty ? un : 'Team member');
    }
  }
  return formatSaleReceiptText(
    sale: row,
    branchName: bname,
    sellerDisplayName: sellerName,
  );
}
