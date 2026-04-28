import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';

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
  final _category = TextEditingController();
  final _purchase = TextEditingController(text: '0');
  final _selling = TextEditingController(text: '0');
  final _reorder = TextEditingController(text: '0');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _generic.dispose();
    _code.dispose();
    _barcode.dispose();
    _category.dispose();
    _purchase.dispose();
    _selling.dispose();
    _reorder.dispose();
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
      await Supabase.instance.client.from('medicines').insert({
        'team_id': teamId,
        'name': name,
        'generic_name': _generic.text.trim().isEmpty ? null : _generic.text.trim(),
        'manual_code': code,
        'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        'category': _category.text.trim().isEmpty ? null : _category.text.trim(),
        'purchase_price': num.tryParse(_purchase.text) ?? 0,
        'selling_price': num.tryParse(_selling.text) ?? 0,
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
          AppTextFormField(
            controller: _generic,
            label: 'Generic name',
          ),
          const SizedBox(height: 12),
          AppTextFormField(
            controller: _code,
            label: 'Manual code (unique)',
            validator: (v) => FormValidators.requiredText(v, label: 'Manual code'),
          ),
          const SizedBox(height: 12),
          AppTextFormField(
            controller: _barcode,
            label: 'Barcode',
          ),
          const SizedBox(height: 12),
          AppTextFormField(
            controller: _category,
            label: 'Category',
          ),
          const SizedBox(height: 12),
          AppTextFormField(
            controller: _purchase,
            label: 'Purchase price',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            validator: (v) => FormValidators.nonNegativeNumber(v, label: 'Purchase price'),
          ),
          const SizedBox(height: 12),
          AppTextFormField(
            controller: _selling,
            label: 'Selling price',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            validator: (v) => FormValidators.nonNegativeNumber(v, label: 'Selling price'),
          ),
          const SizedBox(height: 12),
          AppTextFormField(
            controller: _reorder,
            label: 'Reorder level',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            validator: (v) => FormValidators.nonNegativeNumber(v, label: 'Reorder level'),
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
        ]),
      ),
    );
  }
}
