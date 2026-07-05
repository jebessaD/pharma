import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../../core/forms/form_error_mapper.dart';
import '../../core/layout/layout_density.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/pharmacy_hub_list.dart';
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
  final _searchCtl = TextEditingController();
  /// `null` = all movement types (matches DB `stock_movements.movement_type`).
  String? _selectedMovementType;
  Timer? _debounce;
  final Set<String> _selectedCategoryKeys = <String>{};

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
    _searchCtl.dispose();
    super.dispose();
  }

  static String _movementTypeLabel(String? raw) {
    switch (raw) {
      case 'purchase_in':
        return 'Stock in';
      case 'sale_out':
        return 'Sale';
      case 'adjustment':
        return 'Adjustment';
      case null:
      case '':
        return '—';
      default:
        final s = raw.replaceAll('_', ' ').trim();
        if (s.isEmpty) return raw;
        return '${s[0].toUpperCase()}${s.length > 1 ? s.substring(1) : ''}';
    }
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
            'medicine_batches(batch_no, medicines(name, category_key))',
          )
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .gte('created_at', fromDt.toIso8601String())
          .lt('created_at', toExclusive.toIso8601String());
      if (_selectedCategoryKeys.isNotEmpty) {
        q = q.inFilter(
          'medicine_batches.medicines.category_key',
          _selectedCategoryKeys.toList(growable: false),
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
    if (_selectedMovementType != null) {
      list = list
          .where((r) => r['movement_type'] == _selectedMovementType)
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
    final density = context.layoutDensity;
    final compact = density.isCompact;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: HubPageHeader(title: 'Stock history'),
          ),
          Expanded(
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: pharmacyHubFilterPadding(context).copyWith(top: 0, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PharmacyHubSearchField(
                  controller: _searchCtl,
                  hintText: 'Medicine or batch',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final preset in _StockDatePreset.values)
                        if (preset != _StockDatePreset.custom)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(switch (preset) {
                                _StockDatePreset.today => 'Today',
                                _StockDatePreset.last7 => '7d',
                                _StockDatePreset.last14 => '14d',
                                _StockDatePreset.last30 => '30d',
                                _StockDatePreset.custom => 'Custom',
                              }),
                              selected: _datePreset == preset,
                              visualDensity: VisualDensity.compact,
                              showCheckmark: false,
                              onSelected: (_) => _applyPreset(preset),
                            ),
                          ),
                      FilterChip(
                        label: const Text('Custom'),
                        selected: _datePreset == _StockDatePreset.custom,
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        onSelected: (_) async {
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
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 4 : 6),
                Text(
                  '${formatDdMmYyyy(_from)} – ${formatDdMmYyyy(_to)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: compact ? 6 : 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _selectedMovementType == null,
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        onSelected: (_) =>
                            setState(() => _selectedMovementType = null),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('In'),
                        selected: _selectedMovementType == 'purchase_in',
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        onSelected: (_) => setState(
                          () => _selectedMovementType = 'purchase_in',
                        ),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('Sale'),
                        selected: _selectedMovementType == 'sale_out',
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        onSelected: (_) =>
                            setState(() => _selectedMovementType = 'sale_out'),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('Adj'),
                        selected: _selectedMovementType == 'adjustment',
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        onSelected: (_) => setState(
                          () => _selectedMovementType = 'adjustment',
                        ),
                      ),
                      if (categoryOptions.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        FilterChip(
                          label: Text(
                            _selectedCategoryKeys.isEmpty
                                ? 'Category'
                                : '${_selectedCategoryKeys.length} cat.',
                          ),
                          visualDensity: VisualDensity.compact,
                          showCheckmark: false,
                          onSelected: (_) async {
                            final selected = await _pickCategoryIds(
                              categoryOptions,
                              _selectedCategoryKeys,
                            );
                            if (selected == null) return;
                            setState(() {
                              _selectedCategoryKeys
                                ..clear()
                                ..addAll(selected);
                            });
                            _runSoon();
                          },
                        ),
                      ],
                    ],
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
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final r = _filtered[i];
                      final t = Theme.of(context);
                      final mb = r['medicine_batches'] as Map<String, dynamic>?;
                      final med = mb?['medicines'] as Map<String, dynamic>?;
                      final name = med?['name'] as String? ?? '';
                      final batch = mb?['batch_no'] as String? ?? '';
                      final ts = formatDdMmYyyyHm(r['created_at']);
                      final qty = '${r['qty_change_base_unit']}';
                      final isOut = qty.startsWith('-');
                      final cs = Theme.of(context).colorScheme;
                      final accent = isOut ? cs.error : const Color(0xFF15803D);
                      return Container(
                        margin: EdgeInsets.only(bottom: compact ? 4 : 6),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(compact ? 8 : 10),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(compact ? 8 : 10),
                            border: Border(
                              left: BorderSide(color: accent, width: compact ? 2 : 3),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: compact ? 10 : 12,
                              vertical: compact ? 0 : 2,
                            ),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: compact ? 13 : null,
                              ),
                            ),
                            subtitle: Text(
                              compact
                                  ? '${_movementTypeLabel(r['movement_type'] as String?)} · $batch'
                                  : '${_movementTypeLabel(r['movement_type'] as String?)} · '
                                        '$batch · $ts'
                                        '${r['reason'] != null ? '\n${r['reason']}' : ''}',
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: compact
                                  ? t.textTheme.labelSmall
                                  : null,
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  qty,
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: compact ? 13 : null,
                                  ),
                                ),
                                if (compact)
                                  Text(
                                    ts.split(' ').first,
                                    style: t.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
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
                    onPressed: () => setModalState(() => temp.clear()),
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
