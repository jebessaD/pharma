import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/staff_username_availability.dart';
import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';
import 'staff_credentials_dialog.dart';

class StaffCreateForm extends StatefulWidget {
  const StaffCreateForm({
    super.key,
    required this.teamId,
    required this.branches,
    required this.canAssignAdmin,
    required this.onCreated,
    this.compact = false,
  });

  final String teamId;
  final List<Map<String, dynamic>> branches;
  final bool canAssignAdmin;
  final Future<void> Function(String username, String password) onCreated;
  final bool compact;

  @override
  State<StaffCreateForm> createState() => _StaffCreateFormState();
}

class _StaffCreateFormState extends State<StaffCreateForm> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtl = TextEditingController();
  final _usernameCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  Timer? _usernameDebounce;
  int _usernameCheckSeq = 0;
  bool? _usernameAvailable;
  String _role = 'pharmacist';
  String? _branchId;
  String? _errorText;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _autoPassword = true;

  @override
  void initState() {
    super.initState();
    _branchId = widget.branches.length == 1
        ? widget.branches.first['id'] as String
        : null;
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _fullNameCtl.dispose();
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  void _scheduleUsernameCheck(String _) {
    _usernameDebounce?.cancel();
    final currentText = _usernameCtl.text;
    _usernameDebounce = Timer(const Duration(milliseconds: 400), () async {
      final seq = ++_usernameCheckSeq;
      final avail = await queryStaffUsernameAvailable(
        Supabase.instance.client,
        currentText,
      );
      if (!mounted || seq != _usernameCheckSeq) return;
      setState(() => _usernameAvailable = avail);
    });
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    if (_usernameAvailable == false) return;
    if (_branchId == null) {
      setState(() => _errorText = 'Please assign a branch.');
      return;
    }
    if (widget.teamId.isEmpty) {
      setState(() {
        _errorText =
            'Your team profile is not ready yet. Re-open organization or sign in again.';
      });
      return;
    }
    final username = _usernameCtl.text.trim().toLowerCase();
    final password =
        _autoPassword ? generateStaffPassword() : _passwordCtl.text;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'admin-create-user',
        body: {
          'username': username,
          'password': password,
          'full_name': _fullNameCtl.text.trim(),
          'role': _role,
          'branch_id': _branchId,
        },
      );
      if (res.status >= 400) {
        throw FunctionException(status: res.status, details: res.data);
      }
      if (!mounted) return;
      await widget.onCreated(username, password);
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = userFacingError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gap = widget.compact ? 10.0 : 12.0;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextFormField(
            controller: _fullNameCtl,
            label: 'Full name',
            validator: (v) => FormValidators.requiredText(v, label: 'Full name'),
          ),
          SizedBox(height: gap),
          AppTextFormField(
            controller: _usernameCtl,
            label: 'Username',
            textCapitalization: TextCapitalization.none,
            onChanged: _scheduleUsernameCheck,
            validator: (v) {
              final base = FormValidators.staffUsername(v);
              if (base != null) return base;
              if (_usernameAvailable == false) {
                return 'This username is already taken';
              }
              return null;
            },
          ),
          SizedBox(height: gap),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-generate password'),
            value: _autoPassword,
            onChanged: (value) => setState(() => _autoPassword = value),
          ),
          if (!_autoPassword) ...[
            TextFormField(
              controller: _passwordCtl,
              obscureText: _obscurePassword,
              validator: (v) => FormValidators.passwordMinLength(v, min: 8),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
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
            SizedBox(height: gap),
          ],
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Role'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _role,
                isExpanded: true,
                items: [
                  if (widget.canAssignAdmin)
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
                  if (value != null) setState(() => _role = value);
                },
              ),
            ),
          ),
          SizedBox(height: gap),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Branch *'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _branchId,
                isExpanded: true,
                hint: const Text('Select a branch'),
                items: widget.branches
                    .map(
                      (b) => DropdownMenuItem<String?>(
                        value: b['id'] as String,
                        child: Text(b['name'] as String? ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _branchId = value),
              ),
            ),
          ),
          if (_errorText != null) ...[
            SizedBox(height: gap),
            FormErrorBanner(message: _errorText!),
          ],
          SizedBox(height: gap + 4),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create user'),
          ),
        ],
      ),
    );
  }
}
