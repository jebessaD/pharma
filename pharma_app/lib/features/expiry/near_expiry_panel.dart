import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';

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
      final med = r['medicines'] as Map<String, dynamic>?;
      return (med?['name'] as String? ?? '').toLowerCase().contains(
            _query.trim().toLowerCase(),
          ) ||
          ('${r['batch_no'] ?? ''}').toLowerCase().contains(
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
      final data = await Supabase.instance.client
          .from('medicine_batches')
          .select(
            'batch_no, expiry_date, quantity_in_base_unit, medicines(name)',
          )
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .gte('expiry_date', today.toIso8601String().split('T').first)
          .lte('expiry_date', end.toIso8601String().split('T').first)
          .order('expiry_date');
      setState(() => _rows = List<Map<String, dynamic>>.from(data as List));
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
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
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 10),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [30, 60, 90]
                        .map(
                          (d) => ChoiceChip(
                            label: Text('$d days'),
                            selected: _thresholdDays == d,
                            onSelected: (_) {
                              setState(() => _thresholdDays = d);
                              _load();
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search medicine or batch',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatChip(
                        icon: Icons.inventory_2_rounded,
                        label: 'Found',
                        value: '${_filteredRows.length}',
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.priority_high_rounded,
                        label: '<= 7d',
                        value:
                            '${_filteredRows.where((r) => ((DateTime.tryParse('${r['expiry_date'] ?? ''}')?.difference(DateTime.now()).inDays ?? 999) <= 7)).length}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
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
                  Text('No near-expiry batches', style: t.textTheme.titleMedium),
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
            ..._filteredRows.map((r) {
              final med = r['medicines'] as Map<String, dynamic>?;
              final expDate = DateTime.tryParse('${r['expiry_date'] ?? ''}');
              final daysLeft = expDate?.difference(DateTime.now()).inDays;
              final isUrgent = (daysLeft ?? 999) <= 7;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isUrgent
                            ? cs.error.withValues(alpha: 0.45)
                            : cs.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 17,
                        backgroundColor:
                            (isUrgent ? cs.errorContainer : cs.primaryContainer)
                                .withValues(alpha: 0.8),
                        child: Icon(
                          isUrgent
                              ? Icons.warning_amber_rounded
                              : Icons.schedule_rounded,
                          color: isUrgent
                              ? cs.onErrorContainer
                              : cs.onPrimaryContainer,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        med?['name'] as String? ?? '',
                        style: t.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Batch ${r['batch_no']} · exp ${formatDdMmYyyy(r['expiry_date'])}',
                      ),
                      trailing: Text(
                        daysLeft == null
                            ? '—'
                            : (daysLeft <= 0 ? 'Today' : '${daysLeft}d'),
                        style: t.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isUrgent ? cs.error : cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text('$label: ', style: t.textTheme.labelMedium),
          Text(
            value,
            style: t.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
