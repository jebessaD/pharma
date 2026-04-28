import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class _ReportCard {
  const _ReportCard({
    required this.title,
    required this.subtitle,
    required this.path,
    required this.icon,
    required this.accent,
    required this.accentSoft,
  });

  final String title;
  final String subtitle;
  final String path;
  final IconData icon;
  final Color accent;
  final Color accentSoft;
}

class _ReportSection {
  const _ReportSection({required this.title, required this.items});

  final String title;
  final List<_ReportCard> items;
}

class ReportsHomePage extends StatelessWidget {
  const ReportsHomePage({super.key});

  static const _sections = <_ReportSection>[
    _ReportSection(
      title: 'Core reports',
      items: [
        _ReportCard(
          title: 'Sales summary',
          subtitle: 'Each sale within a selected date range',
          path: '/pharmacy/reports/sales_summary',
          icon: Icons.receipt_long_rounded,
          accent: Color(0xFF2563EB),
          accentSoft: Color(0xFFDBEAFE),
        ),
        _ReportCard(
          title: 'Sales by staff',
          subtitle: 'Compare who sold what in a date range',
          path: '/pharmacy/reports/sales_by_staff',
          icon: Icons.groups_rounded,
          accent: Color(0xFF059669),
          accentSoft: Color(0xFFD1FAE5),
        ),
        _ReportCard(
          title: 'Profit summary',
          subtitle: 'Revenue, COGS, gross profit and margin',
          path: '/pharmacy/reports/profit_summary',
          icon: Icons.trending_up_rounded,
          accent: Color(0xFF7C3AED),
          accentSoft: Color(0xFFEDE9FE),
        ),
      ],
    ),
    _ReportSection(
      title: 'Inventory reports',
      items: [
        _ReportCard(
          title: 'Stock balance',
          subtitle: 'Current quantity by medicine batch',
          path: '/pharmacy/reports/stock_balance',
          icon: Icons.inventory_2_rounded,
          accent: Color(0xFF0D9488),
          accentSoft: Color(0xFFCCFBF1),
        ),
        _ReportCard(
          title: 'Expiry status',
          subtitle: 'Near-expiry and expired batches',
          path: '/pharmacy/reports/expiry_status',
          icon: Icons.event_busy_rounded,
          accent: Color(0xFFDC2626),
          accentSoft: Color(0xFFFEE2E2),
        ),
      ],
    ),
    _ReportSection(
      title: 'Trend reports',
      items: [
        _ReportCard(
          title: 'Daily trend',
          subtitle: 'Sales and profit grouped by day',
          path: '/pharmacy/reports/sales_trend_daily',
          icon: Icons.calendar_view_day_rounded,
          accent: Color(0xFFCA8A04),
          accentSoft: Color(0xFFFEF9C3),
        ),
        _ReportCard(
          title: 'Monthly trend',
          subtitle: 'Sales and profit grouped by month',
          path: '/pharmacy/reports/sales_trend_monthly',
          icon: Icons.calendar_month_rounded,
          accent: Color(0xFFEA580C),
          accentSoft: Color(0xFFFFEDD5),
        ),
        _ReportCard(
          title: 'Yearly trend',
          subtitle: 'Sales and profit grouped by year',
          path: '/pharmacy/reports/sales_trend_yearly',
          icon: Icons.date_range_rounded,
          accent: Color(0xFF4B5563),
          accentSoft: Color(0xFFE5E7EB),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reports',
                  style: t.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Simple list of report tables. Open one, set date range if needed, then run.',
                  style: t.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final section in _sections) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                section.title,
                style: t.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: section.items.length,
              itemBuilder: (context, i) {
                final r = section.items[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReportListTile(
                    card: r,
                    onTap: () => context.push(r.path),
                  ),
                );
              },
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _ReportListTile extends StatelessWidget {
  const _ReportListTile({required this.card, required this.onTap});

  final _ReportCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Material(
      color: cs.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: card.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(card.icon, color: card.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      card.title,
                      style: t.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      card.subtitle,
                      style: t.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
