import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/app_error_state.dart';

class StockMovementsPage extends ConsumerStatefulWidget {
  const StockMovementsPage({super.key});

  @override
  ConsumerState<StockMovementsPage> createState() => _StockMovementsPageState();
}

class _StockMovementsPageState extends ConsumerState<StockMovementsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final _typeCtl = TextEditingController();
  final _searchCtl = TextEditingController();
  final _df = DateFormat('yyyy-MM-dd');

  DateTime _from = DateTime.now().subtract(const Duration(days: 14));
  DateTime _to = DateTime.now();

  @override
  void dispose() {
    _typeCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
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
        _rows = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fromDt = DateTime(_from.year, _from.month, _from.day);
      final toExclusive = DateTime(_to.year, _to.month, _to.day).add(const Duration(days: 1));
      var q = Supabase.instance.client
          .from('stock_movements')
          .select(
            'created_at, movement_type, qty_change_base_unit, reason, reference_type, '
            'medicine_batches(batch_no, medicines(name))',
          )
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .gte('created_at', fromDt.toIso8601String())
          .lt('created_at', toExclusive.toIso8601String())
          .order('created_at', ascending: false)
          .limit(800);
      final data = await q;
      if (!mounted) return;
      setState(() => _rows = List<Map<String, dynamic>>.from(data as List));
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _rows;
    final t = _typeCtl.text.trim().toLowerCase();
    if (t.isNotEmpty) {
      list = list.where((r) => (r['movement_type'] as String? ?? '').toLowerCase().contains(t)).toList();
    }
    final s = _searchCtl.text.trim().toLowerCase();
    if (s.isEmpty) return list;
    return list.where((r) {
      final mb = r['medicine_batches'] as Map<String, dynamic>?;
      final med = mb?['medicines'] as Map<String, dynamic>?;
      final name = (med?['name'] as String? ?? '').toLowerCase();
      final batch = (mb?['batch_no'] as String? ?? '').toLowerCase();
      return name.contains(s) || batch.contains(s);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(selectedBranchIdProvider, (String? previous, String? next) => _load());
    return Scaffold(
      appBar: AppBar(title: const Text('Stock movements')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () async {
                    final a = await showDatePicker(
                      context: context,
                      initialDate: _from,
                      firstDate: DateTime(2020),
                      lastDate: _to,
                    );
                    if (a != null) setState(() => _from = a);
                  },
                  child: Text('From ${_df.format(_from)}'),
                ),
                TextButton(
                  onPressed: () async {
                    final a = await showDatePicker(
                      context: context,
                      initialDate: _to,
                      firstDate: _from,
                      lastDate: DateTime(2100),
                    );
                    if (a != null) setState(() => _to = a);
                  },
                  child: Text('To ${_df.format(_to)}'),
                ),
                FilledButton.tonal(onPressed: _load, child: const Text('Load')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtl,
                    decoration: const InputDecoration(
                      labelText: 'Medicine / batch',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _typeCtl,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      hintText: 'sale_out',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? AppErrorState(message: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? const Center(child: Text('No movements in range'))
                        : ListView.builder(
                            itemCount: _filtered.length,
                            itemBuilder: (context, i) {
                              final r = _filtered[i];
                              final mb = r['medicine_batches'] as Map<String, dynamic>?;
                              final med = mb?['medicines'] as Map<String, dynamic>?;
                              final name = med?['name'] as String? ?? '';
                              final batch = mb?['batch_no'] as String? ?? '';
                              final ts = r['created_at'] as String? ?? '';
                              return ListTile(
                                dense: true,
                                title: Text(name),
                                subtitle: Text(
                                  '${r['movement_type']} · $batch · $ts'
                                  '${r['reason'] != null ? '\n${r['reason']}' : ''}',
                                ),
                                trailing: Text('${r['qty_change_base_unit']}'),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
