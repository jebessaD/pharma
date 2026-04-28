import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
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
      return (med?['name'] as String? ?? '').toLowerCase().contains(_query.trim().toLowerCase()) ||
          ('${r['batch_no'] ?? ''}').toLowerCase().contains(_query.trim().toLowerCase());
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
          .select('batch_no, expiry_date, quantity_in_base_unit, medicines(name)')
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
    ref.listen(selectedBranchIdProvider, (previous, next) => _load());
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return AppErrorState(
        message: _error!,
        onRetry: _load,
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No near-expiry batches'),
            const SizedBox(height: 8),
            if (widget.onViewExpired != null)
              FilledButton(
                onPressed: widget.onViewExpired,
                child: const Text('View expired'),
              ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                DropdownButton<int>(
                  value: _thresholdDays,
                  items: const [30, 60, 90]
                      .map((d) => DropdownMenuItem(value: d, child: Text('$d days')))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _thresholdDays = value);
                    _load();
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Search'),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredRows.length,
              itemBuilder: (context, i) {
                final r = _filteredRows[i];
                final med = r['medicines'] as Map<String, dynamic>?;
                final expDate = DateTime.tryParse('${r['expiry_date'] ?? ''}');
                final daysLeft = expDate?.difference(DateTime.now()).inDays;
                return ListTile(
                  leading: Icon(
                    (daysLeft ?? 999) <= 7 ? Icons.warning_amber_outlined : Icons.schedule_outlined,
                  ),
                  title: Text(med?['name'] as String? ?? ''),
                  subtitle: Text(
                    'Batch ${r['batch_no']} · exp ${r['expiry_date']}',
                  ),
                  trailing: daysLeft == null ? null : Text(daysLeft <= 0 ? 'Today' : '${daysLeft}d'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
