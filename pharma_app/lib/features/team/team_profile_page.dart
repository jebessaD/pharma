import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart' show userFacingError, mapFormError;
import '../../core/forms/form_validators.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';

class TeamProfilePage extends ConsumerStatefulWidget {
  const TeamProfilePage({super.key});

  @override
  ConsumerState<TeamProfilePage> createState() => _TeamProfilePageState();
}

class _TeamProfilePageState extends ConsumerState<TeamProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _pharmacyName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _license = TextEditingController();
  bool _loading = false;
  String? _profileRowId;
  String? _error;
  String? _teamId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final profile = await ref.read(pharmacyProfileProvider.future);
      final teamId = profile?['team_id'] as String?;
      if (!mounted || teamId == null) return;
      setState(() => _teamId = teamId);
      await _load(teamId);
    });
  }

  @override
  void dispose() {
    _pharmacyName.dispose();
    _phone.dispose();
    _address.dispose();
    _license.dispose();
    super.dispose();
  }

  Future<void> _load(String teamId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await Supabase.instance.client
          .from('team_profiles')
          .select()
          .eq('team_id', teamId)
          .maybeSingle();
      if (row != null) {
        _profileRowId = row['id'] as String?;
        _pharmacyName.text = row['pharmacy_name'] as String? ?? '';
        _phone.text = row['phone'] as String? ?? '';
        _address.text = row['address'] as String? ?? '';
        _license.text = row['license_number'] as String? ?? '';
      } else {
        _profileRowId = null;
        _pharmacyName.clear();
        _phone.clear();
        _address.clear();
        _license.clear();
      }
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final teamId = _teamId;
    if (teamId == null) return;
    final name = _pharmacyName.text.trim();
    setState(() => _loading = true);
    try {
      final payload = <String, dynamic>{
        'team_id': teamId,
        'pharmacy_name': name,
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'license_number': _license.text.trim().isEmpty ? null : _license.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (_profileRowId == null) {
        await Supabase.instance.client.from('team_profiles').insert(payload);
      } else {
        final update = Map<String, dynamic>.from(payload)..remove('team_id');
        await Supabase.instance.client
            .from('team_profiles')
            .update(update)
            .eq('id', _profileRowId!);
      }
      await _load(teamId);
      if (mounted) {
        AppFeedback.success(context, 'Saved');
      }
    } catch (e) {
      setState(() => _error = mapFormError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_teamId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text('Team profile', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          AppTextFormField(
            controller: _pharmacyName,
            label: 'Pharmacy name',
            validator: (v) => FormValidators.requiredText(v, label: 'Pharmacy name'),
          ),
          const SizedBox(height: 12),
          AppTextFormField(
            controller: _phone,
            label: 'Phone',
          ),
          const SizedBox(height: 12),
          AppTextFormField(
            controller: _address,
            label: 'Address',
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          AppTextFormField(
            controller: _license,
            label: 'License number',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FormErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ]),
      ),
    );
  }
}
