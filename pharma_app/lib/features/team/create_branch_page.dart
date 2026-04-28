import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';

class CreateBranchPage extends ConsumerStatefulWidget {
  const CreateBranchPage({super.key});

  @override
  ConsumerState<CreateBranchPage> createState() => _CreateBranchPageState();
}

class _CreateBranchPageState extends ConsumerState<CreateBranchPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _address = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    if (teamId == null) return;
    final name = _name.text.trim();
    final code = _code.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.from('branches').insert({
        'team_id': teamId,
        'name': name,
        'code': code,
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      });
      if (mounted) {
        AppFeedback.success(context, 'Branch created');
        context.pop();
      }
    } catch (e) {
      setState(() => _error = mapFormError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New branch')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextFormField(
                controller: _name,
                label: 'Branch name',
                validator: (v) => FormValidators.requiredText(v, label: 'Branch name'),
              ),
              const SizedBox(height: 12),
              AppTextFormField(
                controller: _code,
                label: 'Branch code (unique per team)',
                validator: (v) => FormValidators.requiredText(v, label: 'Branch code'),
              ),
              const SizedBox(height: 12),
              AppTextFormField(
                controller: _address,
                label: 'Address',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                FormErrorBanner(message: _error!),
              ],
              const Spacer(),
              FilledButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
