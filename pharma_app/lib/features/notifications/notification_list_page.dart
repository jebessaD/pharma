import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/layout/layout_density.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/pharmacy_hub_list.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

class NotificationListPage extends ConsumerStatefulWidget {
  const NotificationListPage({super.key});

  @override
  ConsumerState<NotificationListPage> createState() =>
      _NotificationListPageState();
}

class _NotificationListPageState extends ConsumerState<NotificationListPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  bool _showUnreadOnly = false;
  String _query = '';
  final _searchCtl = TextEditingController();

  List<Map<String, dynamic>> get _filteredRows {
    return _rows.where((n) {
      final read = n['is_read'] as bool? ?? false;
      if (_showUnreadOnly && read) return false;
      if (_query.trim().isEmpty) return true;
      return ('${n['title'] ?? ''} ${n['message'] ?? ''}')
          .toLowerCase()
          .contains(_query.trim().toLowerCase());
    }).toList();
  }

  int get _unreadCount =>
      _rows.where((n) => (n['is_read'] as bool? ?? false) == false).length;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await ref.read(pharmacyProfileProvider.future);
    final teamId = profile?['team_id'] as String?;
    if (!mounted) return;
    if (teamId == null) {
      setState(() {
        _loading = false;
        _error = 'No team';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branchId = ref.read(selectedBranchIdProvider);
      final data = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('team_id', teamId)
          .order('created_at', ascending: false)
          .limit(200);
      final rows = List<Map<String, dynamic>>.from(data as List).where((n) {
        final b = n['branch_id'] as String?;
        if (branchId == null) return b == null;
        return b == null || b == branchId;
      }).toList();
      setState(() => _rows = rows);
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshAlerts() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch');
      return;
    }
    try {
      await Supabase.instance.client.rpc(
        'refresh_alerts',
        params: {'p_team_id': teamId, 'p_branch_id': branchId},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Alerts refreshed')));
      }
    } catch (e) {
      setState(() => _error = userFacingError(e));
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
  }

  Future<void> _markAllRead() async {
    final unreadIds = _rows
        .where((n) => (n['is_read'] as bool? ?? false) == false)
        .map((n) => n['id'] as String)
        .toList();
    if (unreadIds.isEmpty) return;
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .inFilter('id', unreadIds);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
  }

  static IconData _iconForType(String? type) {
    switch (type) {
      case 'low_stock':
        return Icons.inventory_2_outlined;
      case 'near_expiry':
      case 'near_expiry_30':
        return Icons.event_note_outlined;
      case 'near_expiry_90':
        return Icons.calendar_month_outlined;
      case 'expired':
        return Icons.event_busy_rounded;
      default:
        return Icons.notifications_active_outlined;
    }
  }

  static Color _accentForType(String? type, ColorScheme cs) {
    switch (type) {
      case 'low_stock':
        return cs.brightness == Brightness.dark
            ? const Color(0xFFFBBF24)
            : const Color(0xFFD97706);
      case 'near_expiry':
      case 'near_expiry_30':
        return cs.brightness == Brightness.dark
            ? const Color(0xFFF59E0B)
            : const Color(0xFFB45309);
      case 'near_expiry_90':
        return cs.brightness == Brightness.dark
            ? const Color(0xFFFBBF24)
            : const Color(0xFFD97706);
      case 'expired':
        return cs.error;
      default:
        return cs.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(selectedBranchIdProvider, (previous, next) => _load());
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final density = context.layoutDensity;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: HubPageHeader(
              title: 'Notifications',
              actions: [
                IconButton(
                  tooltip: 'Mark all read',
                  onPressed: _loading || _unreadCount == 0 ? null : _markAllRead,
                  icon: Badge(
                    isLabelVisible: _unreadCount > 0,
                    label: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(fontSize: 10),
                    ),
                    child: const Icon(Icons.done_all_rounded),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh alerts',
                  onPressed: _loading ? null : _refreshAlerts,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : _error != null
          ? AppErrorState(message: _error!, onRetry: _load)
          : _rows.isEmpty
          ? _EmptyNotificationsState(colorScheme: cs, textTheme: t.textTheme)
          : RefreshIndicator(
              onRefresh: _load,
              color: cs.primary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: PharmacyHubFilterSection(
                      searchController: _searchCtl,
                      searchHint: 'Search notifications',
                      onSearchChanged: (v) => setState(() => _query = v),
                      countLabel:
                          'Showing ${_filteredRows.length} · $_unreadCount unread',
                      countTrailing: FilterChip(
                        label: const Text('Unread only'),
                        selected: _showUnreadOnly,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (v) => setState(() => _showUnreadOnly = v),
                      ),
                    ),
                  ),
                  if (_filteredRows.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.65,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No matching notifications',
                                style: t.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try another search or turn off Unread only.',
                                style: t.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: pharmacyHubListPadding(context, bottom: 20),
                      sliver: SliverList.separated(
                        itemCount: _filteredRows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final n = _filteredRows[i];
                          final read = n['is_read'] as bool? ?? false;
                          final type = n['type'] as String?;
                          final accent = _accentForType(type, cs);
                          final created = n['created_at'];
                          final timeStr = created != null
                              ? formatDdMmYyyyHm(created)
                              : '';

                          return Material(
                            color: cs.surface,
                            elevation: 0,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: read
                                  ? null
                                  : () => _markRead(n['id'] as String),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                ),
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        width: read ? 0 : 4,
                                        color: accent,
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            density.listCardPaddingH,
                                            density.listCardPaddingV,
                                            density.listCardPaddingH,
                                            density.listCardPaddingV,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: density.iconBoxSize,
                                                height: density.iconBoxSize,
                                                decoration: BoxDecoration(
                                                  color: cs
                                                      .surfaceContainerHighest
                                                      .withValues(alpha: 0.7),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    density.v(
                                                      compact: 10,
                                                      standard: 10,
                                                      comfortable: 12,
                                                    ),
                                                  ),
                                                ),
                                                child: Icon(
                                                  _iconForType(type),
                                                  color: accent,
                                                  size: density.v(
                                                    compact: 20,
                                                    standard: 20,
                                                    comfortable: 22,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: density.v(
                                                  compact: 12,
                                                  standard: 12,
                                                  comfortable: 14,
                                                ),
                                              ),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      n['title'] as String? ??
                                                          '',
                                                      style: (density.isCompact
                                                              ? t.textTheme
                                                                  .titleSmall
                                                              : t.textTheme
                                                                  .titleMedium)
                                                          ?.copyWith(
                                                        fontWeight: read
                                                            ? FontWeight.w600
                                                            : FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      n['message'] as String? ??
                                                          '',
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: (density.isCompact
                                                              ? t.textTheme
                                                                  .bodySmall
                                                              : t.textTheme
                                                                  .bodyMedium)
                                                          ?.copyWith(
                                                        color: cs
                                                            .onSurfaceVariant,
                                                        height: 1.35,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      timeStr,
                                                      style: t
                                                          .textTheme.labelSmall
                                                          ?.copyWith(
                                                            color: cs
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNotificationsState extends StatelessWidget {
  const _EmptyNotificationsState({
    required this.colorScheme,
    required this.textTheme,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'You’re all caught up',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Team alerts for stock and expiry will show up here. Pull down to refresh or use Refresh alerts when a branch is selected.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
