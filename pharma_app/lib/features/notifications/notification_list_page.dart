import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/app_error_state.dart';

class NotificationListPage extends ConsumerStatefulWidget {
  const NotificationListPage({super.key});

  @override
  ConsumerState<NotificationListPage> createState() => _NotificationListPageState();
}

class _NotificationListPageState extends ConsumerState<NotificationListPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  bool _showUnreadOnly = false;
  String _query = '';

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

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
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
      final data = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('team_id', teamId)
          .order('created_at', ascending: false)
          .limit(100);
      setState(() => _rows = List<Map<String, dynamic>>.from(data as List));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alerts refreshed')));
      }
    } catch (e) {
      setState(() => _error = userFacingError(e));
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await Supabase.instance.client.from('notifications').update({'is_read': true}).eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
          .update({'is_read': true}).inFilter('id', unreadIds);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _markAllRead,
            child: const Text('Mark all read'),
          ),
          TextButton(
            onPressed: _loading ? null : _refreshAlerts,
            child: const Text('Refresh alerts'),
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
              : _rows.isEmpty
                  ? const Center(child: Text('No notifications'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                FilterChip(
                                  label: const Text('Unread only'),
                                  selected: _showUnreadOnly,
                                  onSelected: (v) => setState(() => _showUnreadOnly = v),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    decoration: const InputDecoration(labelText: 'Search'),
                                    onChanged: (value) => setState(() => _query = value),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                        itemCount: _filteredRows.length,
                        itemBuilder: (context, i) {
                          final n = _filteredRows[i];
                          final read = n['is_read'] as bool? ?? false;
                          return ListTile(
                            title: Text(n['title'] as String? ?? ''),
                            subtitle: Text(n['message'] as String? ?? ''),
                            trailing: read
                                ? null
                                : TextButton(
                                    onPressed: () => _markRead(n['id'] as String),
                                    child: const Text('Read'),
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
