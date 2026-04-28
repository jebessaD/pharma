import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/router/matched_drawer_path.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/providers/branch_change_guard_provider.dart';
import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';

class _Dest {
  const _Dest({
    required this.path,
    required this.label,
    required this.icon,
  });

  final String path;
  final String label;
  final IconData icon;
}

class _Section {
  const _Section(this.title, this.dests);
  final String? title;
  final List<_Dest> dests;
}

class PharmacyShell extends ConsumerWidget {
  const PharmacyShell({super.key, required this.child});

  final Widget child;

  static List<_Section> _sectionsForRole(String role) {
    const home = _Dest(
      path: '/pharmacy/home',
      label: 'Home',
      icon: Icons.home_rounded,
    );
    const pos = _Dest(
      path: '/pharmacy/pos',
      label: 'POS',
      icon: Icons.point_of_sale_rounded,
    );
    if (role == 'admin') {
      return [
        const _Section('Operations', [home, pos]),
        const _Section('Catalog & stock', [
          _Dest(
            path: '/pharmacy/medicines',
            label: 'Medicines',
            icon: Icons.medication_rounded,
          ),
          _Dest(
            path: '/pharmacy/stock',
            label: 'Stock',
            icon: Icons.inventory_2_rounded,
          ),
          _Dest(
            path: '/pharmacy/stock-in',
            label: 'Stock in',
            icon: Icons.add_box_rounded,
          ),
          _Dest(
            path: '/pharmacy/stock-movements',
            label: 'Stock movements',
            icon: Icons.swap_vert_rounded,
          ),
          _Dest(
            path: '/pharmacy/expiry',
            label: 'Expiry',
            icon: Icons.event_busy_rounded,
          ),
          _Dest(
            path: '/pharmacy/adjust-stock',
            label: 'Adjust stock',
            icon: Icons.tune_rounded,
          ),
        ]),
        const _Section('Purchasing & alerts', [
          _Dest(
            path: '/pharmacy/notifications',
            label: 'Notifications',
            icon: Icons.notifications_active_rounded,
          ),
          _Dest(
            path: '/pharmacy/suppliers',
            label: 'Suppliers',
            icon: Icons.local_shipping_rounded,
          ),
          _Dest(
            path: '/pharmacy/purchases/new',
            label: 'New purchase',
            icon: Icons.receipt_long_rounded,
          ),
        ]),
        const _Section('Organization', [
          _Dest(
            path: '/pharmacy/organization',
            label: 'Team & branches',
            icon: Icons.apartment_rounded,
          ),
        ]),
        const _Section('Insights', [
          _Dest(
            path: '/pharmacy/dashboard',
            label: 'Overview',
            icon: Icons.pie_chart_rounded,
          ),
          _Dest(
            path: '/pharmacy/reports',
            label: 'Report tables',
            icon: Icons.table_chart_rounded,
          ),
          _Dest(
            path: '/pharmacy/audit',
            label: 'Audit log',
            icon: Icons.history_rounded,
          ),
        ]),
      ];
    }
    if (role == 'pharmacist') {
      return [
        const _Section('Operations', [home, pos]),
        const _Section('Catalog & stock', [
          _Dest(
            path: '/pharmacy/medicines',
            label: 'Medicines',
            icon: Icons.medication_rounded,
          ),
          _Dest(
            path: '/pharmacy/stock',
            label: 'Stock',
            icon: Icons.inventory_2_rounded,
          ),
          _Dest(
            path: '/pharmacy/stock-in',
            label: 'Stock in',
            icon: Icons.add_box_rounded,
          ),
          _Dest(
            path: '/pharmacy/stock-movements',
            label: 'Stock movements',
            icon: Icons.swap_vert_rounded,
          ),
          _Dest(
            path: '/pharmacy/expiry',
            label: 'Expiry',
            icon: Icons.event_busy_rounded,
          ),
          _Dest(
            path: '/pharmacy/adjust-stock',
            label: 'Adjust stock',
            icon: Icons.tune_rounded,
          ),
        ]),
        const _Section('Insights', [
          _Dest(
            path: '/pharmacy/dashboard',
            label: 'Overview',
            icon: Icons.pie_chart_rounded,
          ),
          _Dest(
            path: '/pharmacy/reports',
            label: 'Report tables',
            icon: Icons.table_chart_rounded,
          ),
        ]),
      ];
    }
    return [
      const _Section(null, [home, pos]),
    ];
  }

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) context.go('/login');
  }

  Future<bool> _confirmBranchSwitchIfDirty(BuildContext context, WidgetRef ref) async {
    final guardState = ref.read(branchChangeGuardProvider);
    if (!guardState.hasDirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
          'You have unsaved data in the current branch context. Switching branch will discard it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(branchChangeGuardProvider.notifier).discardAll();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(pharmacyProfileProvider);
    final path = GoRouterState.of(context).uri.path;

    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: AppErrorState(
          message: userFacingError(e),
          debugDetails: e.toString(),
          onRetry: () {
            ref.invalidate(pharmacyProfileProvider);
          },
        ),
      ),
      data: (profile) {
        if (profile == null) {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FormErrorBanner(
                        message:
                            'No profile was found. Ask an administrator to create your access, then try again.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          ref.invalidate(pharmacyProfileProvider);
                        },
                        child: const Text('Retry'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () => _signOut(context),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final teamId = profile['team_id'] as String? ?? '';

        return FutureBuilder<Map<String, dynamic>?>(
          future: Supabase.instance.client
              .from('teams')
              .select('status')
              .eq('id', teamId)
              .maybeSingle(),
          builder: (context, teamSnap) {
            if (teamSnap.connectionState == ConnectionState.done &&
                teamSnap.data != null &&
                teamSnap.data!['status'] == 'suspended') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                context.go('/suspended');
              });
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final branchesAsync = ref.watch(branchesListProvider(teamId));
            final selectedBranch = ref.watch(selectedBranchIdProvider);
            final role = profile['role'] as String? ?? '';
            final sections = _sectionsForRole(role);
            final allPaths = [
              for (final s in sections) for (final d in s.dests) d.path,
            ];
            final matched = matchedDrawerPath(
              path,
              paths: allPaths,
            );

            return branchesAsync.when(
              loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Scaffold(
                body: AppErrorState(
                  message: userFacingError(e),
                  debugDetails: e.toString(),
                  onRetry: () {
                    ref.invalidate(branchesListProvider(teamId));
                  },
                ),
              ),
              data: (branches) {
                if (branches.isNotEmpty &&
                    (selectedBranch == null ||
                        !branches.any((b) => b['id'] == selectedBranch))) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    ref
                        .read(selectedBranchIdProvider.notifier)
                        .setBranch(branches.first['id'] as String);
                  });
                }

                final t = Theme.of(context);
                final cs = t.colorScheme;
                var branchTitle = 'Branch';
                for (final b in branches) {
                  if (b['id'] == selectedBranch) {
                    branchTitle = b['name'] as String? ?? 'Branch';
                    break;
                  }
                }
                final displayName = (profile['full_name'] as String? ?? '').trim();
                final roleLabel = role.isEmpty
                    ? ''
                    : '${role[0].toUpperCase()}${role.substring(1).toLowerCase()}';

                return Scaffold(
                  drawer: Drawer(
                    width: 304,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadiusDirectional.horizontal(
                        end: Radius.circular(20),
                      ),
                    ),
                    backgroundColor: cs.surface,
                    child: SafeArea(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 12),
                        children: [
                          _DrawerHeader(
                            branchTitle: branches.isEmpty ? null : branchTitle,
                            displayName: displayName.isEmpty ? null : displayName,
                            roleLabel: roleLabel.isEmpty ? null : roleLabel,
                          ),
                          ...List.generate(sections.length, (si) {
                            final sec = sections[si];
                            return <Widget>[
                              if (sec.title != null) ...[
                                if (si > 0) const SizedBox(height: 4),
                                _DrawerSectionLabel(title: sec.title!),
                              ],
                              ...sec.dests.map(
                                (d) => _DrawerNavTile(
                                  dest: d,
                                  selected: d.path == matched,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    Navigator.of(context).pop();
                                    if (d.path == path) return;
                                    context.go(d.path);
                                  },
                                ),
                              ),
                            ];
                          }).expand((w) => w),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _DrawerNavTile(
                              dest: const _Dest(
                                path: '',
                                label: 'Sign out',
                                icon: Icons.logout_rounded,
                              ),
                              selected: false,
                              tone: _DrawerTileTone.muted,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).pop();
                                _signOut(context);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        elevation: 0.5,
                        shadowColor: Colors.black.withValues(alpha: 0.08),
                        color: cs.surface,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(2, 2, 10, 2),
                          child: Row(
                            children: [
                              Builder(
                                builder: (ctx) => IconButton(
                                  tooltip: 'Menu',
                                  icon: Icon(Icons.menu_rounded, color: cs.onSurface),
                                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'Pharmacy',
                                  style: t.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (branches.isEmpty)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(end: 8),
                                  child: Text(
                                    'No branches',
                                    style: t.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              else
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        borderRadius: BorderRadius.circular(12),
                                        value: selectedBranch != null &&
                                                branches.any(
                                                  (b) => b['id'] == selectedBranch,
                                                )
                                            ? selectedBranch
                                            : null,
                                        hint: Text(
                                          'Branch',
                                          style: t.textTheme.bodyMedium?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                        items: branches
                                            .map(
                                              (b) => DropdownMenuItem<String>(
                                                value: b['id'] as String,
                                                child: Text(
                                                  b['name'] as String? ?? '',
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) async {
                                          if (v != null) {
                                            final current = selectedBranch;
                                            if (current == v) return;
                                            final proceed =
                                                await _confirmBranchSwitchIfDirty(
                                              context,
                                              ref,
                                            );
                                            if (!proceed) return;
                                            await ref
                                                .read(
                                                  selectedBranchIdProvider.notifier,
                                                )
                                                .setBranch(v);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: child),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    this.displayName,
    this.roleLabel,
    this.branchTitle,
  });

  final String? displayName;
  final String? roleLabel;
  final String? branchTitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final topPad = MediaQuery.paddingOf(context).top > 0 ? 8.0 : 16.0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: EdgeInsets.fromLTRB(18, topPad + 8, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer,
            Color.lerp(cs.primaryContainer, cs.primary, 0.12)!,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.local_pharmacy_rounded,
              size: 30,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Pharmacy',
            style: t.textTheme.titleLarge?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (displayName != null) ...[
            const SizedBox(height: 4),
            Text(
              displayName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.titleSmall?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (roleLabel != null) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(
                  roleLabel!,
                  style: t.textTheme.labelMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          if (branchTitle != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.storefront_rounded,
                  size: 16,
                  color: cs.onPrimaryContainer.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    branchTitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.9),
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: t.textTheme.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DrawerTileTone { normal, muted }

class _DrawerNavTile extends StatelessWidget {
  const _DrawerNavTile({
    required this.dest,
    required this.selected,
    required this.onTap,
    this.tone = _DrawerTileTone.normal,
  });

  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;
  final _DrawerTileTone tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final muted = tone == _DrawerTileTone.muted;
    final iconBg = selected
        ? cs.primary.withValues(alpha: 0.18)
        : (muted ? cs.surfaceContainerHighest : cs.surfaceContainerHighest.withValues(alpha: 0.85));
    final iconFg = selected
        ? cs.primary
        : (muted ? cs.onSurfaceVariant : cs.onSurfaceVariant);
    final tileBg = selected ? cs.primaryContainer.withValues(alpha: 0.45) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: tileBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(dest.icon, size: 22, color: iconFg),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    dest.label,
                    style: t.textTheme.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: cs.primary.withValues(alpha: 0.8),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
