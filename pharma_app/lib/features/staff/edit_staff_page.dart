import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/staff_login_email.dart';
import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/form_error_banner.dart';

class EditStaffPage extends ConsumerStatefulWidget {
  const EditStaffPage({super.key, required this.staffId});

  final String staffId;

  @override
  ConsumerState<EditStaffPage> createState() => _EditStaffPageState();
}

class _EditStaffPageState extends ConsumerState<EditStaffPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _role = 'pharmacist';
  bool _active = true;
  bool _initialLoad = true;
  bool _busy = false;
  String? _error;
  String? _teamId;
  String? _username;
  String? _teamName;
  String? _viewerRole;

  /// From Auth (admin-get-user-email); preferred for sharing with staff.
  String? _authEmail;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _displaySignInEmail {
    if (_authEmail != null && _authEmail!.trim().isNotEmpty) {
      return _authEmail!.trim();
    }
    final u = _username;
    final tid = _teamId;
    if (u != null && u.isNotEmpty && tid != null && tid.isNotEmpty) {
      return staffSignInEmail(
        username: u,
        teamName: _teamName ?? '',
        teamId: tid,
      );
    }
    return null;
  }

  Future<void> _loadAuthEmail() async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'admin-get-user-email',
        body: {'user_id': widget.staffId},
      );
      if (!mounted) return;
      final d = res.data;
      if (d is Map) {
        final em = d['email'] as String?;
        if (em != null && em.isNotEmpty) {
          setState(() => _authEmail = em);
        }
      }
    } catch (_) {
      /* Edge may not be deployed yet; [_displaySignInEmail] can fall back. */
    }
  }

  Future<void> _load() async {
    try {
      final viewerId = Supabase.instance.client.auth.currentUser?.id;
      if (viewerId != null) {
        final viewer = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', viewerId)
            .maybeSingle();
        _viewerRole = viewer?['role'] as String?;
      }
      final row = await Supabase.instance.client
          .from('profiles')
          .select('full_name, role, is_active, username, team_id, teams(name)')
          .eq('id', widget.staffId)
          .single();
      _name.text = row['full_name'] as String? ?? '';
      _role = row['role'] as String? ?? 'pharmacist';
      _active = row['is_active'] as bool? ?? true;
      _username = row['username'] as String?;
      _teamId = row['team_id'] as String?;
      final teams = row['teams'];
      if (teams is Map<String, dynamic>) {
        _teamName = teams['name'] as String?;
      }
      setState(() => _initialLoad = false);
      await _loadAuthEmail();
    } catch (e) {
      setState(() {
        _initialLoad = false;
        _error = mapFormError(e);
      });
    }
  }

  Future<void> _deleteUser() async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me != null && me == widget.staffId) {
      AppFeedback.error(context, 'Owner account cannot delete itself.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete user?'),
        content: const Text(
          'This removes the login account permanently. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'admin-delete-user',
        body: {'user_id': widget.staffId},
      );
      if (res.status >= 400) {
        throw FunctionException(status: res.status, details: res.data);
      }
      if (!mounted) return;
      AppFeedback.success(context, 'User deleted');
      context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = mapFormError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'full_name': _name.text.trim(),
            'role': _role,
            'is_active': _active,
          })
          .eq('id', widget.staffId);
      if (!mounted) return;
      AppFeedback.success(context, 'Staff profile updated');
      context.pop();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = mapFormError(e);
      });
    }
  }

  Future<void> _resetPassword() async {
    final customCtl = TextEditingController();
    var obscureCustom = true;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reset password'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Leave blank to auto-generate a strong password.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: customCtl,
                  obscureText: obscureCustom,
                  decoration: InputDecoration(
                    labelText: 'Custom password (optional)',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureCustom
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setDialogState(() => obscureCustom = !obscureCustom);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (proceed != true) {
      customCtl.dispose();
      return;
    }
    final custom = customCtl.text.trim();
    customCtl.dispose();
    final useCustomPassword = custom.isNotEmpty;
    if (useCustomPassword && custom.length < 8) {
      if (mounted) {
        AppFeedback.error(context, 'Password must be at least 8 characters.');
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'user_id': widget.staffId,
        if (useCustomPassword) 'password': custom,
      };
      final res = await Supabase.instance.client.functions.invoke(
        'admin-reset-user-password',
        body: body,
      );
      if (!mounted) return;
      String? newPw;
      final data = res.data;
      if (data is Map) {
        newPw = data['password'] as String?;
      }
      if (newPw == null || newPw.isEmpty) {
        throw Exception('No password returned');
      }
      final revealedPassword = newPw;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New password'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Copy and share this with the user securely. It is not stored in the app.',
              ),
              const SizedBox(height: 12),
              SelectableText(revealedPassword),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: revealedPassword));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password copied')),
                );
              },
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = mapFormError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoad) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _teamId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit staff')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Edit staff')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sign-in email'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(_displaySignInEmail ?? '—'),
                    if (_username != null && _username!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Username: $_username',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if ((_username == null || _username!.isEmpty) &&
                        (_displaySignInEmail != null))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Legacy staff account (no username row).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
                trailing: _displaySignInEmail == null
                    ? null
                    : IconButton(
                        tooltip: 'Copy email',
                        icon: const Icon(Icons.copy_outlined),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _displaySignInEmail!),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Email copied')),
                          );
                        },
                      ),
              ),
              const Divider(),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) =>
                    FormValidators.requiredText(v, label: 'Full name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  if (_viewerRole == 'owner' || _role == 'admin')
                    const DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  const DropdownMenuItem(
                    value: 'pharmacist',
                    child: Text('Pharmacist'),
                  ),
                  const DropdownMenuItem(
                    value: 'cashier',
                    child: Text('Cashier'),
                  ),
                  const DropdownMenuItem(
                    value: 'seller',
                    child: Text('Seller'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _role = value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _resetPassword,
                icon: const Icon(Icons.lock_reset_outlined),
                label: const Text('Reset password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                FormErrorBanner(message: _error!),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save changes'),
              ),
              if (_viewerRole == 'owner' &&
                  Supabase.instance.client.auth.currentUser?.id !=
                      widget.staffId) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _deleteUser,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete user'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
