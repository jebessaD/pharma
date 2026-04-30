import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';

class ExpiredPanel extends ConsumerStatefulWidget {
  const ExpiredPanel({super.key, this.onViewNear});

  final VoidCallback? onViewNear;

  @override
  ConsumerState<ExpiredPanel> createState() => _ExpiredPanelState();
}

class _ExpiredPanelState extends ConsumerState<ExpiredPanel> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
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
      final today = DateTime.now().toUtc().toIso8601String().split('T').first;
      final data = await Supabase.instance.client
          .from('medicine_batches')
          .select('batch_no, expiry_date, medicines(name)')
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .lt('expiry_date', today)
          .order('expiry_date', ascending: false);
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
                Icons.verified_rounded,
                size: 42,
                color: cs.primary.withValues(alpha: 0.75),
              ),
              const SizedBox(height: 8),
              Text('No expired batches', style: t.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (widget.onViewNear != null)
                FilledButton.tonal(
                  onPressed: widget.onViewNear,
                  child: const Text('View near expiry'),
                ),
            ],
          ),
        ),
      );
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
                      _ExpiredStatChip(
                        icon: Icons.event_busy_rounded,
                        label: 'Expired',
                        value: '${_filteredRows.length}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          ..._filteredRows.map((r) {
            final med = r['medicines'] as Map<String, dynamic>?;
            final expDate = DateTime.tryParse('${r['expiry_date'] ?? ''}');
            final daysOver = expDate == null
                ? null
                : DateTime.now().difference(expDate).inDays;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.error.withValues(alpha: 0.45)),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 17,
                      backgroundColor: cs.errorContainer.withValues(alpha: 0.8),
                      child: Icon(
                        Icons.dangerous_rounded,
                        color: cs.onErrorContainer,
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
                      daysOver == null ? 'Expired' : '${daysOver}d ago',
                      style: t.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.error,
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

class _ExpiredStatChip extends StatelessWidget {
  const _ExpiredStatChip({
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
          Icon(icon, size: 16, color: cs.error),
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
