import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
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
      final m = await Supabase.instance.client.rpc(
        'dashboard_metrics',
        params: {
          'p_team_id': teamId,
          'p_branch_id': branchId,
        },
      );
      final unreadRows = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('team_id', teamId)
          .or('branch_id.is.null,branch_id.eq.$branchId')
          .eq('is_read', false)
          .limit(500);
      setState(() {
        _metrics = Map<String, dynamic>.from(m as Map);
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

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedBranchIdProvider, (previous, next) => _load());
    final teamId = ref.watch(pharmacyProfileProvider).asData?.value?['team_id'] as String?;
    final branchId = ref.watch(selectedBranchIdProvider);
    final branchesAsync = ref.watch(branchesListProvider(teamId ?? ''));

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
        title: const Text('Overview'),
        actions: [
          if (_unread > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => context.go('/pharmacy/notifications'),
                icon: Badge(
                  label: Text('$_unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                label: const Text('Alerts'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorState(
                  message: _error!,
                  onRetry: () {
                    _load();
                  },
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        branchLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Snapshot for this branch. Open Report tables for full grids, filters, and CSV copy.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => context.go('/pharmacy/pos'),
                            icon: const Icon(Icons.point_of_sale_outlined),
                            label: const Text('POS'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => context.go('/pharmacy/stock-in'),
                            icon: const Icon(Icons.add_shopping_cart_outlined),
                            label: const Text('Stock in'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => context.go('/pharmacy/reports'),
                            icon: const Icon(Icons.table_chart_outlined),
                            label: const Text('Report tables'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_lastUpdated != null)
                        Text(
                          'Last updated: ${DateFormat.yMMMd().add_jm().format(_lastUpdated!.toLocal())}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 8),
                      if (_metrics != null) ...[
                        _tile(
                          context,
                          'Today sales total',
                          _money(_metrics!['today_sales_total']),
                          route: '/pharmacy/reports/sales_summary',
                        ),
                        _tile(
                          context,
                          'Today sales count',
                          _formatMetric(_metrics!['today_sales_count'], decimals: 0),
                          route: '/pharmacy/reports/sales_summary',
                        ),
                        _tile(
                          context,
                          'Today gross profit',
                          _money(_metrics!['today_profit_total'] ?? 0),
                          route: '/pharmacy/reports/profit_summary',
                        ),
                        _tile(
                          context,
                          'Sales (last 7 days)',
                          _money(_metrics!['sales_7d_total'] ?? 0),
                          route: '/pharmacy/reports/sales_summary',
                        ),
                        _tile(
                          context,
                          'Sales (month to date)',
                          _money(_metrics!['sales_mtd_total'] ?? 0),
                          route: '/pharmacy/reports/sales_summary',
                        ),
                        _tile(
                          context,
                          'Stock value at cost',
                          _money(_metrics!['stock_value_at_cost'] ?? 0),
                          subtitle: 'Qty × medicine purchase price',
                          route: '/pharmacy/reports/stock_balance',
                        ),
                        _tile(
                          context,
                          'Low stock SKUs',
                          _formatMetric(
                            _metrics!['low_stock_count'],
                            decimals: 0,
                          ),
                          route: '/pharmacy/stock?tab=low',
                        ),
                        _tile(
                          context,
                          'Near expiry batches',
                          _formatMetric(
                            _metrics!['near_expiry_count'],
                            decimals: 0,
                          ),
                          route: '/pharmacy/expiry?tab=near',
                        ),
                        _tile(
                          context,
                          'Expired batches',
                          _formatMetric(
                            _metrics!['expired_count'],
                            decimals: 0,
                          ),
                          route: '/pharmacy/expiry?tab=expired',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Top sales by medicine (7 days)',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Card(
                          child: _topSellersBody(context, _metrics!['top_sellers_7d']),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sales by staff (7 days)',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => context.go('/pharmacy/reports/sales_by_staff'),
                            child: _staffSalesBody(context, _metrics!['sales_by_staff_7d']),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
            leading: CircleAvatar(
              radius: 14,
              child: Text('${i + 1}'),
            ),
            title: Text(rows[i]['name'] as String? ?? ''),
            subtitle: Text(
              '${_formatMetric(rows[i]['sale_count'], decimals: 0)} sales',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: Text(
              _money(rows[i]['total']),
              style: Theme.of(context).textTheme.bodyMedium,
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
            leading: CircleAvatar(
              radius: 14,
              child: Text('${i + 1}'),
            ),
            title: Text(rows[i]['name'] as String? ?? ''),
            trailing: Text(
              _money(rows[i]['revenue']),
              style: Theme.of(context).textTheme.bodyMedium,
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

  Widget _tile(
    BuildContext context,
    String title,
    String value, {
    String? subtitle,
    String? route,
  }) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
        onTap: route == null ? null : () => context.go(route),
      ),
    );
  }
}
