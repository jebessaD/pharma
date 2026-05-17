import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/providers/post_pharmacy_sign_out.dart';
import '../../core/router/matched_drawer_path.dart';
import '../../core/shared_preferences_provider.dart';
import '../../core/providers/platform_messages_provider.dart';
import '../../core/providers/team_shell_meta_provider.dart';
import '../../core/providers/youtube_onboarding_provider.dart';
import '../../core/widgets/youtube_brand_icon.dart';
import '../onboarding/youtube_onboarding_dialog.dart';
import '../onboarding/youtube_onboarding_host.dart';
import '../../core/providers/sync_status_provider.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/providers/branch_change_guard_provider.dart';
import '../pos/offline/pos_offline_providers.dart';
import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart'
    show isBranchLocked, selectedBranchIdProvider;

class _Dest {
  const _Dest({required this.path, required this.label, required this.icon});

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

  /// Login email for owners; staff `username`, else display name, else email.
  static String? accountIdentityLine(Map<String, dynamic> profile) {
    final role = (profile['role'] as String? ?? '').trim().toLowerCase();
    final auth = Supabase.instance.client.auth.currentUser;
    final email = (auth?.email ?? '').trim();
    final username = (profile['username'] as String? ?? '').trim();
    final fullName = (profile['full_name'] as String? ?? '').trim();
    if (role == 'owner') {
      if (email.isNotEmpty) return email;
      if (username.isNotEmpty) return username;
      if (fullName.isNotEmpty) return fullName;
      return null;
    }
    if (username.isNotEmpty) return username;
    if (fullName.isNotEmpty) return fullName;
    if (email.isNotEmpty) return email;
    return null;
  }

  static List<_Section> _sectionsForRole(String role) {
    const home = _Dest(
      path: '/pharmacy',
      label: 'Home',
      icon: Icons.home_rounded,
    );
    const pos = _Dest(
      path: '/pharmacy/pos',
      label: 'Sell',
      icon: Icons.point_of_sale_rounded,
    );
    if (role == 'admin' || role == 'owner') {
      return [
        const _Section('Operations', [home, pos]),
        const _Section('Insights', [
          _Dest(
            path: '/pharmacy/dashboard',
            label: 'Overview',
            icon: Icons.pie_chart_rounded,
          ),
        ]),
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
            path: '/pharmacy/expiry',
            label: 'Expiry',
            icon: Icons.event_busy_rounded,
          ),
          _Dest(
            path: '/pharmacy/stock-movements',
            label: 'Stock history',
            icon: Icons.swap_vert_rounded,
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
            path: '/pharmacy/purchases',
            label: 'Purchases',
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
        const _Section('Insights & reports', [
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
        const _Section('Support', [
          _Dest(
            path: '/pharmacy/contact',
            label: 'Contact us',
            icon: Icons.chat_bubble_outline_rounded,
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
            path: '/pharmacy/expiry',
            label: 'Expiry',
            icon: Icons.event_busy_rounded,
          ),
          _Dest(
            path: '/pharmacy/stock-movements',
            label: 'Stock history',
            icon: Icons.swap_vert_rounded,
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
        const _Section('Support', [
          _Dest(
            path: '/pharmacy/contact',
            label: 'Contact us',
            icon: Icons.chat_bubble_outline_rounded,
          ),
        ]),
      ];
    }
    return [
      const _Section(null, [
        home,
        pos,
        _Dest(
          path: '/pharmacy/contact',
          label: 'Contact us',
          icon: Icons.chat_bubble_outline_rounded,
        ),
      ]),
    ];
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final prevTeamId = container.read(pharmacyProfileProvider).value?['team_id']
        as String?;
    final prefs = container.read(sharedPreferencesProvider);
    await Supabase.instance.client.auth.signOut();
    schedulePharmacySignOutCleanup(
      container: container,
      prefs: prefs,
      teamId: prevTeamId,
    );
  }

  Future<bool> _confirmBranchSwitchIfDirty(
    BuildContext context,
    WidgetRef ref,
  ) async {
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
    ref.watch(posSyncServiceProvider);
    final profileAsync = ref.watch(pharmacyProfileProvider);
    final isOnline = ref.watch(connectivityProvider).value ?? true;
    final syncStatus = ref.watch(syncStatusProvider);
    final path = GoRouterState.of(context).uri.path;

    return profileAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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
                        onPressed: () => _signOut(context, ref),
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

        ref.listen(teamShellMetaProvider(teamId), (prev, next) {
          final meta = next.asData?.value;
          if (meta != null && meta['status'] == 'suspended') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              context.go('/suspended');
            });
          }
        });

        // Must call ref.listen unconditionally (same count every build).
        // Branch-locked roles get branch from profile; skip auto-pick from list.
        ref.listen(branchesListProvider(teamId), (prev, next) {
          next.whenData((branches) {
            final p = ref.read(pharmacyProfileProvider).asData?.value;
            final userRole = (p?['role'] as String? ?? '').trim().toLowerCase();
            if (isBranchLocked(userRole)) return;
            if (branches.isEmpty) return;
            if (Supabase.instance.client.auth.currentUser == null) return;
            final selected = ref.read(selectedBranchIdProvider);
            final ok =
                selected != null && branches.any((b) => b['id'] == selected);
            if (!ok) {
              final id = branches.first['id'] as String;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                if (Supabase.instance.client.auth.currentUser == null) return;
                ref.read(selectedBranchIdProvider.notifier).setBranch(id);
              });
            }
          });
        });

        return ref.watch(teamShellMetaProvider(teamId)).when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (e, st) => Scaffold(
            body: AppErrorState(
              message: userFacingError(e),
              debugDetails: e.toString(),
              onRetry: () {
                ref.invalidate(teamShellMetaProvider(teamId));
              },
            ),
          ),
          data: (teamSnap) {
            if (teamSnap['status'] == 'suspended') {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final branchesAsync = ref.watch(branchesListProvider(teamId));
            final selectedBranch = ref.watch(selectedBranchIdProvider);
            final role = profile['role'] as String? ?? '';
            final branchLocked = isBranchLocked(role);
            final sections = _sectionsForRole(role);
            final allPaths = [
              for (final s in sections)
                for (final d in s.dests) d.path,
            ];
            final matched = matchedDrawerPath(path, paths: allPaths);

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
                final opsSnap = ref.watch(platformOpsProvider).asData?.value;
                final banner = opsSnap?.bannerMessage;

                final t = Theme.of(context);
                final cs = t.colorScheme;
                var branchTitle = 'Branch';
                for (final b in branches) {
                  if (b['id'] == selectedBranch) {
                    branchTitle = b['name'] as String? ?? 'Branch';
                    break;
                  }
                }
                final pharmacyName =
                    (teamSnap['pharmacy_name'] as String? ?? '').trim();
                final shellTitle = pharmacyName.isEmpty
                    ? 'Pharmacy'
                    : pharmacyName;
                final roleLabel = role.isEmpty
                    ? ''
                    : '${role[0].toUpperCase()}${role.substring(1).toLowerCase()}';

                final accountIdentity =
                    PharmacyShell.accountIdentityLine(profile);
                final youtubeOnboarding =
                    ref.watch(youtubeOnboardingConfigProvider).value;

                final sessionKey =
                    '${profile['id'] as String? ?? ''}_$teamId';
                return Scaffold(
                  key: ValueKey<String>('pharmacy_shell_$sessionKey'),
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
                            key: ValueKey<String>('drawer_header_$sessionKey'),
                            branchTitle: branches.isEmpty ? null : branchTitle,
                            displayName: shellTitle,
                            roleLabel: roleLabel.isEmpty ? null : roleLabel,
                            accountIdentity: accountIdentity,
                            teamId: teamId,
                            selectedBranchId: selectedBranch,
                            notificationsSelected:
                                matched == '/pharmacy/notifications',
                            platformMessagesSelected:
                                matched == '/pharmacy/platform-messages',
                            onOpenNotifications: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).pop();
                              if (path == '/pharmacy/notifications') return;
                              context.go('/pharmacy/notifications');
                            },
                            onOpenPlatformMessages: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).pop();
                              if (path == '/pharmacy/platform-messages') return;
                              context.go('/pharmacy/platform-messages');
                            },
                          ),
                          ...List.generate(sections.length, (si) {
                            final sec = sections[si];
                            final showHowToUse =
                                youtubeOnboarding?.isDrawerActive == true;
                            return <Widget>[
                              if (sec.title != null) ...[
                                if (si > 0) const SizedBox(height: 4),
                                _DrawerSectionLabel(title: sec.title!),
                              ],
                              ...sec.dests.expand((d) {
                                final tiles = <Widget>[
                                  _DrawerNavTile(
                                    dest: d,
                                    selected: d.path == matched,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      Navigator.of(context).pop();
                                      if (d.path == path) return;
                                      context.go(d.path);
                                    },
                                  ),
                                ];
                                if (d.path == '/pharmacy/contact' &&
                                    showHowToUse) {
                                  tiles.add(
                                    _DrawerNavTile(
                                      dest: const _Dest(
                                        path: '',
                                        label: 'How to use',
                                        icon: Icons
                                            .play_circle_outline_rounded,
                                      ),
                                      leading: const YoutubeBrandIcon(
                                        size: 26,
                                      ),
                                      selected: false,
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        Navigator.of(context).pop();
                                        openYoutubeTutorial(
                                          context,
                                          url: youtubeOnboarding!.url,
                                        );
                                      },
                                    ),
                                  );
                                }
                                return tiles;
                              }),
                            ];
                          }).expand((w) => w),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Divider(
                              height: 1,
                              color: cs.outlineVariant.withValues(alpha: 0.6),
                            ),
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
                                _signOut(context, ref);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  body: SafeArea(
                    child: Column(
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
                                    icon: Icon(
                                      Icons.menu_rounded,
                                      color: cs.onSurface,
                                    ),
                                    onPressed: () =>
                                        Scaffold.of(ctx).openDrawer(),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    shellTitle,
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
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 8,
                                    ),
                                    child: Text(
                                      'No branches',
                                      style: t.textTheme.labelSmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                else if (branchLocked)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 8,
                                    ),
                                    child: Text(
                                      branchTitle,
                                      style: t.textTheme.bodyMedium?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                else
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 180,
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          key: ValueKey<String>(
                                            'branch_dd_$teamId',
                                          ),
                                          isExpanded: true,
                                          isDense: true,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          value:
                                              selectedBranch != null &&
                                                  branches.any(
                                                    (b) =>
                                                        b['id'] ==
                                                        selectedBranch,
                                                  )
                                              ? selectedBranch
                                              : null,
                                          hint: Text(
                                            'Branch',
                                            style: t.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                          ),
                                          items: branches
                                              .map(
                                                (b) => DropdownMenuItem<String>(
                                                  value: b['id'] as String,
                                                  child: Text(
                                                    b['name'] as String? ?? '',
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                                                    selectedBranchIdProvider
                                                        .notifier,
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
                        if (!isOnline || syncStatus.pendingCount > 0)
                          Material(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.sync_problem_rounded,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      !isOnline
                                          ? 'Offline - data will sync when internet returns.'
                                          : 'Pending sync: ${syncStatus.pendingCount}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (banner != null)
                          MaterialBanner(
                            backgroundColor: banner['severity'] == 'critical'
                                ? cs.errorContainer
                                    .withValues(alpha: 0.45)
                                : cs.tertiaryContainer
                                    .withValues(alpha: 0.55),
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  banner['title'] as String? ?? '',
                                  style: t.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (((banner['body'] as String?) ?? '')
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    (banner['body'] as String?)!.trim(),
                                    style: t.textTheme.bodySmall?.copyWith(
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () async {
                                  final id = banner['id'] as String?;
                                  if (id != null) {
                                    await markPlatformMessageRead(ref, id);
                                  }
                                },
                                child: const Text('Dismiss'),
                              ),
                            ],
                          ),
                        Expanded(
                          child: YoutubeOnboardingHost(child: child),
                        ),
                      ],
                    ),
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

final _drawerUnreadAlertsCountProvider = FutureProvider.family
    .autoDispose<int, ({String teamId, String? branchId})>((ref, params) async {
      final query = Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('team_id', params.teamId)
          .eq('is_read', false);
      if (params.branchId == null) {
        query.isFilter('branch_id', null);
      } else {
        query.or('branch_id.is.null,branch_id.eq.${params.branchId}');
      }
      final result = await query;
      return (result as List).length;
    });

class _DrawerHeader extends ConsumerWidget {
  const _DrawerHeader({
    super.key,
    this.displayName,
    this.roleLabel,
    this.accountIdentity,
    this.branchTitle,
    required this.teamId,
    required this.selectedBranchId,
    required this.onOpenNotifications,
    required this.notificationsSelected,
    required this.onOpenPlatformMessages,
    required this.platformMessagesSelected,
  });

  final String? displayName;
  final String? roleLabel;
  final String? accountIdentity;
  final String? branchTitle;
  final String teamId;
  final String? selectedBranchId;
  final VoidCallback onOpenNotifications;
  final bool notificationsSelected;
  final VoidCallback onOpenPlatformMessages;
  final bool platformMessagesSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final topPad = MediaQuery.paddingOf(context).top > 0 ? 8.0 : 16.0;
    final primaryName = (displayName ?? '').trim();
    final showProfileName = primaryName.isNotEmpty;
    final headerTitle = showProfileName ? primaryName : 'Pharmacy';
    final unreadCountAsync = ref.watch(
      _drawerUnreadAlertsCountProvider((
        teamId: teamId,
        branchId: selectedBranchId,
      )),
    );
    final unreadCount = unreadCountAsync.asData?.value ?? 0;
    final showUnreadBadge = unreadCount > 0;
    final platformOps = ref.watch(platformOpsProvider).asData?.value;
    final platformUnread = platformOps?.unreadCount ?? 0;
    final showPlatformBadge = platformUnread > 0;

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
          Row(
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
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Notifications',
                        style: IconButton.styleFrom(
                          backgroundColor: notificationsSelected
                              ? cs.primary.withValues(alpha: 0.2)
                              : cs.surface.withValues(alpha: 0.55),
                          foregroundColor: notificationsSelected
                              ? cs.primary
                              : cs.onPrimaryContainer,
                        ),
                        onPressed: onOpenNotifications,
                        icon: const Icon(Icons.notifications_rounded),
                      ),
                      if (showUnreadBadge)
                        PositionedDirectional(
                          top: -4,
                          end: -4,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.error,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              textAlign: TextAlign.center,
                              style: t.textTheme.labelSmall?.copyWith(
                                color: cs.onError,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Announcements',
                        style: IconButton.styleFrom(
                          backgroundColor: platformMessagesSelected
                              ? cs.primary.withValues(alpha: 0.2)
                              : cs.surface.withValues(alpha: 0.55),
                          foregroundColor: platformMessagesSelected
                              ? cs.primary
                              : cs.onPrimaryContainer,
                        ),
                        onPressed: onOpenPlatformMessages,
                        icon: const Icon(Icons.campaign_rounded),
                      ),
                      if (showPlatformBadge)
                        PositionedDirectional(
                          top: -4,
                          end: -4,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.tertiary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              platformUnread > 99 ? '99+' : '$platformUnread',
                              textAlign: TextAlign.center,
                              style: t.textTheme.labelSmall?.copyWith(
                                color: cs.onTertiary,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            headerTitle,
            style: t.textTheme.titleLarge?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (roleLabel != null) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
          if ((accountIdentity ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  size: 18,
                  color: cs.onPrimaryContainer.withValues(alpha: 0.88),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    accountIdentity!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
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
    this.leading,
  });

  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;
  final _DrawerTileTone tone;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final muted = tone == _DrawerTileTone.muted;
    final iconBg = selected
        ? cs.primary.withValues(alpha: 0.18)
        : (muted
              ? cs.surfaceContainerHighest
              : cs.surfaceContainerHighest.withValues(alpha: 0.85));
    final iconFg = selected
        ? cs.primary
        : (muted ? cs.onSurfaceVariant : cs.onSurfaceVariant);
    final tileBg = selected
        ? cs.primaryContainer.withValues(alpha: 0.45)
        : Colors.transparent;

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
                  alignment: Alignment.center,
                  child: leading ??
                      Icon(dest.icon, size: 22, color: iconFg),
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
