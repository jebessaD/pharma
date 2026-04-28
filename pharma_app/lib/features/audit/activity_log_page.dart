import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_error_state.dart';

class ActivityLogPage extends ConsumerStatefulWidget {
  const ActivityLogPage({super.key});

  @override
  ConsumerState<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends ConsumerState<ActivityLogPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final _search = TextEditingController();
  final _actionType = TextEditingController();
  final _entityType = TextEditingController();
  bool _sortAsc = false;
  int _page = 0;
  static const _pageSize = 100;

  @override
  void dispose() {
    _search.dispose();
    _actionType.dispose();
    _entityType.dispose();
    super.dispose();
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
      var query = Supabase.instance.client
          .from('activity_logs')
          .select()
          .eq('team_id', teamId);
      if (_actionType.text.trim().isNotEmpty) {
        query = query.ilike('action_type', '%${_actionType.text.trim()}%');
      }
      if (_entityType.text.trim().isNotEmpty) {
        query = query.ilike('entity_type', '%${_entityType.text.trim()}%');
      }
      if (_search.text.trim().isNotEmpty) {
        query = query.or(
          'action_type.ilike.%${_search.text.trim()}%,entity_type.ilike.%${_search.text.trim()}%',
        );
      }
      final data = await query
          .order('created_at', ascending: _sortAsc)
          .range(_page * _pageSize, (_page + 1) * _pageSize - 1);
      var rows = List<Map<String, dynamic>>.from(data as List);
      final uidSet = <String>{};
      for (final r in rows) {
        final u = r['user_id'];
        if (u is String && u.isNotEmpty) uidSet.add(u);
      }
      if (uidSet.isNotEmpty) {
        final profs = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name, username')
            .inFilter('id', uidSet.toList());
        final nameById = <String, String>{};
        for (final p in profs as List) {
          final m = Map<String, dynamic>.from(p as Map);
          final id = m['id'] as String?;
          if (id == null) continue;
          final fn = (m['full_name'] as String? ?? '').trim();
          final un = (m['username'] as String? ?? '').trim();
          nameById[id] = fn.isNotEmpty ? fn : (un.isNotEmpty ? un : 'Team member');
        }
        for (final r in rows) {
          final u = r['user_id'] as String?;
          if (u != null && u.isNotEmpty) {
            r['_actor_display'] = nameById[u] ?? 'Unknown user';
          } else {
            r['_actor_display'] = 'System';
          }
        }
      } else {
        for (final r in rows) {
          r['_actor_display'] = 'System';
        }
      }
      setState(() => _rows = rows);
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_rows.isEmpty) return;
    const header = 'created_at,action_type,entity_type,user_name,user_id';
    final lines = _rows
        .map(
          (r) =>
              '${r['created_at'] ?? ''},${r['action_type'] ?? ''},${r['entity_type'] ?? ''},'
              '${r['_actor_display'] ?? ''},${r['user_id'] ?? ''}',
        )
        .toList();
    await Clipboard.setData(ClipboardData(text: ([header, ...lines]).join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity log'),
        actions: [
          IconButton(
            tooltip: 'Sort by date',
            onPressed: () {
              setState(() => _sortAsc = !_sortAsc);
              _load();
            },
            icon: Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward),
          ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
            icon: const Icon(Icons.download_outlined),
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
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No activity recorded yet.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Entries will appear here when actions are logged for your team.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(
                              runSpacing: 8,
                              spacing: 8,
                              children: [
                                SizedBox(
                                  width: 220,
                                  child: TextField(
                                    controller: _search,
                                    decoration: const InputDecoration(labelText: 'Search'),
                                    onSubmitted: (_) => _load(),
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: TextField(
                                    controller: _actionType,
                                    decoration: const InputDecoration(labelText: 'Action type'),
                                    onSubmitted: (_) => _load(),
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: TextField(
                                    controller: _entityType,
                                    decoration: const InputDecoration(labelText: 'Entity type'),
                                    onSubmitted: (_) => _load(),
                                  ),
                                ),
                                FilledButton(onPressed: _load, child: const Text('Apply filters')),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _rows.length,
                              itemBuilder: (context, i) {
                                final r = _rows[i];
                                final actor = r['_actor_display'] as String? ?? '—';
                                return ListTile(
                                  dense: true,
                                  title: Text(r['action_type'] as String? ?? ''),
                                  subtitle: Text(
                                    '${r['created_at']} · ${r['entity_type'] ?? ''} · $actor',
                                  ),
                                );
                              },
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: _page == 0
                                    ? null
                                    : () {
                                        setState(() => _page -= 1);
                                        _load();
                                      },
                                child: const Text('Prev'),
                              ),
                              Text('Page ${_page + 1}'),
                              TextButton(
                                onPressed: _rows.length < _pageSize
                                    ? null
                                    : () {
                                        setState(() => _page += 1);
                                        _load();
                                      },
                                child: const Text('Next'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
    );
  }
}
