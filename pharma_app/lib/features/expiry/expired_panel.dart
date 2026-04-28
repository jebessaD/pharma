import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
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
            const Text('No expired batches'),
            const SizedBox(height: 8),
            if (widget.onViewNear != null)
              FilledButton(
                onPressed: widget.onViewNear,
                child: const Text('View near expiry'),
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
            child: TextField(
              decoration: const InputDecoration(labelText: 'Search'),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredRows.length,
              itemBuilder: (context, i) {
                final r = _filteredRows[i];
                final med = r['medicines'] as Map<String, dynamic>?;
                return ListTile(
                  title: Text(med?['name'] as String? ?? ''),
                  subtitle: Text(
                    'Batch ${r['batch_no']} · exp ${r['expiry_date']}',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
