import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/form_error_banner.dart';

class EditMedicinePage extends StatefulWidget {
  const EditMedicinePage({super.key, required this.medicineId});

  final String medicineId;

  @override
  State<EditMedicinePage> createState() => _EditMedicinePageState();
}

class _EditMedicinePageState extends State<EditMedicinePage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
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
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('medicines')
          .select('name, manual_code')
          .eq('id', widget.medicineId)
          .single();
      _name.text = row['name'] as String? ?? '';
      _code.text = row['manual_code'] as String? ?? '';
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
      await Supabase.instance.client.from('medicines').update({
        'name': _name.text.trim(),
        'manual_code': _code.text.trim(),
      }).eq('id', widget.medicineId);
      if (!mounted) return;
      AppFeedback.success(context, 'Medicine updated');
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
      appBar: AppBar(title: const Text('Edit medicine')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) => FormValidators.requiredText(v, label: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _code,
                      decoration: const InputDecoration(labelText: 'Manual code'),
                      validator: (v) => FormValidators.requiredText(v, label: 'Manual code'),
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
