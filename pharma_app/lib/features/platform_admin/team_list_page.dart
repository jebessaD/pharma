import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/widgets/app_error_state.dart';

class TeamListPage extends StatefulWidget {
  const TeamListPage({super.key});

  @override
  State<TeamListPage> createState() => _TeamListPageState();
}

class _TeamListPageState extends State<TeamListPage> {
  int _reloadKey = 0;
  String _query = '';

  Future<List<Map<String, dynamic>>> _load() {
    return Supabase.instance.client
        .from('teams')
        .select()
        .order('created_at', ascending: false);
  }

  Future<void> _openNewTeam() async {
    await context.push('/admin/teams/new');
    if (mounted) setState(() => _reloadKey++);
  }

  Future<void> _openTeamDetail(String id) async {
    await context.push('/admin/teams/$id');
    if (mounted) setState(() => _reloadKey++);
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teams'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTeam,
        icon: const Icon(Icons.add),
        label: const Text('New team'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        key: ValueKey(_reloadKey),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return AppErrorState(
              message: userFacingError(snapshot.error!),
              debugDetails: kDebugMode ? snapshot.error.toString() : null,
              onRetry: () {
                setState(() => _reloadKey++);
              },
            );
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return const Center(child: Text('No teams yet. Create one.'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _reloadKey++);
            },
            child: Builder(
              builder: (context) {
                final filtered = rows.where((t) {
                  if (_query.trim().isEmpty) return true;
                  final q = _query.trim().toLowerCase();
                  return ('${t['name'] ?? ''} ${t['status'] ?? ''}').toLowerCase().contains(q);
                }).toList();
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        decoration: const InputDecoration(labelText: 'Search team'),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final t = filtered[i];
                          final name = t['name'] as String? ?? '';
                          final status = t['status'] as String? ?? '';
                          final id = t['id'] as String? ?? '';
                          final active = status == 'active';
                          return ListTile(
                            title: Text(name),
                            subtitle: Text(status),
                            trailing: Chip(
                              label: Text(active ? 'Active' : 'Suspended'),
                              backgroundColor: active
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .errorContainer,
                              labelStyle: TextStyle(
                                color: active
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer
                                    : Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer,
                              ),
                            ),
                            onTap: () => _openTeamDetail(id),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
