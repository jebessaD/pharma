import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/medicine/medicine_display.dart';
import '../../core/medicine_category_catalog.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/utils/etb_amount_display.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';
import 'batch_edit_sheet.dart';
import 'stock_in_helpers.dart';

class MedicineDetailPage extends ConsumerStatefulWidget {
  const MedicineDetailPage({super.key, required this.medicineId});

  final String medicineId;

  @override
  ConsumerState<MedicineDetailPage> createState() => _MedicineDetailPageState();
}

class _MedicineDetailPageState extends ConsumerState<MedicineDetailPage> {
  Map<String, dynamic>? _medicine;
  List<Map<String, dynamic>> _batches = [];
  bool _loading = true;
  String? _error;

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
      final branchId = ref.read(selectedBranchIdProvider);
      if (branchId == null) {
        setState(() => _error = 'Select a branch first.');
        return;
      }
      final m = await Supabase.instance.client
          .from('medicines')
          .select()
          .eq('id', widget.medicineId)
          .eq('branch_id', branchId)
          .single();
      final batches = await Supabase.instance.client
          .from('medicine_batches')
          .select(
            'id, batch_no, expiry_date, unit_cost_base, sell_price_base, '
            'stock_balances(qty_base_unit)',
          )
          .eq('medicine_id', widget.medicineId)
          .eq('branch_id', branchId)
          .order('expiry_date');
      setState(() {
        _medicine = Map<String, dynamic>.from(m);
        _batches = List<Map<String, dynamic>>.from(batches as List);
      });
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  num _qtyForBatch(Map<String, dynamic> batch) {
    final balances = batch['stock_balances'];
    if (balances is List && balances.isNotEmpty) {
      return (balances.first['qty_base_unit'] as num?) ?? 0;
    }
    if (balances is Map) {
      return (balances['qty_base_unit'] as num?) ?? 0;
    }
    return (batch['quantity_in_base_unit'] as num?) ?? 0;
  }

  Future<void> _addBatch() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch in the app bar');
      return;
    }
    final medicine = _medicine;
    if (medicine == null) return;
    final payload = await showAddBatchSheet(
      context: context,
      defaultBuy: medicine['purchase_price'] as num?,
      defaultSell: medicine['selling_price'] as num?,
    );
    if (!context.mounted || payload == null) return;
    try {
      if (payload.qty != null && payload.qty! > 0) {
        await stockInNewBatch(
          client: Supabase.instance.client,
          teamId: teamId,
          branchId: branchId,
          medicineId: widget.medicineId,
          batchNo: payload.batchNo,
          expiryIso: payload.expiryIso,
          qty: payload.qty!,
          unitCost: payload.unitCost,
          sellPrice: payload.sellPrice,
          refType: 'manual_batch_initial',
          reason: 'manual_batch_initial',
        );
      } else {
        await Supabase.instance.client.from('medicine_batches').insert({
          'team_id': teamId,
          'branch_id': branchId,
          'medicine_id': widget.medicineId,
          'batch_no': payload.batchNo,
          'expiry_date': payload.expiryIso,
          'quantity_in_base_unit': 0,
          'unit_cost_base': payload.unitCost,
          'sell_price_base': payload.sellPrice,
        });
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> _editBatch(Map<String, dynamic> batch) async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) return;
    final batchId = batch['id'] as String?;
    if (batchId == null) return;
    final saved = await showBatchEditSheet(
      context: context,
      batch: BatchRowData(
        batchId: batchId,
        batchNo: batch['batch_no'] as String? ?? '',
        expiryIso: batch['expiry_date'] as String? ?? '',
        qtyOnHand: _qtyForBatch(batch),
        unitCost: batch['unit_cost_base'] as num?,
        sellPrice: batch['sell_price_base'] as num?,
      ),
      teamId: teamId,
      branchId: branchId,
      viewerRole: profile?['role'] as String?,
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _openEdit() async {
    await context.push('/pharmacy/medicines/${widget.medicineId}/edit');
    if (mounted) await _load();
  }

  Widget _buildHeader(BuildContext context) {
    final m = _medicine!;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final primary = medicinePrimaryLabel(m);
    final brand = medicineSecondaryLabel(m);
    final code = m['manual_code'] as String?;
    final category = medicineCategoryLabel(m['category_key'] as String?);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primary,
                        style: t.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (brand != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          brand,
                          style: t.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (code != null && code.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Code: $code', style: t.textTheme.bodySmall),
                      ],
                      if (category.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(category, style: t.textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _openEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchCard(BuildContext context, Map<String, dynamic> batch) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final batchNo = (batch['batch_no'] as String?)?.trim() ?? '';
    final label = batchNo.isEmpty ? 'No batch number' : batchNo;
    final qty = _qtyForBatch(batch);
    final buy = batch['unit_cost_base'] as num?;
    final sell = batch['sell_price_base'] as num?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _editBatch(batch),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: t.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Exp ${formatDdMmYyyy(batch['expiry_date'])} · Qty $qty',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (buy != null || sell != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (buy != null) 'Buy ${formatEtbAmountFixed2(buy)}',
                          if (sell != null) 'Sell ${formatEtbAmountFixed2(sell)}',
                        ].join(' · '),
                        style: t.textTheme.labelMedium,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _medicine == null) {
      return Scaffold(
        appBar: pharmacyPageAppBar(context, title: 'Medicine'),
        body: AppErrorState(
          message: _error ?? 'This medicine was not found.',
          onRetry: _load,
        ),
      );
    }
    final title = medicinePrimaryLabel(_medicine!);
    return Scaffold(
      appBar: pharmacyPageAppBar(context, title: title),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Stock batches', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addBatch,
                icon: const Icon(Icons.add),
                label: const Text('Add batch'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_batches.isEmpty)
            Text(
              'No batches yet. Add one to stock in.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ..._batches.map((b) => _buildBatchCard(context, b)),
        ],
      ),
    );
  }
}
