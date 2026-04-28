import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
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
      title: 'Stock',
      subtitle: 'Balances and reorder signals',
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV copied to clipboard')),
      );
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
          .select('qty_base_unit, medicine_batches(batch_no, expiry_date, medicines(name))')
          .eq('team_id', teamId)
          .eq('branch_id', branchId);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('CSV'),
              ),
              TextButton.icon(
                onPressed: widget.onOpenLowStockTab,
                icon: const Icon(Icons.warning_amber_outlined, size: 18),
                label: const Text('Low stock'),
              ),
              TextButton.icon(
                onPressed: () => context.push('/pharmacy/stock-movements'),
                icon: const Icon(Icons.swap_vert_rounded, size: 18),
                label: const Text('Movements'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await context.push('/pharmacy/stock-in');
                  if (mounted) _load();
                },
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: const Text('Stock in'),
              ),
              TextButton.icon(
                onPressed: () => context.push('/pharmacy/stock-in?tab=bulk'),
                icon: const Icon(Icons.playlist_add_outlined, size: 18),
                label: const Text('Many lines'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await context.push('/pharmacy/adjust-stock');
                  if (mounted) _load();
                },
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Adjust'),
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
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        decoration: const InputDecoration(
                                          labelText: 'Search medicine/batch',
                                        ),
                                        onChanged: (value) => setState(() => _query = value),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () => setState(() => _sortByQtyDesc = !_sortByQtyDesc),
                                      child: Text(_sortByQtyDesc ? 'Qty desc' : 'Qty asc'),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _displayRows.length,
                                  itemBuilder: (context, i) {
                                    final r = _displayRows[i];
                                    final qty = r['qty_base_unit'];
                                    final mb = r['medicine_batches'] as Map<String, dynamic>?;
                                    final med = mb?['medicines'] as Map<String, dynamic>?;
                                    final name = med?['name'] as String? ?? '';
                                    final batch = mb?['batch_no'] as String? ?? '';
                                    final exp = mb?['expiry_date'] as String? ?? '';
                                    return ListTile(
                                      title: Text(name),
                                      subtitle: Text('Batch $batch · exp $exp'),
                                      trailing: Text('$qty'),
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
      final low = raw.where((r) {
        final mb = r['medicine_batches'] as Map<String, dynamic>?;
        final med = mb?['medicines'] as Map<String, dynamic>?;
        final reorder = (med?['reorder_level'] as num?) ?? 0;
        final qty = (r['qty_base_unit'] as num?) ?? 0;
        return qty <= reorder;
      }).toList()
        ..sort((a, b) {
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
    ref.listen<String?>(selectedBranchIdProvider, (String? previous, String? next) => _load());
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
                  subtitle: Text('Batch $batch · exp $exp · reorder ≤ $reorder'),
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
