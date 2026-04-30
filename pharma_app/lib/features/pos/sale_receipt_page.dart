import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';

class SaleReceiptPage extends StatefulWidget {
  const SaleReceiptPage({super.key, required this.saleId});

  final String saleId;

  @override
  State<SaleReceiptPage> createState() => _SaleReceiptPageState();
}

String _paymentMethodLabel(String method) {
  return switch (method) {
    'mobile_banking' => 'Mobile banking',
    'bank_transfer' => 'Bank',
    'cash' => 'Cash',
    _ => method,
  };
}

class _SaleReceiptPageState extends State<SaleReceiptPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _sale;
  String? _branchName;
  String? _sellerDisplayName;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sale = await Supabase.instance.client
          .from('sales')
          .select(
            'id, created_at, subtotal, discount_total, grand_total, branch_id, sold_by, '
            'sale_items(qty, unit_price, line_total, medicine_batches(batch_no, medicines(name))), '
            'payments(method, amount, reference_no)',
          )
          .eq('id', widget.saleId)
          .maybeSingle();
      if (!mounted) return;
      if (sale == null) {
        setState(() {
          _loading = false;
          _error = 'Sale not found or you do not have access.';
        });
        return;
      }
      final branchId = sale['branch_id'] as String?;
      String? bname;
      if (branchId != null) {
        final b = await Supabase.instance.client
            .from('branches')
            .select('name')
            .eq('id', branchId)
            .maybeSingle();
        bname = b?['name'] as String?;
      }
      final soldBy = sale['sold_by'] as String?;
      String? sellerName;
      if (soldBy != null && soldBy.isNotEmpty) {
        final prof = await Supabase.instance.client
            .from('profiles')
            .select('full_name, username')
            .eq('id', soldBy)
            .maybeSingle();
        if (prof != null) {
          final fn = (prof['full_name'] as String?)?.trim() ?? '';
          final un = (prof['username'] as String?)?.trim() ?? '';
          sellerName = fn.isNotEmpty
              ? fn
              : (un.isNotEmpty ? un : 'Team member');
        }
      }
      setState(() {
        _sale = Map<String, dynamic>.from(sale);
        _branchName = bname;
        _sellerDisplayName = sellerName;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = userFacingError(e);
        });
      }
    }
  }

  String _buildReceiptText() {
    final s = _sale!;
    final created = s['created_at'];
    DateTime? dt;
    if (created is String) {
      dt = DateTime.tryParse(created);
    }
    final buf = StringBuffer();
    buf.writeln('PHARMACY RECEIPT');
    if (dt != null) buf.writeln('Date: ${formatDdMmYyyyHm(dt)}');
    if (_branchName != null && _branchName!.trim().isNotEmpty) {
      buf.writeln('Branch: ${_branchName!.trim()}');
    }
    if (_sellerDisplayName != null && _sellerDisplayName!.trim().isNotEmpty) {
      buf.writeln('Served by: ${_sellerDisplayName!.trim()}');
    }
    buf.writeln('---');
    final items = s['sale_items'] as List? ?? [];
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
      buf.writeln('  $qty × $up ETB = $lt ETB');
    }
    buf.writeln('---');
    buf.writeln('Subtotal: ${s['subtotal']} ETB');
    final disc = s['discount_total'] as num? ?? 0;
    if (disc > 0) buf.writeln('Discount: -$disc ETB');
    buf.writeln('TOTAL: ${s['grand_total']} ETB');
    final pays = s['payments'] as List? ?? [];
    for (final raw in pays) {
      final p = Map<String, dynamic>.from(raw as Map);
      final m = p['method'] as String? ?? '';
      buf.writeln('Paid: ${_paymentMethodLabel(m)} ${p['amount']} ETB');
      final ref = p['reference_no'] as String?;
      if (ref != null && ref.isNotEmpty) buf.writeln('Ref: $ref');
    }
    buf.writeln('Thank you.');
    return buf.toString();
  }

  Future<void> _share() async {
    await Share.share(_buildReceiptText(), subject: 'Pharmacy receipt');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          if (_sale != null)
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined),
              onPressed: _share,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? AppErrorState(message: _error!, onRetry: _load)
          : _sale == null
          ? const Center(child: Text('Nothing to show'))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                SelectableText(_buildReceiptText()),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share),
                  label: const Text('Share receipt'),
                ),
              ],
            ),
    );
  }
}
