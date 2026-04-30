import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/form_error_banner.dart';

class EditMedicinePage extends ConsumerStatefulWidget {
  const EditMedicinePage({super.key, required this.medicineId});

  final String medicineId;

  @override
  ConsumerState<EditMedicinePage> createState() => _EditMedicinePageState();
}

class _EditMedicinePageState extends ConsumerState<EditMedicinePage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _barcode = TextEditingController();
  String? _categoryId;
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
    _barcode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final branchId = ref.read(selectedBranchIdProvider);
      if (branchId == null) {
        setState(() {
          _loading = false;
          _error = 'Select a branch first.';
        });
        return;
      }
      final row = await Supabase.instance.client
          .from('medicines')
          .select('name, manual_code, barcode, category_id')
          .eq('id', widget.medicineId)
          .eq('branch_id', branchId)
          .single();
      _name.text = row['name'] as String? ?? '';
      _code.text = row['manual_code'] as String? ?? '';
      _barcode.text = row['barcode'] as String? ?? '';
      _categoryId = row['category_id'] as String?;
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
    final branchId = ref.read(selectedBranchIdProvider);
    if (branchId == null) {
      setState(() => _error = 'Select a branch first.');
      return;
    }
    setState(() => _loading = true);
    try {
      await Supabase.instance.client
          .from('medicines')
          .update({
            'name': _name.text.trim(),
            'manual_code': _code.text.trim(),
            'barcode': _barcode.text.trim().isEmpty
                ? null
                : _barcode.text.trim(),
            'category_id': _categoryId,
          })
          .eq('id', widget.medicineId)
          .eq('branch_id', branchId);
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
    final categoriesAsync = ref.watch(branchMedicineCategoriesProvider);
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
                      validator: (v) =>
                          FormValidators.requiredText(v, label: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _code,
                      decoration: const InputDecoration(
                        labelText: 'Manual code',
                      ),
                      validator: (v) =>
                          FormValidators.requiredText(v, label: 'Manual code'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _barcode,
                      decoration: const InputDecoration(labelText: 'Barcode'),
                    ),
                    const SizedBox(height: 12),
                    categoriesAsync.when(
                      data: (categories) => DropdownButtonFormField<String>(
                        initialValue: _categoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: categories
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: c['id'] as String,
                                child: Text(
                                  c['is_active'] == true
                                      ? (c['name'] as String? ?? '')
                                      : '${c['name'] ?? ''} (inactive)',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _categoryId = value);
                        },
                        validator: (value) =>
                            value == null ? 'Select a category' : null,
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (error, stackTrace) =>
                          const Text('Could not load categories'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      FormErrorBanner(message: _error!),
                    ],
                    const Spacer(),
                    FilledButton(
                      onPressed: _save,
                      child: const Text('Save changes'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
