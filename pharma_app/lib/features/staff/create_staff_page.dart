import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_formKey.currentState?.validate() != true) return;
    final profile = ref.read(pharmacyProfileProvider).value;
    if (profile == null) {
      setState(() {
        _error =
            'Your account profile is not loaded. Open the menu and retry, or sign in again as an administrator.';
      });
      return;
    }
    final username = _username.text.trim().toLowerCase();
    final password = _password.text;
    final fullName = _fullName.text.trim();
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
      if (!mounted) return;
      String? loginEmail;
      final data = res.data;
      if (data is Map) {
        loginEmail = data['login_email'] as String?;
      }
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
                  'Share these details with this person. They can sign in with their username '
                  'or the full email below.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text('Username', style: TextStyle(fontWeight: FontWeight.w600)),
                SelectableText(username),
                const SizedBox(height: 8),
                const Text('Sign-in email', style: TextStyle(fontWeight: FontWeight.w600)),
                SelectableText(loginEmail ?? '—'),
                const SizedBox(height: 8),
                const Text('Password', style: TextStyle(fontWeight: FontWeight.w600)),
                SelectableText(password),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${loginEmail ?? ''}\n$password'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied email and password')),
                );
              },
              child: const Text('Copy email & password'),
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
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String? ?? '';
    final branches = ref.watch(branchesListProvider(teamId)).value ?? const [];

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
              validator: (v) => FormValidators.requiredText(v, label: 'Full name'),
            ),
            const SizedBox(height: 12),
            AppTextFormField(
              controller: _username,
              label: 'Username',
              textCapitalization: TextCapitalization.none,
              validator: FormValidators.staffUsername,
            ),
            const Text(
              'Lowercase letters, numbers, and underscores only (3–32 characters).',
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
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(
                      value: 'pharmacist',
                      child: Text('Pharmacist'),
                    ),
                    DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
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
              decoration: const InputDecoration(labelText: 'Branch (optional)'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _branchId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No branch'),
                    ),
                    ...branches.map(
                      (b) => DropdownMenuItem<String?>(
                        value: b['id'] as String,
                        child: Text(b['name'] as String? ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _branchId = value),
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
