import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/app_error_state.dart';
import 'purchase_drafts_refresh_provider.dart';

/// Draft purchases list without a [Scaffold] — for [PurchasesHubPage] tab.
class PurchaseDraftsListBody extends ConsumerStatefulWidget {
  const PurchaseDraftsListBody({super.key, this.onSwitchToNewTab});

  /// Opens the hub "New purchase" tab (e.g. from empty state).
  final VoidCallback? onSwitchToNewTab;

  @override
  ConsumerState<PurchaseDraftsListBody> createState() =>
      _PurchaseDraftsListBodyState();
}

class _PurchaseDraftsListBodyState extends ConsumerState<PurchaseDraftsListBody> {
  bool _loading = true;
  String? _error;
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
          .select(
            'id, created_at, invoice_reference, supplier_id, status',
          )
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
      final purchaseIds =
          purchases.map((p) => p['id'] as String).toList();
      final Map<String, int> lineCounts = {};
      if (purchaseIds.isNotEmpty) {
        final items = await Supabase.instance.client
            .from('purchase_items')
            .select('purchase_id')
            .inFilter('purchase_id', purchaseIds);
        for (final row in List<Map<String, dynamic>>.from(items as List)) {
          final pid = row['purchase_id'] as String;
          lineCounts[pid] = (lineCounts[pid] ?? 0) + 1;
        }
      }
      for (final p in purchases) {
        final sid = p['supplier_id'] as String?;
        p['_supplier_name'] = sid != null ? supplierNames[sid] ?? '' : '';
        p['_line_count'] = lineCounts[p['id'] as String] ?? 0;
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
              Text(
                'No draft purchases for this branch.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (widget.onSwitchToNewTab != null) {
                    widget.onSwitchToNewTab!();
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _rows.length,
        itemBuilder: (context, i) {
          final p = _rows[i];
          final name = p['_supplier_name'] as String? ?? '';
          final inv = (p['invoice_reference'] as String?)?.trim();
          final lines = p['_line_count'] as int? ?? 0;
          final created = p['created_at'];
          String subtitle = '$lines line${lines == 1 ? '' : 's'}';
          if (inv != null && inv.isNotEmpty) {
            subtitle += ' · $inv';
          }
          if (created != null) {
            subtitle += '\n${created.toString().split('.').first}';
          }
          return ListTile(
            title: Text(
              name.isEmpty ? 'Supplier' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/pharmacy/purchases/${p['id']}'),
          );
        },
      ),
    );
  }
}
