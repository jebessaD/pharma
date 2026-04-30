import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

class StockMovementsPage extends ConsumerStatefulWidget {
  const StockMovementsPage({super.key});

  @override
  ConsumerState<StockMovementsPage> createState() => _StockMovementsPageState();
}

enum _StockDatePreset { today, last7, last14, last30, custom }

class _StockMovementsPageState extends ConsumerState<StockMovementsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final _typeCtl = TextEditingController();
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  final Set<String> _selectedCategoryIds = <String>{};

  DateTime _from = DateTime.now().subtract(const Duration(days: 14));
  DateTime _to = DateTime.now();
  _StockDatePreset _datePreset = _StockDatePreset.last14;

  void _runSoon([Duration delay = const Duration(milliseconds: 220)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      if (!mounted || _loading) return;
      _load();
    });
  }

  void _applyQuickRange(int days) {
    final today = DateTime.now();
    setState(() {
      _to = DateTime(today.year, today.month, today.day);
      _from = _to.subtract(Duration(days: days - 1));
    });
    _runSoon();
  }

  void _applyPreset(_StockDatePreset p) {
    _datePreset = p;
    switch (p) {
      case _StockDatePreset.today:
        _applyQuickRange(1);
      case _StockDatePreset.last7:
        _applyQuickRange(7);
      case _StockDatePreset.last14:
        _applyQuickRange(14);
      case _StockDatePreset.last30:
        _applyQuickRange(30);
      case _StockDatePreset.custom:
        break;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
      final toExclusive = DateTime(
        _to.year,
        _to.month,
        _to.day,
      ).add(const Duration(days: 1));
      var q = Supabase.instance.client
          .from('stock_movements')
          .select(
            'created_at, movement_type, qty_change_base_unit, reason, reference_type, '
            'medicine_batches(batch_no, medicines(name, category_id))',
          )
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .gte('created_at', fromDt.toIso8601String())
          .lt('created_at', toExclusive.toIso8601String());
      if (_selectedCategoryIds.isNotEmpty) {
        q = q.inFilter(
          'medicine_batches.medicines.category_id',
          _selectedCategoryIds.toList(growable: false),
        );
      }
      final data = await q.order('created_at', ascending: false).limit(800);
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
      list = list
          .where(
            (r) =>
                (r['movement_type'] as String? ?? '').toLowerCase().contains(t),
          )
          .toList();
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
    ref.listen<String?>(
      selectedBranchIdProvider,
      (String? previous, String? next) => _load(),
    );
    final categoriesAsync = ref.watch(activeBranchMedicineCategoriesProvider);
    final categoryOptions =
        categoriesAsync.value
            ?.map((row) {
              final id = (row['id'] as String? ?? '').trim();
              final name = (row['name'] as String? ?? '').trim();
              if (id.isEmpty || name.isEmpty) return null;
              return {'id': id, 'name': name};
            })
            .whereType<Map<String, String>>()
            .toList() ??
        const <Map<String, String>>[];
    return Scaffold(
      appBar: pharmacyHubAppBar(context, title: 'Stock history'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<_StockDatePreset>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: _StockDatePreset.today,
                          label: Text('Today'),
                        ),
                        ButtonSegment(
                          value: _StockDatePreset.last7,
                          label: Text('7d'),
                        ),
                        ButtonSegment(
                          value: _StockDatePreset.last14,
                          label: Text('14d'),
                        ),
                        ButtonSegment(
                          value: _StockDatePreset.last30,
                          label: Text('30d'),
                        ),
                        ButtonSegment(
                          value: _StockDatePreset.custom,
                          label: Text('Custom'),
                        ),
                      ],
                      selected: {_datePreset},
                      onSelectionChanged: (next) {
                        _applyPreset(next.first);
                      },
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDateRange: DateTimeRange(
                            start: _from,
                            end: _to,
                          ),
                        );
                        if (picked == null) return;
                        setState(() {
                          _datePreset = _StockDatePreset.custom;
                          _from = DateTime(
                            picked.start.year,
                            picked.start.month,
                            picked.start.day,
                          );
                          _to = DateTime(
                            picked.end.year,
                            picked.end.month,
                            picked.end.day,
                          );
                        });
                        _runSoon();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Text(
                          'Date range: ${formatDdMmYyyy(_from)} → ${formatDdMmYyyy(_to)}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (categoryOptions.isNotEmpty) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Categories'),
                        subtitle: Text(
                          _selectedCategoryIds.isEmpty
                              ? 'All categories'
                              : '${_selectedCategoryIds.length} selected',
                        ),
                        trailing: const Icon(Icons.checklist_rounded),
                        onTap: () async {
                          final selected = await _pickCategoryIds(
                            categoryOptions,
                            _selectedCategoryIds,
                          );
                          if (selected == null) return;
                          setState(() {
                            _selectedCategoryIds
                              ..clear()
                              ..addAll(selected);
                          });
                          _runSoon();
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtl,
                            decoration: const InputDecoration(
                              labelText: 'Medicine / batch',
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 130,
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
                  ],
                ),
              ),
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
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final r = _filtered[i];
                      final mb = r['medicine_batches'] as Map<String, dynamic>?;
                      final med = mb?['medicines'] as Map<String, dynamic>?;
                      final name = med?['name'] as String? ?? '';
                      final batch = mb?['batch_no'] as String? ?? '';
                      final ts = formatDdMmYyyyHm(r['created_at']);
                      final qty = '${r['qty_change_base_unit']}';
                      final isOut = qty.startsWith('-');
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          title: Text(name),
                          subtitle: Text(
                            '${r['movement_type']} · $batch · $ts'
                            '${r['reason'] != null ? '\n${r['reason']}' : ''}',
                          ),
                          trailing: Text(
                            qty,
                            style: TextStyle(
                              color: isOut
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<Set<String>?> _pickCategoryIds(
    List<Map<String, String>> options,
    Set<String> selected,
  ) async {
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final temp = Set<String>.from(selected);
        return StatefulBuilder(
          builder: (context, setModalState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Select categories'),
                  trailing: TextButton(
                    onPressed: () => setModalState(temp.clear),
                    child: const Text('Clear'),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final option in options)
                        CheckboxListTile(
                          value: temp.contains(option['id']),
                          title: Text(option['name'] ?? ''),
                          onChanged: (checked) {
                            setModalState(() {
                              final id = option['id'];
                              if (id == null) return;
                              if (checked == true) {
                                temp.add(id);
                              } else {
                                temp.remove(id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, temp),
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
