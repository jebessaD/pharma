import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/layout/layout_density.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/utils/etb_amount_display.dart';
import 'recent_sales_repository.dart';
import 'sale_receipt_text.dart';

class RecentSalesPanel extends ConsumerStatefulWidget {
  const RecentSalesPanel({super.key, this.limit = 5, this.compact = false});

  final int limit;
  final bool compact;

  @override
  ConsumerState<RecentSalesPanel> createState() => _RecentSalesPanelState();
}

class _RecentSalesPanelState extends ConsumerState<RecentSalesPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(pharmacyProfileProvider);
    final branchId = ref.watch(selectedBranchIdProvider);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final density = context.layoutDensity;
    final compact = widget.compact || density.isCompact;

    return Card(
      elevation: 0,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          density.v(compact: 16, standard: 16, comfortable: 18),
          widget.compact ? 10 : density.v(compact: 10, standard: 14, comfortable: 16),
          density.v(compact: 16, standard: 16, comfortable: 18),
          density.v(compact: 14, standard: 14, comfortable: 16),
        ),
        child: profileAsync.when(
          loading: () => _RecentSalesShell(
            compact: widget.compact,
            expanded: _expanded,
            onToggle: _toggleExpanded,
            child: _expanded ? const _RecentSalesLoading() : null,
          ),
          error: (error, _) => _RecentSalesShell(
            compact: widget.compact,
            expanded: _expanded,
            onToggle: _toggleExpanded,
            child: _expanded
                ? _RecentSalesMessage(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load recent sales',
                    message: error.toString(),
                    embedded: true,
                  )
                : null,
          ),
          data: (profile) {
            final teamId = profile?['team_id'] as String? ?? '';
            final role = (profile?['role'] as String? ?? '')
                .trim()
                .toLowerCase();
            if (teamId.isEmpty || branchId == null || branchId.isEmpty) {
              return _RecentSalesShell(
                compact: widget.compact,
                expanded: _expanded,
                onToggle: _toggleExpanded,
                child: _expanded
                    ? const _RecentSalesMessage(
                        icon: Icons.storefront_outlined,
                        title: 'Recent sales',
                        message: 'Select a branch to see confirmed sales.',
                        embedded: true,
                      )
                    : null,
              );
            }

            final params = (
              teamId: teamId,
              branchId: branchId,
              role: role,
              userId: currentUserId,
              limit: widget.limit,
            );
            final details = _expanded
                ? ref
                      .watch(recentSalesProvider(params))
                      .when(
                        loading: () => const _RecentSalesLoading(),
                        error: (error, _) => _RecentSalesMessage(
                          icon: Icons.error_outline_rounded,
                          title: 'Could not load recent sales',
                          message: error.toString(),
                          embedded: true,
                        ),
                        data: (sales) => _RecentSalesDetails(
                          sales: sales,
                          compact: compact,
                        ),
                      )
                : null;

            return _RecentSalesShell(
              compact: widget.compact,
              expanded: _expanded,
              onToggle: _toggleExpanded,
              onRefresh: _expanded
                  ? () => ref.invalidate(recentSalesProvider(params))
                  : null,
              child: details,
            );
          },
        ),
      ),
    );
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
  }
}

class _RecentSalesShell extends StatelessWidget {
  const _RecentSalesShell({
    required this.compact,
    required this.expanded,
    required this.onToggle,
    this.onRefresh,
    this.child,
  });

  final bool compact;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onRefresh;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RecentSalesHeader(
          compact: compact,
          expanded: expanded,
          onToggle: onToggle,
          onRefresh: onRefresh,
        ),
        if (expanded && child != null) ...[const SizedBox(height: 10), child!],
      ],
    );
  }
}

class _RecentSalesHeader extends StatelessWidget {
  const _RecentSalesHeader({
    required this.compact,
    required this.expanded,
    required this.onToggle,
    this.onRefresh,
  });

  final bool compact;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              Icons.history_rounded,
              color: cs.primary,
              size: compact ? 20 : 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent sales',
                    style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (!compact)
                    Text(
                      expanded
                          ? 'Confirmed sales with sold item details'
                          : 'Tap to check confirmed sale history',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                ],
              ),
            ),
            if (onRefresh != null)
              IconButton(
                tooltip: 'Refresh recent sales',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            IconButton(
              tooltip: expanded ? 'Hide recent sales' : 'Show recent sales',
              onPressed: onToggle,
              icon: AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentSalesDetails extends StatelessWidget {
  const _RecentSalesDetails({required this.sales, this.compact = false});

  final List<RecentSale> sales;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    if (sales.isEmpty) {
      return const _RecentSalesMessage(
        icon: Icons.receipt_long_outlined,
        title: 'No recent confirmed sales yet',
        message: 'When a sale is confirmed by the server, it will appear here.',
        embedded: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...sales.map((sale) => _RecentSaleTile(sale: sale, compact: compact)),
        const SizedBox(height: 8),
        Text(
          'Only confirmed server sales appear here.',
          style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _RecentSaleTile extends StatelessWidget {
  const _RecentSaleTile({required this.sale, this.compact = false});

  final RecentSale sale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final method = (sale.paymentMethod ?? '').trim();
    final paymentLabel = method.isEmpty
        ? 'Payment'
        : salePaymentMethodLabel(method);
    final itemLabel = sale.itemCount == 1
        ? '1 item'
        : '${sale.itemCount} items';
    final created = sale.createdAt == null
        ? 'Unknown time'
        : formatDdMmYyyyHm(sale.createdAt);
    final seller = (sale.sellerName ?? '').trim();
    final ref = (sale.referenceNo ?? '').trim();
    final meta = [
      created,
      paymentLabel,
      itemLabel,
      if (seller.isNotEmpty) seller,
      if (ref.isNotEmpty) 'Ref $ref',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 8),
      child: Material(
        color: Color.alphaBlend(
          cs.surfaceContainerHighest.withValues(alpha: 0.24),
          cs.surface,
        ),
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/pharmacy/receipt/${sale.id}'),
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 8 : 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (!compact)
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.receipt_long_rounded,
                          color: cs.onPrimaryContainer,
                          size: 20,
                        ),
                      ),
                    if (!compact) const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${formatEtbAmountFixed2(sale.grandTotal)} ETB',
                            style: (compact
                                    ? t.textTheme.labelLarge
                                    : t.textTheme.titleSmall)
                                ?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: compact ? 1 : 2),
                          Text(
                            compact
                                ? [
                                    created.split(' ').first,
                                    paymentLabel,
                                    if (seller.isNotEmpty) seller,
                                  ].join(' · ')
                                : meta,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.2,
                              fontSize: compact ? 11 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: compact ? 18 : 24,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
                if (sale.items.isNotEmpty) ...[
                  SizedBox(height: compact ? 6 : 10),
                  ...sale.items
                      .take(compact ? 2 : 3)
                      .map(
                        (item) => _RecentSaleItemLine(
                          item: item,
                          compact: compact,
                        ),
                      ),
                  if (sale.items.length > (compact ? 2 : 3))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+ ${sale.items.length - (compact ? 2 : 3)} more',
                        style: t.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

class _RecentSaleItemLine extends StatelessWidget {
  const _RecentSaleItemLine({required this.item, this.compact = false});

  final RecentSaleItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final generic = (item.genericName ?? '').trim();
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 2 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatEtbAmount(item.qty)}×',
            style: t.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (compact ? t.textTheme.labelMedium : t.textTheme.bodySmall)
                      ?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!compact && generic.isNotEmpty)
                  Text(
                    generic,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.15,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSalesLoading extends StatelessWidget {
  const _RecentSalesLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 72,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _RecentSalesMessage extends StatelessWidget {
  const _RecentSalesMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.embedded = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Container(
      padding: EdgeInsets.all(embedded ? 12 : 4),
      decoration: embedded
          ? BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.onSurfaceVariant, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
