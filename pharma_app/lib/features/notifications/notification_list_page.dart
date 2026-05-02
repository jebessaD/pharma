import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';
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
        params: {
          'p_team_id': teamId,
          'p_branch_id': branchId,
        },
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alerts refreshed')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
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
        return cs.tertiary;
      case 'near_expiry':
      case 'near_expiry_30':
        return cs.secondary;
      case 'near_expiry_90':
        return cs.primary;
      case 'expired':
        return cs.error;
      default:
        return cs.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      selectedBranchIdProvider,
      (previous, next) => _load(),
    );
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: pharmacyHubAppBar(
        context,
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
              child: Icon(Icons.done_all_rounded, color: cs.onSurface),
            ),
          ),
          IconButton(
            tooltip: 'Refresh alerts',
            onPressed: _loading ? null : _refreshAlerts,
            icon: Icon(Icons.refresh_rounded, color: cs.onSurface),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : _error != null
          ? AppErrorState(
              message: _error!,
              onRetry: _load,
            )
          : _rows.isEmpty
          ? _EmptyNotificationsState(colorScheme: cs, textTheme: t.textTheme)
          : RefreshIndicator(
              onRefresh: _load,
              color: cs.primary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant),
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  FilterChip(
                                    label: const Text('Unread only'),
                                    selected: _showUnreadOnly,
                                    showCheckmark: false,
                                    avatar: Icon(
                                      Icons.mark_email_unread_outlined,
                                      size: 18,
                                      color: _showUnreadOnly
                                          ? cs.onSecondaryContainer
                                          : cs.onSurfaceVariant,
                                    ),
                                    onSelected: (v) =>
                                        setState(() => _showUnreadOnly = v),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SearchBar(
                                hintText: 'Search title or message',
                                leading: Icon(
                                  Icons.search_rounded,
                                  color: cs.onSurfaceVariant,
                                ),
                                trailing: [
                                  if (_query.isNotEmpty)
                                    IconButton(
                                      tooltip: 'Clear',
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      onPressed: () {
                                        _searchCtl.clear();
                                        setState(() => _query = '');
                                      },
                                    ),
                                ],
                                controller: _searchCtl,
                                onChanged: (v) => setState(() => _query = v),
                                elevation: WidgetStateProperty.all(0),
                                backgroundColor: WidgetStateProperty.all(
                                  cs.surface.withValues(alpha: 0.95),
                                ),
                                side: WidgetStateProperty.all(
                                  BorderSide(
                                    color: cs.outline.withValues(alpha: 0.22),
                                  ),
                                ),
                                shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: _filteredRows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
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
                            color: read
                                ? cs.surface
                                : cs.primaryContainer.withValues(alpha: 0.22),
                            elevation: 0,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: read
                                  ? null
                                  : () => _markRead(n['id'] as String),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: read
                                        ? cs.outlineVariant.withValues(
                                            alpha: 0.65,
                                          )
                                        : accent.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    14,
                                    10,
                                    14,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          _iconForType(type),
                                          color: accent,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    n['title'] as String? ?? '',
                                                    style: t.textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                      fontWeight: read
                                                          ? FontWeight.w600
                                                          : FontWeight.w700,
                                                      letterSpacing: -0.2,
                                                    ),
                                                  ),
                                                ),
                                                if (!read)
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    margin: const EdgeInsets
                                                        .only(
                                                      top: 6,
                                                      left: 6,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: cs.primary,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              n['message'] as String? ?? '',
                                              style: t.textTheme.bodyMedium
                                                  ?.copyWith(
                                                color: cs.onSurface
                                                    .withValues(alpha: 0.78),
                                                height: 1.35,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              timeStr,
                                              style: t.textTheme.labelMedium
                                                  ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!read)
                                        IconButton(
                                          tooltip: 'Mark read',
                                          icon: Icon(
                                            Icons.check_circle_outline_rounded,
                                            color: cs.primary,
                                          ),
                                          onPressed: () => _markRead(
                                            n['id'] as String,
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
