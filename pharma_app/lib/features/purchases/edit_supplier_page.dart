import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

class EditSupplierPage extends StatefulWidget {
  const EditSupplierPage({super.key, required this.supplierId});

  final String supplierId;

  @override
  State<EditSupplierPage> createState() => _EditSupplierPageState();
}

class _EditSupplierPageState extends State<EditSupplierPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
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
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('suppliers')
          .select('name, phone')
          .eq('id', widget.supplierId)
          .single();
      _name.text = row['name'] as String? ?? '';
      _phone.text = row['phone'] as String? ?? '';
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
      await Supabase.instance.client.from('suppliers').update({
        'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      }).eq('id', widget.supplierId);
      if (!mounted) return;
      AppFeedback.success(context, 'Supplier updated');
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
      appBar: pharmacyPageAppBar(context, title: 'Edit supplier'),
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
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) => FormValidators.requiredText(v, label: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
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
