import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/medicine_category_catalog.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/medicine_catalog_form_fields.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

class EditMedicinePage extends ConsumerStatefulWidget {
  const EditMedicinePage({super.key, required this.medicineId});

  final String medicineId;

  @override
  ConsumerState<EditMedicinePage> createState() => _EditMedicinePageState();
}

class _EditMedicinePageState extends ConsumerState<EditMedicinePage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _generic = TextEditingController();
  final _code = TextEditingController();
  final _barcode = TextEditingController();
  final _subcategory = TextEditingController();
  final _country = TextEditingController();
  final _presentation = TextEditingController();
  final _strength = TextEditingController();
  final _dosageForm = TextEditingController();
  final _reorder = TextEditingController(text: '0');
  String _categoryKey = medicineCategoryCatalog.first.key;
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
    _generic.dispose();
    _code.dispose();
    _barcode.dispose();
    _subcategory.dispose();
    _country.dispose();
    _presentation.dispose();
    _strength.dispose();
    _dosageForm.dispose();
    _reorder.dispose();
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
          .select(
            'name, generic_name, manual_code, barcode, category_key, reorder_level, '
            'subcategory, country, presentation, strength, dosage_form',
          )
          .eq('id', widget.medicineId)
          .eq('branch_id', branchId)
          .single();
      _name.text = row['name'] as String? ?? '';
      _generic.text = row['generic_name'] as String? ?? '';
      _code.text = row['manual_code'] as String? ?? '';
      _barcode.text = row['barcode'] as String? ?? '';
      _subcategory.text = row['subcategory'] as String? ?? '';
      _country.text = row['country'] as String? ?? '';
      _presentation.text = row['presentation'] as String? ?? '';
      _strength.text = row['strength'] as String? ?? '';
      _dosageForm.text = row['dosage_form'] as String? ?? '';
      _reorder.text = '${row['reorder_level'] ?? 0}';
      final rawKey = row['category_key'] as String?;
      _categoryKey = medicineCategoryCatalog.any((c) => c.key == rawKey)
          ? rawKey!
          : medicineCategoryCatalog.last.key;
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
            'generic_name': _generic.text.trim().isEmpty
                ? null
                : _generic.text.trim(),
            'manual_code': _code.text.trim().isEmpty ? null : _code.text.trim(),
            'barcode': _barcode.text.trim().isEmpty
                ? null
                : _barcode.text.trim(),
            'category_key': _categoryKey,
            'subcategory': optionalMedicineText(_subcategory),
            'country': optionalMedicineText(_country),
            'presentation': optionalMedicineText(_presentation),
            'strength': optionalMedicineText(_strength),
            'dosage_form': optionalMedicineText(_dosageForm),
            'reorder_level': num.tryParse(_reorder.text) ?? 0,
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
      appBar: pharmacyPageAppBar(context, title: 'Edit medicine'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) =>
                        FormValidators.requiredText(v, label: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _generic,
                    decoration: const InputDecoration(
                      labelText: 'Generic name (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _code,
                    decoration: const InputDecoration(
                      labelText: 'Manual code (optional)',
                      helperText: 'Unique per branch when set',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _barcode,
                    decoration: const InputDecoration(labelText: 'Barcode'),
                  ),
                  const SizedBox(height: 12),
                  categoriesAsync.when(
                    data: (categories) => DropdownButtonFormField<String>(
                      initialValue: _categoryKey,
                      decoration: const InputDecoration(labelText: 'Category'),
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
                        if (value != null) {
                          setState(() => _categoryKey = value);
                        }
                      },
                      validator: (value) =>
                          value == null ? 'Select a category' : null,
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stackTrace) =>
                        const Text('Could not load categories'),
                  ),
                  const SizedBox(height: 12),
                  AppTextFormField(
                    controller: _reorder,
                    label: 'Reorder level',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    validator: (v) =>
                        FormValidators.nonNegativeNumber(v, label: 'Reorder level'),
                  ),
                  const SizedBox(height: 12),
                  MedicineOptionalDetailsSection(
                    subcategory: _subcategory,
                    country: _country,
                    presentation: _presentation,
                    strength: _strength,
                    dosageForm: _dosageForm,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    FormErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Save changes'),
                  ),
                ],
              ),
            ),
    );
  }
}
