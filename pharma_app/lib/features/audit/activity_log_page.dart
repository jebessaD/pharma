import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/utils/csv_export.dart';
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
  Timer? _searchDebounce;
  static const _pageSize = 50;
  bool _hasMore = false;

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

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({bool append = false}) async {
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
      if (_search.text.trim().isNotEmpty) {
        final q = _search.text.trim();
        query = query.or('action_type.ilike.%$q%,entity_type.ilike.%$q%');
      }
      final offset = append ? _rows.length : 0;
      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + _pageSize - 1);
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
          r['_actor_display'] = u != null && u.isNotEmpty
              ? (nameById[u] ?? 'Unknown user')
              : 'System';
        }
      } else {
        for (final r in rows) {
          r['_actor_display'] = 'System';
        }
      }
      setState(() {
        if (append) {
          _rows = [..._rows, ...rows];
        } else {
          _rows = rows;
        }
        _hasMore = rows.length >= _pageSize;
      });
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
  }

  Future<void> _exportCsv() async {
    if (_rows.isEmpty) return;
    final header = [
      'created_at',
      'action_type',
      'entity_type',
      'user_name',
      'user_id',
    ].join(',');
    final lines = _rows
        .map(
          (r) => [
            csvEscapeField(formatDdMmYyyyHm(r['created_at'])),
            csvEscapeField(r['action_type']),
            csvEscapeField(r['entity_type']),
            csvEscapeField(r['_actor_display']),
            csvEscapeField(r['user_id']),
          ].join(','),
        )
        .toList();
    final text = [header, ...lines].join('\n');
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV copied to clipboard')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not copy CSV to clipboard.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Scaffold(
      appBar: pharmacyHubAppBar(
        context,
        title: 'Activity log',
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _rows.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: _loading && _rows.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? AppErrorState(message: _error!, onRetry: _load)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search activity…',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 22),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () {
                                _search.clear();
                                _load();
                              },
                            ),
                      filled: true,
                      fillColor: cs.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.65),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.65),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.primary, width: 1.5),
                      ),
                    ),
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(),
                  ),
                ),
                Expanded(
                  child: _rows.isEmpty
                      ? Center(
                          child: Text(
                            'No activity recorded yet.',
                            style: t.textTheme.titleMedium,
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                            itemCount: _rows.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i >= _rows.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: OutlinedButton(
                                    onPressed: _loading
                                        ? null
                                        : () => _load(append: true),
                                    child: _loading
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Load more'),
                                  ),
                                );
                              }
                              final r = _rows[i];
                              final actor =
                                  r['_actor_display'] as String? ?? '—';
                              final actionLabel = _toHumanLabel(
                                r['action_type'] as String? ?? '',
                              );
                              final entityLabel = _toHumanLabel(
                                r['entity_type'] as String? ?? '',
                              );
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: cs.outlineVariant.withValues(alpha: 0.55),
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 4,
                                  ),
                                  title: Text(
                                    actionLabel,
                                    style: t.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${formatDdMmYyyyHm(r['created_at'])}  •  $entityLabel  •  $actor',
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
