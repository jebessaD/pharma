import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_error_state.dart';

class BranchListPage extends ConsumerStatefulWidget {
  const BranchListPage({super.key, this.embedInHub = false});

  /// When true, omits [Scaffold] / FAB (used inside [OrganizationHubPage]).
  final bool embedInHub;

  @override
  ConsumerState<BranchListPage> createState() => _BranchListPageState();
}

class _BranchListPageState extends ConsumerState<BranchListPage> {
  String _query = '';

  Future<void> _openBranchRoute(String location) async {
    await context.push(location);
    if (!mounted) return;
    final teamId = ref.read(pharmacyProfileProvider).value?['team_id'] as String?;
    if (teamId != null && teamId.isNotEmpty) {
      ref.invalidate(branchesListProvider(teamId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String? ?? '';
    final branches = ref.watch(branchesListProvider(teamId));

    final body = branches.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          message: userFacingError(e),
          debugDetails: e.toString(),
          onRetry: () {
            ref.invalidate(branchesListProvider(teamId));
          },
        ),
        data: (rows) {
          final filtered = rows.where((b) {
            if (_query.trim().isEmpty) return true;
            final q = _query.trim().toLowerCase();
            final name = (b['name'] as String? ?? '').toLowerCase();
            final code = (b['code'] as String? ?? '').toLowerCase();
            return name.contains(q) || code.contains(q);
          }).toList();
          if (rows.isEmpty) {
            return const Center(child: Text('No branches yet'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(branchesListProvider(teamId));
            },
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Search branch name/code'),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final b = filtered[i];
                      final id = b['id'] as String? ?? '';
                      return ListTile(
                        title: Text(b['name'] as String? ?? ''),
                        subtitle: Text(b['code'] as String? ?? ''),
                        trailing: IconButton(
                          tooltip: 'Edit',
                          onPressed: () => _openBranchRoute('/pharmacy/branches/$id/edit'),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        onTap: () => _openBranchRoute('/pharmacy/branches/$id/edit'),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
    );

    if (widget.embedInHub) {
      return body;
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBranchRoute('/pharmacy/branches/new'),
        icon: const Icon(Icons.add),
        label: const Text('Branch'),
      ),
      body: body,
    );
  }
}
