import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

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
  List<String> _actionTypeOptions = [];
  List<String> _entityTypeOptions = [];
  String? _selectedActionType;
  String? _selectedEntityType;
  bool _sortAsc = false;
  int _page = 0;
  static const _pageSize = 100;

  String _toHumanLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return 'Unknown';
    final parts = cleaned
        .replaceAll('-', '_')
        .split('_')
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Unknown';
    return parts
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }

  IconData _iconForActionType(String actionType) {
    final value = actionType.toLowerCase();
    if (value.contains('sale')) return Icons.point_of_sale_rounded;
    if (value.contains('stock')) return Icons.inventory_2_rounded;
    if (value.contains('purchase')) return Icons.receipt_long_rounded;
    if (value.contains('create') || value.contains('add')) {
      return Icons.add_circle_outline_rounded;
    }
    if (value.contains('update') || value.contains('edit')) {
      return Icons.edit_note_rounded;
    }
    if (value.contains('delete') || value.contains('remove')) {
      return Icons.delete_outline_rounded;
    }
    if (value.contains('login') || value.contains('signin')) {
      return Icons.login_rounded;
    }
    return Icons.history_rounded;
  }

  @override
  void dispose() {
    _search.dispose();
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
      final filterData = await Supabase.instance.client
          .from('activity_logs')
          .select('action_type, entity_type')
          .eq('team_id', teamId)
          .order('created_at', ascending: false)
          .limit(300);
      final actionOptions = <String>{};
      final entityOptions = <String>{};
      for (final item in filterData as List) {
        final row = Map<String, dynamic>.from(item as Map);
        final action = (row['action_type'] as String? ?? '').trim();
        final entity = (row['entity_type'] as String? ?? '').trim();
        if (action.isNotEmpty) actionOptions.add(action);
        if (entity.isNotEmpty) entityOptions.add(entity);
      }

      final sortedActionOptions = actionOptions.toList()
        ..sort((a, b) => _toHumanLabel(a).compareTo(_toHumanLabel(b)));
      final sortedEntityOptions = entityOptions.toList()
        ..sort((a, b) => _toHumanLabel(a).compareTo(_toHumanLabel(b)));

      var query = Supabase.instance.client
          .from('activity_logs')
          .select()
          .eq('team_id', teamId);
      if (_selectedActionType != null) {
        query = query.eq('action_type', _selectedActionType!);
      }
      if (_selectedEntityType != null) {
        query = query.eq('entity_type', _selectedEntityType!);
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
          nameById[id] = fn.isNotEmpty
              ? fn
              : (un.isNotEmpty ? un : 'Team member');
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
      setState(() {
        _actionTypeOptions = sortedActionOptions;
        _entityTypeOptions = sortedEntityOptions;
        if (_selectedActionType != null &&
            !_actionTypeOptions.contains(_selectedActionType)) {
          _selectedActionType = null;
        }
        if (_selectedEntityType != null &&
            !_entityTypeOptions.contains(_selectedEntityType)) {
          _selectedEntityType = null;
        }
        _rows = rows;
      });
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
              '${formatDdMmYyyyHm(r['created_at'])},${r['action_type'] ?? ''},${r['entity_type'] ?? ''},'
              '${r['_actor_display'] ?? ''},${r['user_id'] ?? ''}',
        )
        .toList();
    await Clipboard.setData(
      ClipboardData(text: ([header, ...lines]).join('\n')),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final hasFilters =
        _search.text.trim().isNotEmpty ||
        _selectedActionType != null ||
        _selectedEntityType != null;
    return Scaffold(
      appBar: pharmacyHubAppBar(
        context,
        title: 'Activity log',
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
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outlineVariant),
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _search,
                                decoration: const InputDecoration(
                                  labelText: 'Search',
                                  prefixIcon: Icon(Icons.search_rounded),
                                ),
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) {
                                  setState(() => _page = 0);
                                  _load();
                                },
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedActionType,
                                decoration: const InputDecoration(
                                  labelText: 'Action type',
                                ),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('All actions'),
                                  ),
                                  ..._actionTypeOptions.map(
                                    (action) => DropdownMenuItem<String>(
                                      value: action,
                                      child: Text(_toHumanLabel(action)),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedActionType = value;
                                    _page = 0;
                                  });
                                },
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedEntityType,
                                decoration: const InputDecoration(
                                  labelText: 'Entity type',
                                ),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('All entities'),
                                  ),
                                  ..._entityTypeOptions.map(
                                    (entity) => DropdownMenuItem<String>(
                                      value: entity,
                                      child: Text(_toHumanLabel(entity)),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedEntityType = value;
                                    _page = 0;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: _load,
                                    icon: const Icon(Icons.tune_rounded),
                                    label: const Text('Apply filters'),
                                  ),
                                  OutlinedButton(
                                    onPressed: hasFilters
                                        ? () {
                                            _search.clear();
                                            setState(() {
                                              _selectedActionType = null;
                                              _selectedEntityType = null;
                                              _page = 0;
                                            });
                                            _load();
                                          }
                                        : null,
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        '${_rows.length} result${_rows.length == 1 ? '' : 's'} on page ${_page + 1}',
                        style: t.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    sliver: SliverList.builder(
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        final actor = r['_actor_display'] as String? ?? '—';
                        final rawAction = r['action_type'] as String? ?? '';
                        final rawEntity = r['entity_type'] as String? ?? '';
                        final actionLabel = _toHumanLabel(rawAction);
                        final entityLabel = _toHumanLabel(rawEntity);
                        final actionIcon = _iconForActionType(rawAction);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: cs.primaryContainer,
                              child: Icon(
                                actionIcon,
                                color: cs.onPrimaryContainer,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              actionLabel,
                              style: t.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${formatDdMmYyyyHm(r['created_at'])}  •  $entityLabel  •  By $actor',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Row(
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
                  ),
                ],
              ),
            ),
    );
  }
}
