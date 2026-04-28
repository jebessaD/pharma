import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_error_state.dart';

class StaffListPage extends ConsumerStatefulWidget {
  const StaffListPage({super.key, this.embedInHub = false});

  /// When true, omits [Scaffold] / [AppBar] / FAB (used inside [OrganizationHubPage]).
  final bool embedInHub;

  @override
  ConsumerState<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends ConsumerState<StaffListPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _openNewStaff() async {
    await context.push('/pharmacy/staff/new');
    if (mounted) _load();
  }

  Future<void> _openEditStaff(String id) async {
    await context.push('/pharmacy/staff/$id/edit');
    if (mounted) _load();
  }

  Future<void> _load() async {
    final profile = await ref.read(pharmacyProfileProvider.future);
    final teamId = profile?['team_id'] as String?;
    if (!mounted) return;
    if (teamId == null) {
      setState(() {
        _loading = false;
        _error = 'No team profile found.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, role, is_active, branch_id, username')
          .eq('team_id', teamId)
          .order('full_name');
      setState(() => _rows = List<Map<String, dynamic>>.from(rows as List));
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> row, bool active) async {
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'is_active': active})
          .eq('id', row['id'] as String);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? AppErrorState(
                message: _error!,
                onRetry: () {
                  _load();
                },
              )
            : _rows.isEmpty
                ? const Center(child: Text('No staff profiles yet'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        final active = row['is_active'] as bool? ?? false;
                        final uname = row['username'] as String?;
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              _initial(row['full_name'] as String?),
                            ),
                          ),
                          title: Text(row['full_name'] as String? ?? ''),
                          subtitle: Text(
                            [
                              if (uname != null && uname.isNotEmpty) '@$uname',
                              row['role'] ?? '',
                              if ((row['branch_id'] as String?)?.isNotEmpty == true) 'Branch assigned',
                            ].where((s) => s.toString().isNotEmpty).join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Switch(
                            value: active,
                            onChanged: (value) => _toggleActive(row, value),
                          ),
                          onTap: () => _openEditStaff(row['id'] as String),
                        );
                      },
                    ),
                  );

    if (widget.embedInHub) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewStaff,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add staff'),
      ),
      body: body,
    );
  }

  String _initial(String? name) {
    final cleaned = (name ?? '').trim();
    if (cleaned.isEmpty) return '?';
    return cleaned.substring(0, 1).toUpperCase();
  }
}
