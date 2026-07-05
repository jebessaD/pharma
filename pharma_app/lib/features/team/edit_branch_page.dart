import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

class EditBranchPage extends StatefulWidget {
  const EditBranchPage({super.key, required this.branchId});

  final String branchId;

  @override
  State<EditBranchPage> createState() => _EditBranchPageState();
}

class _EditBranchPageState extends State<EditBranchPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _address = TextEditingController();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('branches')
          .select('name, code, address')
          .eq('id', widget.branchId)
          .single();
      _name.text = row['name'] as String? ?? '';
      _code.text = row['code'] as String? ?? '';
      _address.text = row['address'] as String? ?? '';
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = mapFormError(e);
      });
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.from('branches').update({
        'name': _name.text.trim(),
        'code': _code.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      }).eq('id', widget.branchId);
      if (!mounted) return;
      AppFeedback.success(context, 'Branch updated');
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = mapFormError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pharmacyPageAppBar(context, title: 'Edit branch'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Branch name'),
                      validator: (v) => FormValidators.requiredText(v, label: 'Branch name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _code,
                      decoration: const InputDecoration(labelText: 'Branch code'),
                      validator: (v) => FormValidators.requiredText(v, label: 'Branch code'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _address,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      FormErrorBanner(message: _error!),
                    ],
                    const Spacer(),
                    FilledButton(onPressed: _save, child: const Text('Save changes')),
                  ],
                ),
              ),
            ),
    );
  }
}
