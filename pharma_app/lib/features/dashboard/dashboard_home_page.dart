import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';

class DashboardHomePage extends ConsumerStatefulWidget {
  const DashboardHomePage({super.key});

  @override
  ConsumerState<DashboardHomePage> createState() => _DashboardHomePageState();
}

class _DashboardHomePageState extends ConsumerState<DashboardHomePage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _metrics;
  int _unread = 0;
  DateTime? _lastUpdated;
  final Set<String> _selectedCategoryIds = <String>{};

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
      var m = await _loadDashboardMetrics(teamId, branchId);
      final role =
          (profile?['role'] as String? ?? '').trim().toLowerCase();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (role == 'pharmacist' && uid != null) {
        m = await _mergePharmacistOwnSalesKpis(
          Map<String, dynamic>.from(m as Map),
          teamId,
          branchId,
          uid,
        );
      }
      final unreadRows = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('team_id', teamId)
          .or('branch_id.is.null,branch_id.eq.$branchId')
          .eq('is_read', false)
          .limit(500);
      setState(() {
        _metrics = Map<String, dynamic>.from(m);
        _unread = (unreadRows as List).length;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static List<Map<String, dynamic>> _parseTopSellers(Object? raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    return raw
        .map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          return <String, dynamic>{};
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  Future<dynamic> _loadDashboardMetrics(String teamId, String branchId) async {
    return Supabase.instance.client.rpc(
      'dashboard_metrics',
      params: {
        'p_team_id': teamId,
        'p_branch_id': branchId,
        'p_category_ids': _selectedCategoryIds.isEmpty
            ? null
            : _selectedCategoryIds.toList(growable: false),
      },
    );
  }

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  /// Pharmacist: replace branch-wide sales KPIs with this user's sales only
  /// (via unified report + client-side distinct sale_id), no DB migration.
  Future<Map<String, dynamic>> _mergePharmacistOwnSalesKpis(
    Map<String, dynamic> base,
    String teamId,
    String branchId,
    String userId,
  ) async {
    final fmt = DateFormat('yyyy-MM-dd');
    final today = _dateOnly(DateTime.now());
    final catIds = _selectedCategoryIds.isEmpty
        ? null
        : _selectedCategoryIds.toList(growable: false);

    Future<(num total, int count)> totalsForRange(
      DateTime from,
      DateTime to,
    ) async {
      final data = await Supabase.instance.client.rpc(
        'rpc_report_sales_unified',
        params: {
          'p_team_id': teamId,
          'p_branch_id': branchId,
          'p_from': fmt.format(from),
          'p_to': fmt.format(to),
          'p_sold_by': userId,
          'p_min_amount': null,
          'p_max_amount': null,
          'p_payment_method': null,
          'p_overrides_only': false,
          'p_category_ids': catIds,
        },
      );
      final rows =
          List<Map<String, dynamic>>.from(data as List? ?? const []);
      final seen = <String>{};
      num grand = 0;
      for (final r in rows) {
        final sid = '${r['sale_id'] ?? ''}'.trim();
        if (sid.isEmpty || !seen.add(sid)) continue;
        grand += (r['grand_total'] as num?) ?? 0;
      }
      return (grand, seen.length);
    }

    final (todayTotal, todayCount) = await totalsForRange(today, today);
    final (w7Total, w7Count) = await totalsForRange(
      today.subtract(const Duration(days: 6)),
      today,
    );
    final (w30Total, _) = await totalsForRange(
      today.subtract(const Duration(days: 29)),
      today,
    );

    base['today_sales_total'] = todayTotal;
    base['today_sales_count'] = todayCount;
    base['sales_7d_total'] = w7Total;
    base['sales_mtd_total'] = w30Total;
    base['sales_by_staff_7d'] = [
      {
        'name': 'My sales',
        'sale_count': w7Count,
        'total': w7Total,
      },
    ];
    return base;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedBranchIdProvider, (previous, next) => _load());
    final teamId =
        ref.watch(pharmacyProfileProvider).asData?.value?['team_id'] as String?;
    final branchId = ref.watch(selectedBranchIdProvider);
    final branchesAsync = ref.watch(branchesListProvider(teamId ?? ''));
    final categoriesAsync = ref.watch(activeBranchMedicineCategoriesProvider);

    final branchLabel = teamId == null || teamId.isEmpty
        ? '—'
        : branchesAsync.when(
            loading: () => '…',
            error: (_, _) => '—',
            data: (branches) {
              if (branchId == null) return 'No branch selected';
              for (final b in branches) {
                if (b['id'] == branchId) {
                  return b['name'] as String? ?? 'Branch';
                }
              }
              return 'Unknown branch';
            },
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Overview',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? AppErrorState(
              message: _error!,
              onRetry: _load,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gridColumns = constraints.maxWidth >= 960
                      ? 3
                      : (constraints.maxWidth >= 360 ? 2 : 1);
                  final role = (ref
                              .watch(pharmacyProfileProvider)
                              .asData
                              ?.value?['role'] as String? ??
                          '')
                      .trim()
                      .toLowerCase();
                  final isPharmacist = role == 'pharmacist';
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                    children: [
                      _heroHeader(
                        context,
                        branchLabel,
                        categoriesAsync.value
                                ?.map((row) {
                                  final id = (row['id'] as String? ?? '').trim();
                                  final name = (row['name'] as String? ?? '').trim();
                                  if (id.isEmpty || name.isEmpty) return null;
                                  return {'id': id, 'name': name};
                                })
                                .whereType<Map<String, String>>()
                                .toList() ??
                            const <Map<String, String>>[],
                      ),
                      const SizedBox(height: 12),
                      _quickActions(context),
                      const SizedBox(height: 14),
                      if (_metrics != null) ...[
                        _sectionTitle(context, 'Sales snapshot'),
                        const SizedBox(height: 8),
                        _metricGrid(
                          context,
                          gridColumns: gridColumns,
                          children: [
                            _metricCard(
                              context,
                              title: isPharmacist
                                  ? 'Your sales today'
                                  : 'Today sales total',
                              value: _money(_metrics!['today_sales_total']),
                              route: '/pharmacy/reports/sales_summary',
                              icon: Icons.payments_rounded,
                            ),
                            _metricCard(
                              context,
                              title: isPharmacist
                                  ? 'Your sales count today'
                                  : 'Today sales count',
                              value: _formatMetric(_metrics!['today_sales_count'], decimals: 0),
                              route: '/pharmacy/reports/sales_summary',
                              icon: Icons.receipt_long_rounded,
                            ),
                            if (!isPharmacist)
                              _metricCard(
                                context,
                                title: 'Today gross profit',
                                value: _money(_metrics!['today_profit_total'] ?? 0),
                                route: '/pharmacy/reports/profit_summary',
                                icon: Icons.trending_up_rounded,
                              ),
                            _metricCard(
                              context,
                              title: isPharmacist
                                  ? 'Your sales (7 days)'
                                  : 'Sales (last 7 days)',
                              value: _money(_metrics!['sales_7d_total'] ?? 0),
                              route: '/pharmacy/reports/sales_summary',
                              icon: Icons.view_week_rounded,
                            ),
                            _metricCard(
                              context,
                              title: isPharmacist
                                  ? 'Your sales (30 days)'
                                  : 'Sales (month to date)',
                              value: _money(_metrics!['sales_mtd_total'] ?? 0),
                              route: '/pharmacy/reports/sales_summary',
                              icon: isPharmacist
                                  ? Icons.date_range_rounded
                                  : Icons.calendar_month_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _sectionTitle(context, 'Inventory health'),
                        const SizedBox(height: 8),
                        _metricGrid(
                          context,
                          gridColumns: gridColumns,
                          children: [
                            _metricCard(
                              context,
                              title: 'Stock value at cost',
                              value: _money(_metrics!['stock_value_at_cost'] ?? 0),
                              subtitle: 'Qty × medicine purchase price',
                              route: '/pharmacy/reports/stock_balance',
                              icon: Icons.inventory_2_rounded,
                            ),
                            _metricCard(
                              context,
                              title: 'Low stock SKUs',
                              value: _formatMetric(_metrics!['low_stock_count'], decimals: 0),
                              route: '/pharmacy/stock?tab=low',
                              icon: Icons.warning_amber_rounded,
                            ),
                            _metricCard(
                              context,
                              title: 'Near expiry batches',
                              value: _formatMetric(_metrics!['near_expiry_count'], decimals: 0),
                              route: '/pharmacy/expiry?tab=near',
                              icon: Icons.event_note_rounded,
                            ),
                            _metricCard(
                              context,
                              title: 'Expired batches',
                              value: _formatMetric(_metrics!['expired_count'], decimals: 0),
                              route: '/pharmacy/expiry?tab=expired',
                              icon: Icons.event_busy_rounded,
                            ),
                          ],
                        ),
                        if (!isPharmacist) ...[
                          const SizedBox(height: 14),
                          _sectionTitle(context, 'Top sales by medicine (7 days)'),
                          const SizedBox(height: 8),
                          Card(
                            clipBehavior: Clip.antiAlias,
                            child: _topSellersBody(context, _metrics!['top_sellers_7d']),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _sectionTitle(
                          context,
                          isPharmacist
                              ? 'My sales (7 days)'
                              : 'Sales by staff (7 days)',
                        ),
                        const SizedBox(height: 8),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () =>
                                context.push('/pharmacy/reports/sales_by_staff'),
                            child: _staffSalesBody(context, _metrics!['sales_by_staff_7d']),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _heroHeader(
    BuildContext context,
    String branchLabel,
    List<Map<String, String>> categoryOptions,
  ) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branchLabel,
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Snapshot for this branch.',
                      style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (_unread > 0)
                FilledButton.tonalIcon(
                  onPressed: () => context.go('/pharmacy/notifications'),
                  icon: Badge(label: Text('$_unread'), child: const Icon(Icons.notifications_outlined)),
                  label: const Text('Alerts'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _lastUpdated == null ? 'Not updated yet' : 'Last updated: ${formatDdMmYyyyHm(_lastUpdated)}',
            style: t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (categoryOptions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Medicine categories'),
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
                _load();
              },
            ),
          ],
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

  Widget _quickActions(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => context.go('/pharmacy/reports'),
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('Report tables'),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _metricGrid(BuildContext context, {required int gridColumns, required List<Widget> children}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridColumns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: gridColumns >= 3 ? 1.45 : (gridColumns == 2 ? 1.25 : 2.4),
      ),
      itemBuilder: (context, index) => children[index],
    );
  }

  static List<Map<String, dynamic>> _parseStaffRows(Object? raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    return raw
        .map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          return <String, dynamic>{};
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  Widget _staffSalesBody(BuildContext context, Object? raw) {
    final rows = _parseStaffRows(raw);
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No sales in the last 7 days.'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++)
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
            title: Text(rows[i]['name'] as String? ?? ''),
            subtitle: Text(
              '${_formatMetric(rows[i]['sale_count'], decimals: 0)} sales',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: Text(
              _money(rows[i]['total']),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Tap for full date range in Report tables',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _topSellersBody(BuildContext context, Object? raw) {
    final rows = _parseTopSellers(raw);
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No sales in the last 7 days.'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++)
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
            title: Text(rows[i]['name'] as String? ?? ''),
            trailing: Text(
              _money(rows[i]['revenue']),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  String _money(Object? v) => '${_formatMetric(v, decimals: 2)} ETB';

  String _formatMetric(Object? v, {required int decimals}) {
    if (v == null) return '0';
    if (v is num) {
      if (decimals == 0) {
        return NumberFormat.decimalPattern().format(v);
      }
      return NumberFormat('#,##0.${'0' * decimals}').format(v);
    }
    return v.toString();
  }

  Widget _metricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    String? subtitle,
    String? route,
  }) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: route == null ? null : () => context.push(route),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 19, color: cs.primary),
                    ),
                    const Spacer(),
                    if (route != null)
                      Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
