import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/widgets/app_error_state.dart';

class TeamDetailPage extends StatefulWidget {
  const TeamDetailPage({super.key, required this.teamId});

  final String teamId;

  @override
  State<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends State<TeamDetailPage> {
  Map<String, dynamic>? _team;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await Supabase.instance.client
          .from('teams')
          .select()
          .eq('id', widget.teamId)
          .single();
      if (!mounted) return;
      setState(() => _team = Map<String, dynamic>.from(row));
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(String status) async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client
          .from('teams')
          .update({'status': status})
          .eq('id', widget.teamId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _team == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team')),
        body: AppErrorState(
          message: _error!,
          onRetry: () {
            _load();
          },
        ),
      );
    }
    final t = _team!;
    final name = t['name'] as String? ?? '';
    final status = t['status'] as String? ?? '';
    final active = status == 'active';

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Status'),
              subtitle: Text(status),
              trailing: Chip(
                label: Text(active ? 'Active' : 'Suspended'),
                backgroundColor: active
                    ? Colors.green.shade100
                    : Colors.red.shade100,
              ),
            ),
            const SizedBox(height: 24),
            if (active)
              FilledButton.tonal(
                onPressed: _loading ? null : () => _setStatus('suspended'),
                child: const Text('Suspend team'),
              )
            else
              FilledButton(
                onPressed: _loading ? null : () => _setStatus('active'),
                child: const Text('Activate team'),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
