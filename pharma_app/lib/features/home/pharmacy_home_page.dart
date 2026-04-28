import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/form_error_banner.dart';

class PharmacyHomePage extends ConsumerWidget {
  const PharmacyHomePage({super.key});

  static String _greetingLine() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _roleLabel(String role) {
    if (role.isEmpty) return '';
    return role[0].toUpperCase() + role.substring(1).toLowerCase();
  }

  static String _roleTagline(String role) {
    return switch (role) {
      'cashier' => 'Checkout and receipts — open POS when a customer is ready.',
      'pharmacist' => 'Stock, batches, and expiry — keep the shelf accurate.',
      'admin' => 'Operations, purchasing, and team — full control from here.',
      _ => 'Welcome back.',
    };
  }

  static List<_HomeSection> _sectionsForRole(String role) {
    switch (role) {
      case 'cashier':
        return const [];
      case 'pharmacist':
        return [
          _HomeSection(
            title: 'Counter & stock',
            actions: [
              _HomeAction(
                icon: Icons.inventory_2_rounded,
                label: 'Stock',
                subtitle: 'Balances & low stock',
                path: '/pharmacy/stock',
                accent: Color(0xFF2563EB),
                accentSoft: Color(0xFFDBEAFE),
              ),
              _HomeAction(
                icon: Icons.event_busy_rounded,
                label: 'Expiry',
                subtitle: 'Near-due & expired',
                path: '/pharmacy/expiry',
                accent: Color(0xFFDC2626),
                accentSoft: Color(0xFFFEE2E2),
              ),
              _HomeAction(
                icon: Icons.add_box_rounded,
                label: 'Stock in',
                subtitle: 'Receive inventory',
                path: '/pharmacy/stock-in',
                accent: Color(0xFFD97706),
                accentSoft: Color(0xFFFEF3C7),
              ),
              _HomeAction(
                icon: Icons.medication_rounded,
                label: 'Medicines',
                subtitle: 'Catalog & pricing',
                path: '/pharmacy/medicines',
                accent: Color(0xFF0D9488),
                accentSoft: Color(0xFFCCFBF1),
              ),
              _HomeAction(
                icon: Icons.swap_vert_rounded,
                label: 'Movements',
                subtitle: 'In / out history',
                path: '/pharmacy/stock-movements',
                accent: Color(0xFF6366F1),
                accentSoft: Color(0xFFE0E7FF),
              ),
              _HomeAction(
                icon: Icons.tune_rounded,
                label: 'Adjust stock',
                subtitle: 'Corrections & counts',
                path: '/pharmacy/adjust-stock',
                accent: Color(0xFF475569),
                accentSoft: Color(0xFFE2E8F0),
              ),
            ],
          ),
          _HomeSection(
            title: 'Insights',
            actions: [
              _HomeAction(
                icon: Icons.pie_chart_rounded,
                label: 'Overview',
                subtitle: 'Snapshot for this branch',
                path: '/pharmacy/dashboard',
                accent: Color(0xFF7C3AED),
                accentSoft: Color(0xFFEDE9FE),
              ),
              _HomeAction(
                icon: Icons.table_chart_rounded,
                label: 'Report tables',
                subtitle: 'Grids & CSV export',
                path: '/pharmacy/reports',
                accent: Color(0xFF4B5563),
                accentSoft: Color(0xFFE5E7EB),
              ),
            ],
          ),
        ];
      case 'admin':
        return [
          _HomeSection(
            title: 'Counter & stock',
            actions: [
              _HomeAction(
                icon: Icons.inventory_2_rounded,
                label: 'Stock',
                subtitle: 'Balances & low stock',
                path: '/pharmacy/stock',
                accent: Color(0xFF2563EB),
                accentSoft: Color(0xFFDBEAFE),
              ),
              _HomeAction(
                icon: Icons.event_busy_rounded,
                label: 'Expiry',
                subtitle: 'Near-due & expired',
                path: '/pharmacy/expiry',
                accent: Color(0xFFDC2626),
                accentSoft: Color(0xFFFEE2E2),
              ),
              _HomeAction(
                icon: Icons.add_box_rounded,
                label: 'Stock in',
                subtitle: 'Receive inventory',
                path: '/pharmacy/stock-in',
                accent: Color(0xFFD97706),
                accentSoft: Color(0xFFFEF3C7),
              ),
              _HomeAction(
                icon: Icons.medication_rounded,
                label: 'Medicines',
                subtitle: 'Catalog & pricing',
                path: '/pharmacy/medicines',
                accent: Color(0xFF0D9488),
                accentSoft: Color(0xFFCCFBF1),
              ),
              _HomeAction(
                icon: Icons.swap_vert_rounded,
                label: 'Movements',
                subtitle: 'In / out history',
                path: '/pharmacy/stock-movements',
                accent: Color(0xFF6366F1),
                accentSoft: Color(0xFFE0E7FF),
              ),
              _HomeAction(
                icon: Icons.tune_rounded,
                label: 'Adjust stock',
                subtitle: 'Corrections & counts',
                path: '/pharmacy/adjust-stock',
                accent: Color(0xFF475569),
                accentSoft: Color(0xFFE2E8F0),
              ),
            ],
          ),
          _HomeSection(
            title: 'Insights & compliance',
            actions: [
              _HomeAction(
                icon: Icons.pie_chart_rounded,
                label: 'Overview',
                subtitle: 'Snapshot for this branch',
                path: '/pharmacy/dashboard',
                accent: Color(0xFF7C3AED),
                accentSoft: Color(0xFFEDE9FE),
              ),
              _HomeAction(
                icon: Icons.table_chart_rounded,
                label: 'Report tables',
                subtitle: 'Grids & CSV export',
                path: '/pharmacy/reports',
                accent: Color(0xFF4B5563),
                accentSoft: Color(0xFFE5E7EB),
              ),
              _HomeAction(
                icon: Icons.history_rounded,
                label: 'Audit log',
                subtitle: 'Who changed what',
                path: '/pharmacy/audit',
                accent: Color(0xFF0F766E),
                accentSoft: Color(0xFFCCFBF1),
              ),
            ],
          ),
          _HomeSection(
            title: 'Purchasing & alerts',
            actions: [
              _HomeAction(
                icon: Icons.notifications_active_rounded,
                label: 'Notifications',
                subtitle: 'Team alerts',
                path: '/pharmacy/notifications',
                accent: Color(0xFFC026D3),
                accentSoft: Color(0xFFFAE8FF),
              ),
              _HomeAction(
                icon: Icons.local_shipping_rounded,
                label: 'Suppliers',
                subtitle: 'Vendor directory',
                path: '/pharmacy/suppliers',
                accent: Color(0xFF0369A1),
                accentSoft: Color(0xFFE0F2FE),
              ),
              _HomeAction(
                icon: Icons.receipt_long_rounded,
                label: 'New purchase',
                subtitle: 'Record an order',
                path: '/pharmacy/purchases/new',
                accent: Color(0xFFB45309),
                accentSoft: Color(0xFFFEF3C7),
              ),
            ],
          ),
          _HomeSection(
            title: 'Organization',
            actions: [
              _HomeAction(
                icon: Icons.apartment_rounded,
                label: 'Team & branches',
                subtitle: 'Profile, staff, locations',
                path: '/pharmacy/organization',
                accent: Color(0xFF4338CA),
                accentSoft: Color(0xFFE0E7FF),
              ),
            ],
          ),
        ];
      default:
        return const [];
    }
  }

  static int _gridCross(int viewportCross, int itemCount) {
    if (itemCount <= 1) return 1;
    return math.min(itemCount, viewportCross);
  }

  static double _childAspectRatio(int gridCross, double layoutWidth) {
    if (gridCross >= 3) return 1.12;
    if (gridCross == 1) return 1.82;
    return layoutWidth >= 720 ? 1.05 : 1.02;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(pharmacyProfileProvider);
    return profile.when(
      loading: () => const _HomeLoadingScaffold(),
      error: (e, _) {
        return AppErrorState(
          message: userFacingError(e),
          debugDetails: e.toString(),
          onRetry: () {
            ref.invalidate(pharmacyProfileProvider);
          },
        );
      },
      data: (p) {
        if (p == null) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FormErrorBanner(
                  message: 'No profile is linked to your account. Contact an administrator.',
                ),
              ),
            ),
          );
        }
        final rawName = (p['full_name'] as String? ?? '').trim();
        final first = rawName.isEmpty ? 'there' : rawName.split(RegExp(r'\s+')).first;
        final role = p['role'] as String? ?? '';
        final sections = _sectionsForRole(role);
        final tagline = _roleTagline(role);

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final pad = maxW >= 600 ? 28.0 : (maxW < 360 ? 12.0 : 20.0);
            final viewportCross = maxW < 340 ? 1 : (maxW >= 720 ? 3 : 2);
            final inner = (maxW - 2 * pad).clamp(0.0, double.infinity);
            final cellW = viewportCross <= 1
                ? inner
                : (inner - (viewportCross - 1) * 14) / viewportCross;
            final tileCompact = cellW < 132;

            final slivers = <Widget>[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 20, pad, 12),
                sliver: SliverToBoxAdapter(
                  child: _GreetingHeader(
                    greeting: _greetingLine(),
                    name: first,
                    roleLabel: _roleLabel(role),
                    tagline: tagline,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverToBoxAdapter(
                  child: _PosHeroCard(
                    emphasizeCheckout: role == 'cashier',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.go('/pharmacy/pos');
                    },
                  ),
                ),
              ),
            ];

            if (sections.isEmpty) {
              slivers.add(
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(pad, 24, pad, 40),
                  sliver: const SliverToBoxAdapter(child: _CashierHomeExtras()),
                ),
              );
            } else {
              for (var si = 0; si < sections.length; si++) {
                final section = sections[si];
                final topPad = si == 0 ? 28.0 : 24.0;
                final gridCross = _gridCross(viewportCross, section.actions.length);
                final aspect = _childAspectRatio(gridCross, maxW);

                slivers.add(
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, topPad, pad, 10),
                    sliver: SliverToBoxAdapter(child: _SectionTitle(title: section.title)),
                  ),
                );
                slivers.add(
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridCross,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: aspect,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _ActionTile(
                          action: section.actions[i],
                          compact: tileCompact,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.go(section.actions[i].path);
                          },
                        ),
                        childCount: section.actions.length,
                      ),
                    ),
                  ),
                );
              }
              slivers.add(SliverPadding(padding: EdgeInsets.only(bottom: pad)));
            }

            return CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: slivers,
            );
          },
        );
      },
    );
  }
}

class _HomeSection {
  const _HomeSection({required this.title, required this.actions});
  final String title;
  final List<_HomeAction> actions;
}

class _HomeLoadingScaffold extends StatelessWidget {
  const _HomeLoadingScaffold();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: cs.primary,
              backgroundColor: cs.primaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading your workspace…',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({
    required this.greeting,
    required this.name,
    required this.roleLabel,
    required this.tagline,
  });

  final String greeting;
  final String name;
  final String roleLabel;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting,',
          style: t.textTheme.titleMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          name,
          style: t.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            height: 1.1,
          ),
        ),
        if (roleLabel.isNotEmpty) ...[
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text(
                roleLabel,
                style: t.textTheme.labelLarge?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          tagline,
          style: t.textTheme.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: t.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _PosHeroCard extends StatelessWidget {
  const _PosHeroCard({
    required this.onTap,
    this.emphasizeCheckout = false,
  });

  final VoidCallback onTap;
  final bool emphasizeCheckout;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              cs.primary,
              Color.lerp(cs.primary, const Color(0xFF14532D), 0.35)!,
            ]
          : [
              cs.primary,
              Color.lerp(cs.primary, const Color(0xFF166534), 0.25)!,
            ],
    );

    final title = emphasizeCheckout ? 'Open checkout' : 'Point of sale';
    final headline = emphasizeCheckout ? 'Sell & print receipt' : 'Ring up sales';
    final sub = emphasizeCheckout
        ? 'Cash or mobile — receipt opens after sale.'
        : 'Fast checkout · Cash & mobile';

    return Material(
      elevation: isDark ? 0 : 3,
      shadowColor: cs.primary.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(gradient: gradient),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 18, 22),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.22),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.point_of_sale_rounded,
                    size: 36,
                    color: cs.onPrimary,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.textTheme.labelLarge?.copyWith(
                          color: cs.onPrimary.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.headlineSmall?.copyWith(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sub,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: cs.onPrimary.withValues(alpha: 0.85),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: cs.onPrimary.withValues(alpha: 0.9),
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeAction {
  const _HomeAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.path,
    required this.accent,
    required this.accentSoft,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String path;
  final Color accent;
  final Color accentSoft;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    required this.onTap,
    this.compact = false,
  });

  final _HomeAction action;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final surface = isDark ? cs.surfaceContainerHigh : cs.surface;
    final border = isDark ? cs.outlineVariant.withValues(alpha: 0.35) : cs.outlineVariant.withValues(alpha: 0.5);
    final hPad = compact ? 10.0 : 16.0;
    final vPad = compact ? 12.0 : 16.0;
    final iconBox = compact ? 40.0 : 48.0;
    final iconGlyph = compact ? 22.0 : 26.0;

    return Material(
      color: surface,
      elevation: isDark ? 0 : 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border, width: 1),
          ),
          padding: EdgeInsets.fromLTRB(hPad, vPad, hPad - 2, vPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: iconBox,
                    height: iconBox,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          action.accentSoft,
                          Color.lerp(action.accentSoft, action.accent, isDark ? 0.35 : 0.2)!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: action.accent.withValues(alpha: isDark ? 0.2 : 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      action.icon,
                      size: iconGlyph,
                      color: action.accent,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    size: compact ? 22 : 26,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      fontSize: compact ? 15 : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    action.subtitle,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.25,
                      fontSize: compact ? 11 : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cashier-only: POS is the job; menu for the rest.
class _CashierHomeExtras extends StatelessWidget {
  const _CashierHomeExtras();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          color: cs.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.menu_rounded, size: 28, color: cs.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Need something else?',
                        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Open the menu (top left). Your role is limited to checkout and receipts for security.',
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.receipt_long_rounded, size: 28, color: cs.tertiary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'After a sale, you can open the receipt from POS or from history when your team enables it.',
                    style: t.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
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
