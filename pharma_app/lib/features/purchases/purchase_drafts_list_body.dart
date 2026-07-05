import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/refresh_alerts_silent.dart';
import '../../core/widgets/app_error_state.dart';
import 'purchase_drafts_refresh_provider.dart';

/// Draft purchases list without a [Scaffold] — for [PurchasesHubPage].
class PurchaseDraftsListBody extends ConsumerStatefulWidget {
  const PurchaseDraftsListBody({super.key, this.onCreatePurchase});

  /// Opens the focused purchase editor (e.g. from empty state).
  final VoidCallback? onCreatePurchase;

  @override
  ConsumerState<PurchaseDraftsListBody> createState() =>
      _PurchaseDraftsListBodyState();
}

class _PurchaseDraftsListBodyState
    extends ConsumerState<PurchaseDraftsListBody> {
  bool _loading = true;
  String? _error;
  String? _receivingPurchaseId;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final profile = await ref.read(pharmacyProfileProvider.future);
    final teamId = profile?['team_id'] as String?;
    if (!mounted) return;
    if (teamId == null) {
      setState(() {
        _loading = false;
        _error = 'No team';
      });
      return;
    }
    final branchId = ref.read(selectedBranchIdProvider);
    if (branchId == null) {
      setState(() {
        _loading = false;
        _error = 'Select a branch first.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Supabase.instance.client
          .from('purchases')
          .select('id, created_at, invoice_reference, supplier_id, status')
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .eq('status', 'draft')
          .order('created_at', ascending: false);
      final purchases = List<Map<String, dynamic>>.from(data as List);
      final supplierIds = purchases
          .map((p) => p['supplier_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final Map<String, String> supplierNames = {};
      if (supplierIds.isNotEmpty) {
        final supRows = await Supabase.instance.client
            .from('suppliers')
            .select('id, name')
            .eq('team_id', teamId)
            .inFilter('id', supplierIds);
        for (final s in List<Map<String, dynamic>>.from(supRows as List)) {
          supplierNames[s['id'] as String] = s['name'] as String? ?? '';
        }
      }
      final purchaseIds = purchases.map((p) => p['id'] as String).toList();
      final Map<String, List<Map<String, dynamic>>> lineItems = {};
      if (purchaseIds.isNotEmpty) {
        final items = await Supabase.instance.client
            .from('purchase_items')
            .select(
              'id, purchase_id, batch_no, expiry_date, qty_base_unit, unit_cost, sell_price, medicines(name, manual_code, barcode)',
            )
            .inFilter('purchase_id', purchaseIds)
            .order('id');
        for (final row in List<Map<String, dynamic>>.from(items as List)) {
          final pid = row['purchase_id'] as String;
          (lineItems[pid] ??= <Map<String, dynamic>>[]).add(row);
        }
      }
      for (final p in purchases) {
        final sid = p['supplier_id'] as String?;
        p['_supplier_name'] = sid != null ? supplierNames[sid] ?? '' : '';
        final lines =
            lineItems[p['id'] as String] ?? const <Map<String, dynamic>>[];
        p['_line_count'] = lines.length;
        p['_line_items'] = lines;
      }
      if (!mounted) return;
      setState(() => _rows = purchases);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load draft purchases. Pull to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static num _coerceNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _formatQty(dynamic value) {
    final n = _coerceNum(value).toDouble();
    if (n == n.roundToDouble()) return n.round().toString();
    return n.toStringAsFixed(2);
  }

  static String _formatMoney(dynamic value) {
    return _coerceNum(value).toDouble().toStringAsFixed(2);
  }

  static String _formatExpiry(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.length >= 10) return raw.substring(0, 10);
    return raw;
  }

  static String _formatCreatedAt(BuildContext context, dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.split('.').first;
    final local = parsed.toLocal();
    final material = MaterialLocalizations.of(context);
    final date = material.formatMediumDate(local);
    final time = TimeOfDay.fromDateTime(local).format(context);
    return '$date · $time';
  }

  Future<void> _receiveDraft(Map<String, dynamic> purchase) async {
    final id = purchase['id'] as String?;
    if (id == null || id.isEmpty) return;
    final lineItems = List<Map<String, dynamic>>.from(
      purchase['_line_items'] as List? ?? const [],
    );
    if (lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one line before receiving.'),
        ),
      );
      return;
    }

    final lineSummaries = lineItems
        .map((row) {
          final med = Map<String, dynamic>.from(
            row['medicines'] as Map? ?? const {},
          );
          final name = med['name'] as String? ?? 'Medicine';
          final qty = _formatQty(row['qty_base_unit']);
          return '· $name — +$qty base units';
        })
        .join('\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Receive goods?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Stock will increase for ${lineItems.length} line(s).',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              SelectableText(
                lineSummaries,
                style: Theme.of(
                  ctx,
                ).textTheme.bodySmall?.copyWith(height: 1.45),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Receive'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _receivingPurchaseId = id;
      _error = null;
    });
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    try {
      await Supabase.instance.client.rpc(
        'receive_purchase',
        params: {'p_purchase_id': id},
      );
      if (teamId != null && branchId != null) {
        await refreshAlertsSilent(teamId: teamId, branchId: branchId);
      }
      if (!mounted) return;
      ref.read(purchaseDraftsRefreshProvider.notifier).bump();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase received. Stock updated.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _receivingPurchaseId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(purchaseDraftsRefreshProvider, (prev, next) {
      if (prev != null && prev != next) {
        Future.microtask(() {
          if (mounted) _load();
        });
      }
    });

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'No draft purchases for this branch.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Start one purchase, add its lines there, then receive it when goods arrive.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (widget.onCreatePurchase != null) {
                    widget.onCreatePurchase!();
                  } else {
                    context.go('/pharmacy/purchases?tab=new');
                  }
                },
                child: const Text('New purchase'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: _rows.length,
        itemBuilder: (context, i) {
          final p = _rows[i];
          final t = Theme.of(context);
          final cs = t.colorScheme;
          final name = p['_supplier_name'] as String? ?? '';
          final inv = (p['invoice_reference'] as String?)?.trim();
          final lines = p['_line_count'] as int? ?? 0;
          final lineItems = List<Map<String, dynamic>>.from(
            p['_line_items'] as List? ?? const [],
          );
          final created = p['created_at'];
          final title = name.isEmpty ? 'Supplier' : name;
          final isReceiving = _receivingPurchaseId == p['id'];
          final meta = <String>[
            '$lines line${lines == 1 ? '' : 's'}',
            if (inv != null && inv.isNotEmpty) inv,
            if (created != null) _formatCreatedAt(context, created),
          ].join(' · ');

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.8),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.expand_more_rounded),
              children: [
                if (lineItems.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No lines yet. Open the draft to add medicines.',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ...lineItems.map((row) {
                    final med = Map<String, dynamic>.from(
                      row['medicines'] as Map? ?? const {},
                    );
                    final medName = med['name'] as String? ?? 'Medicine';
                    final code = [med['manual_code'], med['barcode']]
                        .whereType<String>()
                        .where((v) => v.isNotEmpty)
                        .join(' / ');
                    final batch = row['batch_no'] as String? ?? '';
                    final qty = _formatQty(row['qty_base_unit']);
                    final cost = _formatMoney(row['unit_cost']);
                    final sellPrice = row['sell_price'];
                    final sell = sellPrice == null
                        ? ''
                        : ' · Sell ${_formatMoney(sellPrice)} ETB';
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.35,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (code.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              code,
                              style: t.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text('Qty $qty · Cost $cost ETB$sell'),
                          const SizedBox(height: 4),
                          Text(
                            'Batch $batch · Expiry ${_formatExpiry(row['expiry_date'])}',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await context.push('/pharmacy/purchases/${p['id']}');
                          if (mounted) await _load();
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: isReceiving || lineItems.isEmpty
                            ? null
                            : () => _receiveDraft(p),
                        icon: isReceiving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.inventory_rounded),
                        label: Text(isReceiving ? 'Receiving' : 'Receive'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
