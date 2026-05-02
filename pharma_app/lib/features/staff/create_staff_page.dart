import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/staff_username_availability.dart';
import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';

class CreateStaffPage extends ConsumerStatefulWidget {
  const CreateStaffPage({super.key});

  @override
  ConsumerState<CreateStaffPage> createState() => _CreateStaffPageState();
}

class _CreateStaffPageState extends ConsumerState<CreateStaffPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  String _role = 'pharmacist';
  String? _branchId;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  Timer? _usernameDebounce;
  int _usernameCheckSeq = 0;
  bool? _usernameAvailable;

  void _scheduleUsernameAvailabilityCheck(String _) {
    _usernameDebounce?.cancel();
    _usernameDebounce = Timer(const Duration(milliseconds: 400), () async {
      final seq = ++_usernameCheckSeq;
      final avail = await queryStaffUsernameAvailable(
        Supabase.instance.client,
        _username.text,
      );
      if (!mounted || seq != _usernameCheckSeq) return;
      setState(() => _usernameAvailable = avail);
    });
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _username.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    debugPrint('[CreateStaff] submit tapped');
    if (_formKey.currentState?.validate() != true) return;
    if (_usernameAvailable == false) return;
    if (_branchId == null) {
      setState(() => _error = 'Please assign a branch.');
      return;
    }
    final profile = ref.read(pharmacyProfileProvider).value;
    if (profile == null) {
      debugPrint('[CreateStaff] profile is null');
      setState(() {
        _error =
            'Your account profile is not loaded. Open the menu and retry, or sign in again as an administrator.';
      });
      return;
    }
    final username = _username.text.trim().toLowerCase();
    final password = _password.text;
    final fullName = _fullName.text.trim();
    debugPrint(
      '[CreateStaff] request username=$username role=$_role branch=$_branchId hasTeam=${profile['team_id'] != null}',
    );
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'admin-create-user',
        body: {
          'username': username,
          'password': password,
          'full_name': fullName,
          'role': _role,
          'branch_id': _branchId,
        },
      );
      if (res.status >= 400) {
        debugPrint(
          '[CreateStaff] function invoke failed status=${res.status} data=${res.data}',
        );
        throw FunctionException(status: res.status, details: res.data);
      }
      debugPrint('[CreateStaff] function invoke success status=${res.status}');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Staff created'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Share these details with this person. They sign in with username and password.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Username',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SelectableText(username),
                const SizedBox(height: 8),
                const Text(
                  'Password',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SelectableText(password),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: '$username\n$password'),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied username and password')),
                );
              },
              child: const Text('Copy username & password'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      AppFeedback.success(context, 'Staff user created');
      context.pop();
    } catch (e) {
      debugPrint('[CreateStaff] create failed: $e');
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(pharmacyProfileProvider).value;
    final viewerRole = profile?['role'] as String? ?? '';
    final canAssignAdmin = viewerRole == 'owner';
    final teamId = profile?['team_id'] as String? ?? '';
    final branches = ref.watch(branchesListProvider(teamId)).value ?? const [];
    if (_branchId == null && branches.length == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _branchId = branches.first['id'] as String);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add staff')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            AppTextFormField(
              controller: _fullName,
              label: 'Full name',
              validator: (v) =>
                  FormValidators.requiredText(v, label: 'Full name'),
            ),
            const SizedBox(height: 12),
            AppTextFormField(
              controller: _username,
              label: 'Username',
              textCapitalization: TextCapitalization.none,
              onChanged: _scheduleUsernameAvailabilityCheck,
              validator: (v) {
                final base = FormValidators.staffUsername(v);
                if (base != null) return base;
                if (_usernameAvailable == false) {
                  return 'This username is already taken';
                }
                return null;
              },
            ),
            const Text(
              'Lowercase letters, numbers, and underscores only (3–32 characters). '
              'Must be unique across all pharmacies.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              validator: (v) => FormValidators.passwordMinLength(v, min: 8),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Role'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _role,
                  isExpanded: true,
                  items: [
                    if (canAssignAdmin)
                      const DropdownMenuItem(
                        value: 'admin',
                        child: Text('Admin'),
                      ),
                    const DropdownMenuItem(
                      value: 'pharmacist',
                      child: Text('Pharmacist'),
                    ),
                    const DropdownMenuItem(
                      value: 'seller',
                      child: Text('Seller (counter)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _role = value);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Branch *',
                errorText: _branchId == null && _error != null && _error!.contains('branch')
                    ? 'Required'
                    : null,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _branchId,
                  isExpanded: true,
                  hint: const Text('Select a branch'),
                  items: branches
                      .map(
                        (b) => DropdownMenuItem<String?>(
                          value: b['id'] as String,
                          child: Text(b['name'] as String? ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _branchId = value;
                    if (_error != null && _error!.contains('branch')) {
                      _error = null;
                    }
                  }),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              FormErrorBanner(message: _error!),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _create,
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create user'),
            ),
          ],
        ),
      ),
    );
  }
}
