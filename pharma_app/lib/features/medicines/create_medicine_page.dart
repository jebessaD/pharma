import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/medicine_category_catalog.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';
import 'scan/medicine_scan_controller.dart';

class CreateMedicinePage extends ConsumerStatefulWidget {
  const CreateMedicinePage({super.key});

  @override
  ConsumerState<CreateMedicinePage> createState() => _CreateMedicinePageState();
}

class _CreateMedicinePageState extends ConsumerState<CreateMedicinePage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _generic = TextEditingController();
  final _code = TextEditingController();
  final _barcode = TextEditingController();
  final _reorder = TextEditingController(text: '0');
  String _categoryKey = medicineCategoryCatalog.first.key;
  bool _loading = false;
  String? _error;

  Future<void> _scanBarcode() async {
    String? code;
    try {
      code = await showCameraScanSheet(context);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Camera scanning is unavailable here. Type barcode manually.',
      );
      return;
    }
    final scanned = code?.trim();
    if (!mounted || scanned == null || scanned.isEmpty) return;
    setState(() {
      _barcode.text = scanned;
      _error = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _generic.dispose();
    _code.dispose();
    _barcode.dispose();
    _reorder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch first.');
      return;
    }
    final name = _name.text.trim();
    final codeRaw = _code.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.from('medicines').insert({
        'team_id': teamId,
        'branch_id': branchId,
        'name': name,
        'generic_name': _generic.text.trim().isEmpty
            ? null
            : _generic.text.trim(),
        'manual_code': codeRaw.isEmpty ? null : codeRaw,
        'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        'category_key': _categoryKey,
        'purchase_price': 0,
        'selling_price': 0,
        'reorder_level': num.tryParse(_reorder.text) ?? 0,
      });
      if (mounted) {
        AppFeedback.success(context, 'Medicine created');
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
    final categoriesAsync = ref.watch(activeBranchMedicineCategoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New medicine')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            AppTextFormField(
              controller: _name,
              label: 'Name',
              validator: (v) => FormValidators.requiredText(v, label: 'Name'),
            ),
            const SizedBox(height: 12),
            AppTextFormField(controller: _generic, label: 'Generic name'),
            const SizedBox(height: 12),
            AppTextFormField(
              controller: _code,
              label: 'Manual code (optional)',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _barcode,
              decoration: InputDecoration(
                labelText: 'Barcode (optional)',
                helperText: 'Type manually or scan',
                suffixIcon: IconButton(
                  tooltip: 'Scan barcode',
                  onPressed: _loading ? null : _scanBarcode,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ),
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
                        child: Text(c['name'] as String? ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _categoryKey = value);
                        }
                      },
                validator: (value) =>
                    value == null || value.isEmpty ? 'Select a category' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => const Text(
                'Could not load categories. Check branch and retry.',
              ),
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
            const SizedBox(height: 4),
            Text(
              'Low-stock threshold in your base unit. At or below this quantity, '
              'the medicine counts as low stock in reports and alerts. Use 0 to turn off.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
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
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
