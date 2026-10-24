import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/medicine/medicine_display.dart';
import '../../core/layout/layout_density.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/roles/stock_permissions.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/pharmacy_hub_list.dart';

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
    final role =
        ref.watch(pharmacyProfileProvider).asData?.value?['role'] as String?;
    final canAddStockIn = canAddStockInForRole(role);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: canAddStockIn
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/pharmacy/stock-in'),
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Stock in'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Balances'),
                    Tab(text: 'Low stock'),
                  ],
                  dividerColor: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              IconButton(
                tooltip: 'Stock history',
                onPressed: () => context.push('/pharmacy/stock-movements'),
                icon: const Icon(Icons.history_rounded),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _StockBalancePanel(),
                _LowStockPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockBalancePanel extends ConsumerStatefulWidget {
  const _StockBalancePanel();

  @override
  ConsumerState<_StockBalancePanel> createState() => _StockBalancePanelState();
}

class _StockBalancePanelState extends ConsumerState<_StockBalancePanel> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _query = '';
  bool _sortByQtyDesc = true;
  final Set<String> _categoryFilterKeys = <String>{};

  List<Map<String, dynamic>> get _displayRows {
    var rows = List<Map<String, dynamic>>.from(_rows);
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      rows = rows.where((r) {
        final mb = r['medicine_batches'] as Map<String, dynamic>?;
        final med = mb?['medicines'] as Map<String, dynamic>?;
        final medMap = med ?? const <String, dynamic>{};
        final haystack =
            '${medicinePrimaryLabel(medMap)} ${medicineBrandName(medMap)} ${medicineGenericName(medMap)}'
                .toLowerCase();
        final batch = (mb?['batch_no'] as String? ?? '').toLowerCase();
        return haystack.contains(q) || batch.contains(q);
      }).toList();
    }
    if (_categoryFilterKeys.isNotEmpty) {
      rows = rows.where((r) {
        final mb = r['medicine_batches'] as Map<String, dynamic>?;
        final med = mb?['medicines'] as Map<String, dynamic>?;
        final categoryKey = (med?['category_key'] as String? ?? '').trim();
        return _categoryFilterKeys.contains(categoryKey);
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
            'qty_base_unit, medicine_batches(id, batch_no, expiry_date, medicines(id, name, generic_name, category_key))',
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

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedBranchIdProvider, (previous, next) => _load());
    final role =
        ref.watch(pharmacyProfileProvider).asData?.value?['role'] as String?;
    final canAddStockIn = canAddStockInForRole(role);
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
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? AppErrorState(message: _error!, onRetry: _load)
        : RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: PharmacyHubFilterSection(
                    searchHint: 'Search medicine or batch',
                    onSearchChanged: (value) => setState(() => _query = value),
                    countLabel:
                        'Showing ${_displayRows.length} of ${_rows.length} batches',
                    sortDescending: _sortByQtyDesc,
                    onToggleSort: () =>
                        setState(() => _sortByQtyDesc = !_sortByQtyDesc),
                    categorySelectedCount: categoryOptions.isEmpty
                        ? null
                        : _categoryFilterKeys.length,
                    onPickCategories: categoryOptions.isEmpty
                        ? null
                        : () async {
                            final selected = await _pickCategoryIds(
                              categoryOptions,
                              _categoryFilterKeys,
                            );
                            if (selected == null) return;
                            setState(() {
                              _categoryFilterKeys
                                ..clear()
                                ..addAll(selected);
                            });
                          },
                  ),
                ),
                if (_rows.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _StockHubEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No stock yet',
                      message: canAddStockIn
                          ? 'Receive inventory with stock in.'
                          : 'Ask a team owner or admin to receive inventory.',
                      actionLabel: canAddStockIn ? 'Stock in' : null,
                      onAction: canAddStockIn
                          ? () async {
                              await context.push('/pharmacy/stock-in');
                              if (mounted) _load();
                            }
                          : null,
                    ),
                  )
                else if (_displayRows.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _StockHubEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches',
                      message: 'Try a different search or category filter.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: pharmacyHubListPadding(context, bottom: 88),
                    sliver: SliverList.builder(
                      itemCount: _displayRows.length,
                      itemBuilder: (context, i) {
                        final r = _displayRows[i];
                        final qty = r['qty_base_unit'];
                        final mb =
                            r['medicine_batches'] as Map<String, dynamic>?;
                        final med = mb?['medicines'] as Map<String, dynamic>?;
                        final medMap = med ?? const <String, dynamic>{};
                        final primary = medicinePrimaryLabel(medMap);
                        final brand = medicineSecondaryLabel(medMap);
                        final batch = mb?['batch_no'] as String? ?? '';
                        final exp = mb?['expiry_date'] as String? ?? '';
                        final medicineId = med?['id'] as String?;
                        return PharmacyHubListRow(
                          icon: _stockExpiryIsNear(exp)
                              ? Icons.schedule_rounded
                              : Icons.inventory_2_outlined,
                          borderColor: _stockExpiryIsNear(exp)
                              ? Theme.of(context).colorScheme.tertiary
                                  .withValues(alpha: 0.5)
                              : null,
                          title: primary,
                          subtitle: [
                            if (brand != null) brand,
                            'Batch ${batch.isEmpty ? "—" : batch} · exp ${formatDdMmYyyy(exp)}',
                          ].join(' · '),
                          onTap: medicineId != null
                              ? () =>
                                    context.push('/pharmacy/medicines/$medicineId')
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$qty',
                                style: context.layoutDensity
                                    .listTitleStyle(Theme.of(context).textTheme)
                                    ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: context.layoutDensity.listIconSize,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ],
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
    return showPharmacyCategoryFilterSheet(
      context,
      selected: selected,
      categories: options
          .map((o) => {'id': o['id'], 'name': o['name']})
          .toList(),
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
  String _query = '';

  List<Map<String, dynamic>> get _displayRows {
    if (_query.trim().isEmpty) return _rows;
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      final mb = r['medicine_batches'] as Map<String, dynamic>?;
      final med = mb?['medicines'] as Map<String, dynamic>?;
      final medMap = med ?? const <String, dynamic>{};
      final haystack =
          '${medicinePrimaryLabel(medMap)} ${medicineBrandName(medMap)} ${medicineGenericName(medMap)}'
              .toLowerCase();
      final batch = (mb?['batch_no'] as String? ?? '').toLowerCase();
      return haystack.contains(q) || batch.contains(q);
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
            'qty_base_unit, medicine_batches(batch_no, expiry_date, medicines(id, name, generic_name, reorder_level))',
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
    final role =
        ref.watch(pharmacyProfileProvider).asData?.value?['role'] as String?;
    final canAddStockIn = canAddStockInForRole(role);
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? AppErrorState(message: _error!, onRetry: _load)
        : RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: PharmacyHubFilterSection(
                    searchHint: 'Search medicine or batch',
                    onSearchChanged: (value) => setState(() => _query = value),
                    countLabel:
                        'Showing ${_displayRows.length} of ${_rows.length} low stock',
                  ),
                ),
                if (_rows.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _StockHubEmptyState(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'All stocked',
                      message: 'No batches at or below reorder level.',
                      iconColor: Theme.of(context).colorScheme.primary,
                    ),
                  )
                else if (_displayRows.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _StockHubEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches',
                      message: 'Try a different search term.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: pharmacyHubListPadding(context, bottom: 88),
                    sliver: SliverList.builder(
                      itemCount: _displayRows.length,
                      itemBuilder: (context, i) {
                        final r = _displayRows[i];
                        final mb = r['medicine_batches'] as Map<String, dynamic>?;
                        final med = mb?['medicines'] as Map<String, dynamic>?;
                        final medMap = med ?? const <String, dynamic>{};
                        final primary = medicinePrimaryLabel(medMap);
                        final brand = medicineSecondaryLabel(medMap);
                        final reorder = med?['reorder_level'];
                        final batch = mb?['batch_no'] as String? ?? '';
                        final exp = mb?['expiry_date'] as String? ?? '';
                        final qty = r['qty_base_unit'];
                        final medicineId = med?['id'] as String?;
                        return PharmacyHubListRow(
                          icon: Icons.warning_amber_rounded,
                          iconColor: Theme.of(context).colorScheme.error
                              .withValues(alpha: 0.9),
                          borderColor: Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: 0.45),
                          title: primary,
                          subtitle: [
                            if (brand != null) brand,
                            'Batch ${batch.isEmpty ? "—" : batch} · exp ${formatDdMmYyyy(exp)} · reorder ≤ $reorder',
                          ].join(' · '),
                          subtitleMaxLines: 2,
                          onTap: medicineId != null
                              ? () =>
                                    context.push('/pharmacy/medicines/$medicineId')
                              : null,
                          trailing: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$qty',
                                style: context.layoutDensity
                                    .listTitleStyle(
                                      Theme.of(context).textTheme,
                                    )
                                    ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color:
                                      Theme.of(context).colorScheme.error,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              if (canAddStockIn)
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: context.layoutDensity.listIconSize,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                            ],
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

class _StockHubEmptyState extends StatelessWidget {
  const _StockHubEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: iconColor ?? cs.onSurfaceVariant.withValues(alpha: 0.75),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool _stockExpiryIsNear(String? expiry, {int withinDays = 30}) {
  final dt = DateTime.tryParse(expiry ?? '');
  if (dt == null) return false;
  return dt.difference(DateTime.now()).inDays <= withinDays;
}
