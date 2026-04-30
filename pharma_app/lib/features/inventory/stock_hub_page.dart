import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/pharmacy_hub_scaffold.dart';

enum StockHubTab { balances, low }

/// `/pharmacy/stock?tab=balances|low` (default balances). Legacy `/pharmacy/low-stock` redirects here.
class StockHubPage extends ConsumerStatefulWidget {
  const StockHubPage({super.key, required this.initialTab});

  final StockHubTab initialTab;

  @override
  ConsumerState<StockHubPage> createState() => _StockHubPageState();
}

class _StockHubPageState extends ConsumerState<StockHubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == StockHubTab.low ? 1 : 0,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final tab = _tabController.index == 0 ? 'balances' : 'low';
    final loc = GoRouterState.of(context).uri;
    if (loc.queryParameters['tab'] != tab) {
      context.go('/pharmacy/stock?tab=$tab');
    }
  }

  @override
  void didUpdateWidget(StockHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      final idx = widget.initialTab == StockHubTab.low ? 1 : 0;
      if (_tabController.index != idx) {
        _tabController.animateTo(idx);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PharmacyHubScaffold(
      title: '',
      subtitle: null,
      tabController: _tabController,
      tabs: const [
        Tab(text: 'Balances', icon: Icon(Icons.inventory_2_rounded)),
        Tab(text: 'Low stock', icon: Icon(Icons.warning_amber_rounded)),
      ],
      tabBarViewChildren: [
        _StockBalancePanel(
          onOpenLowStockTab: () {
            _tabController.animateTo(1);
            context.go('/pharmacy/stock?tab=low');
          },
        ),
        const _LowStockPanel(),
      ],
    );
  }
}

class _StockBalancePanel extends ConsumerStatefulWidget {
  const _StockBalancePanel({required this.onOpenLowStockTab});

  final VoidCallback onOpenLowStockTab;

  @override
  ConsumerState<_StockBalancePanel> createState() => _StockBalancePanelState();
}

class _StockBalancePanelState extends ConsumerState<_StockBalancePanel> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _query = '';
  bool _sortByQtyDesc = true;
  bool _isNavigating = false;
  final Set<String> _categoryFilterIds = <String>{};
  String? _adjustingBatchId;

  List<Map<String, dynamic>> get _displayRows {
    var rows = List<Map<String, dynamic>>.from(_rows);
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      rows = rows.where((r) {
        final mb = r['medicine_batches'] as Map<String, dynamic>?;
        final med = mb?['medicines'] as Map<String, dynamic>?;
        final name = (med?['name'] as String? ?? '').toLowerCase();
        final batch = (mb?['batch_no'] as String? ?? '').toLowerCase();
        return name.contains(q) || batch.contains(q);
      }).toList();
    }
    if (_categoryFilterIds.isNotEmpty) {
      rows = rows.where((r) {
        final mb = r['medicine_batches'] as Map<String, dynamic>?;
        final med = mb?['medicines'] as Map<String, dynamic>?;
        final categoryId = (med?['category_id'] as String? ?? '').trim();
        return _categoryFilterIds.contains(categoryId);
      }).toList();
    }
    rows.sort((a, b) {
      final av = (a['qty_base_unit'] as num? ?? 0).toDouble();
      final bv = (b['qty_base_unit'] as num? ?? 0).toDouble();
      return _sortByQtyDesc ? bv.compareTo(av) : av.compareTo(bv);
    });
    return rows;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _exportCsv() async {
    if (_displayRows.isEmpty) return;
    final lines = <String>['medicine,batch,expiry,qty'];
    for (final r in _displayRows) {
      final mb = r['medicine_batches'] as Map<String, dynamic>?;
      final med = mb?['medicines'] as Map<String, dynamic>?;
      lines.add(
        '${med?['name'] ?? ''},${mb?['batch_no'] ?? ''},${mb?['expiry_date'] ?? ''},${r['qty_base_unit'] ?? 0}',
      );
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard')));
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
      final data = await Supabase.instance.client
          .from('stock_balances')
          .select(
            'qty_base_unit, medicine_batches(id, batch_no, expiry_date, medicines(name, category_id, medicine_categories(name)))',
          )
          .eq('team_id', teamId)
          .eq('branch_id', branchId);
      setState(() => _rows = List<Map<String, dynamic>>.from(data as List));
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openQuickAdjust(Map<String, dynamic> row) async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a branch first.')));
      return;
    }
    final mb = row['medicine_batches'] as Map<String, dynamic>?;
    final batchId = mb?['id'] as String?;
    if (batchId == null || batchId.isEmpty) return;
    final medicineName = ((mb?['medicines'] as Map<String, dynamic>?)?['name']
            as String?) ??
        'Medicine';
    final batchNo = (mb?['batch_no'] as String?) ?? '';
    final qtyOnHand = (row['qty_base_unit'] as num?) ?? 0;
    final payload = await showDialog<({bool isReduce, num qty, String reason})>(
      context: context,
      builder: (ctx) {
        final qtyCtl = TextEditingController();
        final reasonCtl = TextEditingController();
        final formKey = GlobalKey<FormState>();
        var isReduce = false;
        return StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: const Text('Adjust stock'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    medicineName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Batch ${batchNo.isEmpty ? "—" : batchNo} · on hand $qtyOnHand',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment<bool>(value: false, label: Text('Add')),
                      ButtonSegment<bool>(value: true, label: Text('Reduce')),
                    ],
                    selected: {isReduce},
                    onSelectionChanged: (next) {
                      setLocalState(() => isReduce = next.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: qtyCtl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}$'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      hintText: 'Enter amount',
                    ),
                    validator: (value) {
                      final qty = num.tryParse((value ?? '').trim());
                      if (qty == null || qty <= 0) {
                        return 'Enter quantity greater than 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: reasonCtl,
                    decoration: InputDecoration(
                      labelText: 'Reason',
                      hintText: isReduce
                          ? 'e.g. damaged, correction'
                          : 'e.g. restock, correction',
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Enter reason'
                        : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  final qty = num.parse(qtyCtl.text.trim());
                  Navigator.pop(
                    ctx,
                    (
                      isReduce: isReduce,
                      qty: qty,
                      reason: reasonCtl.text.trim(),
                    ),
                  );
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || payload == null) return;
    setState(() => _adjustingBatchId = batchId);
    try {
      await Supabase.instance.client.rpc(
        'apply_stock_movement',
        params: {
          'p_team_id': teamId,
          'p_branch_id': branchId,
          'p_batch_id': batchId,
          'p_type': 'adjustment',
          'p_qty': payload.isReduce ? -payload.qty : payload.qty,
          'p_reason': payload.reason,
          'p_ref_type': 'adjustment',
          'p_ref_id': null,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            payload.isReduce
                ? 'Reduced stock by ${payload.qty}.'
                : 'Added stock by ${payload.qty}.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    } finally {
      if (mounted) {
        setState(() => _adjustingBatchId = null);
      }
    }
  }

  Future<void> _safePush(String route, {bool reloadAfter = false}) async {
    if (_isNavigating || !mounted) return;
    setState(() => _isNavigating = true);
    try {
      await context.push(route);
      if (reloadAfter && mounted) {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedBranchIdProvider, (previous, next) => _load());
    final cs = Theme.of(context).colorScheme;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _isNavigating
                    ? null
                    : () => _safePush('/pharmacy/stock-in', reloadAfter: true),
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: const Text('Stock in'),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (value) async {
                  switch (value) {
                    case 'many_lines':
                      await _safePush('/pharmacy/stock-in?tab=bulk');
                    case 'history':
                      await _safePush('/pharmacy/stock-movements');
                    case 'csv':
                      await _exportCsv();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'many_lines',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.playlist_add_outlined),
                      title: Text('Many lines'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'history',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.swap_vert_rounded),
                      title: Text('Stock history'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'csv',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.download_outlined),
                      title: Text('CSV'),
                    ),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.more_horiz_rounded),
                      SizedBox(width: 2),
                      Text('More'),
                    ],
                  ),
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
              : _rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No stock rows yet'),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () async {
                          await context.push('/pharmacy/stock-in');
                          if (mounted) _load();
                        },
                        child: const Text('Add stock'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  decoration: InputDecoration(
                                    hintText: 'Search medicine or batch',
                                    prefixIcon: const Icon(Icons.search_rounded),
                                    filled: true,
                                    fillColor: cs.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: cs.outlineVariant),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: cs.outlineVariant),
                                    ),
                                  ),
                                  onChanged: (value) => setState(() => _query = value),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Showing ${_displayRows.length} rows',
                                        style: Theme.of(context).textTheme.bodySmall
                                            ?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                    ActionChip(
                                      label: Text(
                                        _sortByQtyDesc
                                            ? 'Qty: high to low'
                                            : 'Qty: low to high',
                                      ),
                                      avatar: Icon(
                                        _sortByQtyDesc
                                            ? Icons.arrow_downward_rounded
                                            : Icons.arrow_upward_rounded,
                                        size: 16,
                                      ),
                                      onPressed: () => setState(
                                        () => _sortByQtyDesc = !_sortByQtyDesc,
                                      ),
                                    ),
                                  ],
                                ),
                                if (categoryOptions.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Categories'),
                                    subtitle: Text(
                                      _categoryFilterIds.isEmpty
                                          ? 'All categories'
                                          : '${_categoryFilterIds.length} selected',
                                    ),
                                    trailing: const Icon(Icons.checklist_rounded),
                                    onTap: () async {
                                      final selected = await _pickCategoryIds(
                                        categoryOptions,
                                        _categoryFilterIds,
                                      );
                                      if (selected == null) return;
                                      setState(() {
                                        _categoryFilterIds
                                          ..clear()
                                          ..addAll(selected);
                                      });
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: _displayRows.length,
                          itemBuilder: (context, i) {
                            final r = _displayRows[i];
                            final qty = r['qty_base_unit'];
                            final mb =
                                r['medicine_batches'] as Map<String, dynamic>?;
                            final med =
                                mb?['medicines'] as Map<String, dynamic>?;
                            final name = med?['name'] as String? ?? '';
                            final batch = mb?['batch_no'] as String? ?? '';
                            final exp = mb?['expiry_date'] as String? ?? '';
                            final batchId = mb?['id'] as String?;
                            final busy = batchId != null && _adjustingBatchId == batchId;
                            return Column(
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  title: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    'Batch ${batch.isEmpty ? "—" : batch} · exp ${formatDdMmYyyy(exp)}',
                                  ),
                                  trailing: Text(
                                    busy ? '...' : '$qty',
                                    style: TextStyle(
                                      color: busy ? cs.onSurfaceVariant : cs.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onTap: busy ? null : () => _openQuickAdjust(r),
                                ),
                                Divider(
                                  height: 1,
                                  color: cs.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
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

class _LowStockPanel extends ConsumerStatefulWidget {
  const _LowStockPanel();

  @override
  ConsumerState<_LowStockPanel> createState() => _LowStockPanelState();
}

class _LowStockPanelState extends ConsumerState<_LowStockPanel> {
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
      final data = await Supabase.instance.client
          .from('stock_balances')
          .select(
            'qty_base_unit, medicine_batches(batch_no, expiry_date, medicines(name, reorder_level))',
          )
          .eq('team_id', teamId)
          .eq('branch_id', branchId);
      if (!mounted) return;
      final raw = List<Map<String, dynamic>>.from(data as List);
      final low =
          raw.where((r) {
            final mb = r['medicine_batches'] as Map<String, dynamic>?;
            final med = mb?['medicines'] as Map<String, dynamic>?;
            final reorder = (med?['reorder_level'] as num?) ?? 0;
            final qty = (r['qty_base_unit'] as num?) ?? 0;
            return qty <= reorder;
          }).toList()..sort((a, b) {
            final qa = (a['qty_base_unit'] as num? ?? 0).toDouble();
            final qb = (b['qty_base_unit'] as num? ?? 0).toDouble();
            return qa.compareTo(qb);
          });
      setState(() => _rows = low);
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      selectedBranchIdProvider,
      (String? previous, String? next) => _load(),
    );
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('No batches at or below reorder level'));
    }
    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final r = _rows[i];
                final mb = r['medicine_batches'] as Map<String, dynamic>?;
                final med = mb?['medicines'] as Map<String, dynamic>?;
                final name = med?['name'] as String? ?? '';
                final reorder = med?['reorder_level'];
                final batch = mb?['batch_no'] as String? ?? '';
                final exp = mb?['expiry_date'] as String? ?? '';
                final qty = r['qty_base_unit'];
                return ListTile(
                  title: Text(name),
                  subtitle: Text(
                    'Batch $batch · exp ${formatDdMmYyyy(exp)} · reorder ≤ $reorder',
                  ),
                  trailing: Text('$qty'),
                  onTap: () => context.push('/pharmacy/stock-in'),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
