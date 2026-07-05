import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/layout/layout_density.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/etb_amount_display.dart';
import '../reports/report_display.dart';

bool homeReportsEnabledForRole(String role) {
  return switch (role.trim().toLowerCase()) {
    'pharmacist' || 'admin' || 'owner' => true,
    _ => false,
  };
}

String formatHomeReportValue(String key, Object? value) {
  final raw = value ?? '';
  final s = '$raw'.trim();
  if (s.isEmpty) return '';
  final k = key.toLowerCase();
  if (value is num &&
      (k.contains('total') ||
          k.contains('revenue') ||
          k.contains('profit') ||
          k.contains('amount') ||
          k.contains('gain'))) {
    return '${formatEtbAmount(value)} ETB';
  }
  return formatReportCell(key, value);
}

class HomeReportsSnapshot {
  const HomeReportsSnapshot({
    this.profitToday,
    this.salesStatsToday,
    required this.metrics,
    required this.isPharmacist,
  });

  final Map<String, dynamic>? profitToday;
  final Map<String, dynamic>? salesStatsToday;
  final Map<String, dynamic> metrics;
  final bool isPharmacist;
}

class HomeReportsRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final homeReportsRefreshTickProvider =
    NotifierProvider<HomeReportsRefreshNotifier, int>(
      HomeReportsRefreshNotifier.new,
    );

final homeReportsSnapshotProvider =
    FutureProvider.autoDispose<HomeReportsSnapshot?>((ref) async {
      ref.watch(homeReportsRefreshTickProvider);
      final profile = await ref.watch(pharmacyProfileProvider.future);
      final branchId = ref.watch(selectedBranchIdProvider);
      final teamId = profile?['team_id'] as String?;
      final role = (profile?['role'] as String? ?? '').trim().toLowerCase();

      if (!homeReportsEnabledForRole(role)) return null;
      if (teamId == null || branchId == null) return null;

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final client = Supabase.instance.client;
      final isPharmacist = role == 'pharmacist';

      final metricsFuture = client.rpc(
        'dashboard_metrics',
        params: {
          'p_team_id': teamId,
          'p_branch_id': branchId,
          'p_category_keys': null,
        },
      );

      if (isPharmacist) {
        final userId = client.auth.currentUser?.id;
        final statsFuture = client.rpc(
          'rpc_report_sales_unified_stats',
          params: {
            'p_team_id': teamId,
            'p_branch_id': branchId,
            'p_from': today,
            'p_to': today,
            'p_sold_by': userId,
            'p_min_amount': null,
            'p_max_amount': null,
            'p_payment_method': null,
            'p_overrides_only': false,
            'p_category_keys': null,
            'p_search': null,
          },
        );
        final results = await Future.wait([metricsFuture, statsFuture]);
        final metrics = Map<String, dynamic>.from(results[0] as Map);
        final statsRows =
            List<Map<String, dynamic>>.from(results[1] as List);
        return HomeReportsSnapshot(
          salesStatsToday: statsRows.isEmpty ? null : statsRows.first,
          metrics: metrics,
          isPharmacist: true,
        );
      }

      final profitFuture = client.rpc(
        'rpc_report_profit_summary',
        params: {
          'p_team_id': teamId,
          'p_branch_id': branchId,
          'p_from': today,
          'p_to': today,
        },
      );

      final results = await Future.wait([metricsFuture, profitFuture]);
      final metrics = Map<String, dynamic>.from(results[0] as Map);
      final profitRows = List<Map<String, dynamic>>.from(results[1] as List);

      return HomeReportsSnapshot(
        profitToday: profitRows.isEmpty ? null : profitRows.first,
        metrics: metrics,
        isPharmacist: false,
      );
    });

class HomeReportsSnapshotCard extends ConsumerWidget {
  const HomeReportsSnapshotCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(pharmacyProfileProvider).asData?.value;
    final role = (profile?['role'] as String? ?? '').trim().toLowerCase();
    if (!homeReportsEnabledForRole(role)) {
      return const SizedBox.shrink();
    }

    final snapAsync = ref.watch(homeReportsSnapshotProvider);
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final density = context.layoutDensity;

    return snapAsync.when(
      loading: () => _HomeReportsCardShell(
        compact: compact,
        child: Padding(
          padding: EdgeInsets.all(density.v(compact: 14, standard: 16, comfortable: 18)),
          child: const Center(
            child: SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (snap) {
        if (snap == null) return const SizedBox.shrink();
        return _HomeReportsCardShell(
          compact: compact,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              density.v(compact: 14, standard: 16, comfortable: 18),
              density.v(compact: 12, standard: 14, comfortable: 16),
              density.v(compact: 10, standard: 12, comfortable: 14),
              density.v(compact: 12, standard: 14, comfortable: 16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => context.go('/pharmacy/reports'),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.insights_rounded,
                        size: density.listIconSize,
                        color: const Color(0xFF7C3AED),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Today',
                          style: density.listTitleStyle(t.textTheme),
                        ),
                      ),
                      Text(
                        'Full reports',
                        style: t.textTheme.labelMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: density.listIconSize,
                        color: cs.primary,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: density.v(compact: 10, standard: 12, comfortable: 14)),
                if (snap.isPharmacist)
                  _HomeReportsStatRow(
                    stats: [
                      _HomeReportStat(
                        label: 'Sales',
                        value: formatHomeReportValue(
                          'sale_count',
                          snap.salesStatsToday?['line_count'],
                        ),
                      ),
                      _HomeReportStat(
                        label: 'Total',
                        value: formatHomeReportValue(
                          'grand_total',
                          snap.salesStatsToday?['grand_total_sum'],
                        ),
                      ),
                    ],
                  )
                else
                  _HomeReportsStatRow(
                    stats: [
                      _HomeReportStat(
                        label: 'Gain',
                        value: formatHomeReportValue(
                          'revenue',
                          snap.profitToday?['revenue'],
                        ),
                      ),
                      _HomeReportStat(
                        label: 'Profit',
                        value: formatHomeReportValue(
                          'gross_profit',
                          snap.profitToday?['gross_profit'],
                        ),
                      ),
                      _HomeReportStat(
                        label: 'Sales',
                        value: formatHomeReportValue(
                          'sale_count',
                          snap.profitToday?['sale_count'],
                        ),
                      ),
                    ],
                  ),
                SizedBox(height: density.v(compact: 10, standard: 12, comfortable: 14)),
                _HomeReportsAlertsRow(metrics: snap.metrics),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeReportStat {
  const _HomeReportStat({required this.label, required this.value});

  final String label;
  final String value;
}

class _HomeReportsStatRow extends StatelessWidget {
  const _HomeReportsStatRow({required this.stats});

  final List<_HomeReportStat> stats;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stats[i].label,
                    style: t.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats[i].value.isEmpty ? '—' : stats[i].value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HomeReportsAlertsRow extends StatelessWidget {
  const _HomeReportsAlertsRow({required this.metrics});

  final Map<String, dynamic> metrics;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final low = (metrics['low_stock_count'] as num?)?.toInt() ?? 0;
    final near = (metrics['near_expiry_count'] as num?)?.toInt() ?? 0;
    final expired = (metrics['expired_count'] as num?)?.toInt() ?? 0;

    Widget chip(
      String label,
      int count,
      Color fg,
      VoidCallback onTap,
    ) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Text(
                    '$count',
                    style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: count > 0 ? fg : cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    label,
                    style: t.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          chip(
            'Low',
            low,
            cs.error,
            () => context.go('/pharmacy/stock?tab=low'),
          ),
          Container(width: 1, height: 28, color: cs.outlineVariant.withValues(alpha: 0.35)),
          chip(
            'Near exp.',
            near,
            const Color(0xFFD97706),
            () => context.go('/pharmacy/expiry?tab=near'),
          ),
          Container(width: 1, height: 28, color: cs.outlineVariant.withValues(alpha: 0.35)),
          chip(
            'Expired',
            expired,
            cs.error,
            () => context.go('/pharmacy/expiry?tab=expired'),
          ),
        ],
      ),
    );
  }
}

class _HomeReportsCardShell extends StatelessWidget {
  const _HomeReportsCardShell({
    required this.child,
    this.compact = false,
  });

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(compact ? 16 : 18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 16 : 18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
        ),
        child: child,
      ),
    );
  }
}
