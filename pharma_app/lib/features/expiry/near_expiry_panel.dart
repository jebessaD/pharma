import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/layout/layout_density.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/pharmacy_hub_list.dart';

class NearExpiryPanel extends ConsumerStatefulWidget {
  const NearExpiryPanel({super.key, this.onViewExpired});

  final VoidCallback? onViewExpired;

  @override
  ConsumerState<NearExpiryPanel> createState() => _NearExpiryPanelState();
}

class _NearExpiryPanelState extends ConsumerState<NearExpiryPanel> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  int _thresholdDays = 90;
  String _query = '';

  List<Map<String, dynamic>> get _filteredRows {
    return _rows.where((r) {
      if (_query.trim().isEmpty) return true;
      final batch = r['medicine_batches'] as Map<String, dynamic>?;
      final med = batch?['medicines'] as Map<String, dynamic>?;
      return (med?['name'] as String? ?? '').toLowerCase().contains(
            _query.trim().toLowerCase(),
          ) ||
          ('${batch?['batch_no'] ?? ''}').toLowerCase().contains(
            _query.trim().toLowerCase(),
          );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final profile = await ref.read(pharmacyProfileProvider.future);
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (!mounted) return;
    if (teamId == null || branchId == null) {
      setState(() {
        _loading = false;
        _error = 'Select a branch';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = DateTime.now().toUtc();
      final end = today.add(Duration(days: _thresholdDays));
      final todayIso = today.toIso8601String().split('T').first;
      final endIso = end.toIso8601String().split('T').first;
      final data = await Supabase.instance.client
          .from('stock_balances')
          .select(
            'qty_base_unit, medicine_batches(batch_no, expiry_date, medicines(name))',
          )
          .eq('team_id', teamId)
          .eq('branch_id', branchId);
      final rows =
          List<Map<String, dynamic>>.from(data as List).where((row) {
            final qty = (row['qty_base_unit'] as num?) ?? 0;
            final batch = row['medicine_batches'] as Map<String, dynamic>?;
            final expiry = batch?['expiry_date'] as String?;
            return qty > 0 &&
                expiry != null &&
                expiry.compareTo(todayIso) >= 0 &&
                expiry.compareTo(endIso) <= 0;
          }).toList()..sort((a, b) {
            final aBatch = a['medicine_batches'] as Map<String, dynamic>?;
            final bBatch = b['medicine_batches'] as Map<String, dynamic>?;
            return (aBatch?['expiry_date'] as String? ?? '').compareTo(
              bBatch?['expiry_date'] as String? ?? '',
            );
          });
      setState(() => _rows = rows);
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    ref.listen(selectedBranchIdProvider, (previous, next) => _load());
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.only(bottom: pharmacyHubListPadding(context).bottom),
        children: [
          PharmacyHubFilterSection(
            searchHint: 'Search medicine or batch',
            onSearchChanged: (value) => setState(() => _query = value),
            countLabel: 'Showing ${_filteredRows.length} batches',
            afterSearch: _loading
                ? const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                : null,
            beforeCount: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final d in [30, 60, 90])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('$d d'),
                        selected: _thresholdDays == d,
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        onSelected: (_) {
                          setState(() => _thresholdDays = d);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_filteredRows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_rounded,
                    size: 42,
                    color: cs.primary.withValues(alpha: 0.75),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No near-expiry batches',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (widget.onViewExpired != null)
                    FilledButton.tonal(
                      onPressed: widget.onViewExpired,
                      child: const Text('View expired'),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: pharmacyHubListPadding(context),
              child: Column(
                children: _filteredRows.map((r) {
                  final batch = r['medicine_batches'] as Map<String, dynamic>?;
                  final med = batch?['medicines'] as Map<String, dynamic>?;
                  final expDate = DateTime.tryParse(
                    '${batch?['expiry_date'] ?? ''}',
                  );
                  final daysLeft = expDate?.difference(DateTime.now()).inDays;
                  final isUrgent = (daysLeft ?? 999) <= 7;
                  final qty = (r['qty_base_unit'] as num?) ?? 0;
                  return PharmacyHubListRow(
                    icon: isUrgent
                        ? Icons.warning_amber_rounded
                        : Icons.schedule_rounded,
                    iconColor: isUrgent ? cs.error : null,
                    borderColor: isUrgent
                        ? cs.error.withValues(alpha: 0.45)
                        : null,
                    title: med?['name'] as String? ?? '',
                    subtitle:
                        'Batch ${batch?['batch_no'] ?? 'No batch'} · exp ${formatDdMmYyyy(batch?['expiry_date'])} · qty $qty',
                    trailing: Text(
                      daysLeft == null
                          ? '—'
                          : (daysLeft <= 0 ? 'Today' : '${daysLeft}d'),
                      style: context.layoutDensity
                          .listTitleStyle(Theme.of(context).textTheme)
                          ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isUrgent ? cs.error : cs.primary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
