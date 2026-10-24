import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/medicine_catalog/medicine_catalog.dart';
import '../../core/medicine_category_catalog.dart';
import '../../core/pricing/recommended_sell_price.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/medicine_catalog_form_fields.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';
import '../../core/widgets/apply_profit_roundup_checkbox.dart';
import '../../core/widgets/slash_dd_mm_yyyy_input.dart';
import 'stock_in_helpers.dart';
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
  final _subcategory = TextEditingController();
  final _country = TextEditingController();
  final _presentation = TextEditingController();
  final _strength = TextEditingController();
  final _dosageForm = TextEditingController();
  String _categoryKey = medicineCategoryCatalog.first.key;
  bool _loading = false;
  bool _addStockNow = false;
  bool _applyProfitRoundup = false;
  String? _error;
  final _stockBatchNo = TextEditingController();
  final _stockExpiry = TextEditingController();
  final _stockQty = TextEditingController();
  final _stockBuy = TextEditingController();
  final _stockSell = TextEditingController();

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
    _subcategory.dispose();
    _country.dispose();
    _presentation.dispose();
    _strength.dispose();
    _dosageForm.dispose();
    _stockBatchNo.dispose();
    _stockExpiry.dispose();
    _stockQty.dispose();
    _stockBuy.dispose();
    _stockSell.dispose();
    super.dispose();
  }

  void _applyCatalogEntry(MedicineCatalogEntry entry) {
    applyMedicineCatalogEntry(
      entry: entry,
      name: _name,
      genericName: _generic,
      subcategory: _subcategory,
      country: _country,
      presentation: _presentation,
      strength: _strength,
      dosageForm: _dosageForm,
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    if (_addStockNow) {
      final qty = num.tryParse(_stockQty.text.trim());
      if (qty == null || qty <= 0) {
        setState(
          () => _error = 'Enter stock quantity or turn off Add stock now.',
        );
        return;
      }
      final expErr = slashDdMmYyyyExpiryError(
        _stockExpiry.text,
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      );
      if (expErr != null) {
        setState(() => _error = expErr);
        return;
      }
    }
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch first.');
      return;
    }
    final name = _name.text.trim();
    final codeRaw = _code.text.trim();
    final buyPrice = num.tryParse(_stockBuy.text.trim()) ?? 0;
    final sellPrice =
        num.tryParse(_stockSell.text.trim()) ??
        (buyPrice > 0 ? recommendedSellPrice(buyPrice) : 0);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inserted = await Supabase.instance.client
          .from('medicines')
          .insert({
            'team_id': teamId,
            'branch_id': branchId,
            'name': name,
            'generic_name': _generic.text.trim().isEmpty
                ? null
                : _generic.text.trim(),
            'manual_code': codeRaw.isEmpty ? null : codeRaw,
            'barcode': _barcode.text.trim().isEmpty
                ? null
                : _barcode.text.trim(),
            'category_key': _categoryKey,
            'subcategory': optionalMedicineText(_subcategory),
            'country': optionalMedicineText(_country),
            'presentation': optionalMedicineText(_presentation),
            'strength': optionalMedicineText(_strength),
            'dosage_form': optionalMedicineText(_dosageForm),
            'purchase_price': buyPrice,
            'selling_price': sellPrice > 0 ? sellPrice : 0,
            'reorder_level': num.tryParse(_reorder.text) ?? 0,
          })
          .select('id')
          .single();
      final medicineId = inserted['id'] as String;
      if (_addStockNow) {
        final iso = slashDdMmYyyyToIso(_stockExpiry.text.trim())!;
        final qty = num.parse(_stockQty.text.trim());
        await stockInNewBatch(
          client: Supabase.instance.client,
          teamId: teamId,
          branchId: branchId,
          medicineId: medicineId,
          batchNo: _stockBatchNo.text.trim().isEmpty
              ? null
              : _stockBatchNo.text.trim(),
          expiryIso: iso,
          qty: qty,
          unitCost: buyPrice > 0 ? buyPrice : null,
          sellPrice: sellPrice > 0 ? sellPrice : null,
        );
      }
      if (mounted) {
        AppFeedback.success(context, 'Medicine created');
        context.go('/pharmacy/medicines/$medicineId');
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
    final catalogAsync = ref.watch(medicineCatalogProvider);
    final catalog =
        catalogAsync.asData?.value ?? const <MedicineCatalogEntry>[];
    return Scaffold(
      appBar: pharmacyPageAppBar(
        context,
        title: 'New medicine',
        subtitle: 'Add to catalog and stock in',
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            MedicineCatalogAutocompleteField(
              controller: _generic,
              catalog: catalog,
              label: 'Generic name',
              hintText: 'Search by generic, brand, or strength',
              displayTextForOption: (entry) => entry.genericName ?? entry.name,
              onSelected: _applyCatalogEntry,
            ),
            if (catalogAsync.isLoading) ...[
              const SizedBox(height: 6),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            MedicineCatalogAutocompleteField(
              controller: _name,
              catalog: catalog,
              label: 'Brand / trade name',
              hintText: 'e.g. Aldaz, Panadol',
              onSelected: _applyCatalogEntry,
              validator: (v) =>
                  FormValidators.requiredText(v, label: 'Brand / trade name'),
            ),
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
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add stock now'),
              subtitle: const Text('Stock in the first batch right away'),
              value: _addStockNow,
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _addStockNow = value),
            ),
            if (_addStockNow) ...[
              AppTextFormField(
                controller: _stockBatchNo,
                label: 'Batch number (optional)',
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _stockExpiry,
                keyboardType: TextInputType.number,
                inputFormatters: [SlashDdMmYyyyInputFormatter()],
                decoration: slashDdMmYyyyInputDecoration(
                  context,
                  label: 'Expiry *',
                ),
              ),
              const SizedBox(height: 10),
              AppTextFormField(
                controller: _stockQty,
                label: 'Quantity *',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: AppTextFormField(
                      controller: _stockBuy,
                      label: 'Buy price',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}$'),
                        ),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppTextFormField(
                      controller: _stockSell,
                      label: 'Sell price',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}$'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_addStockNow) ...[
                ApplyProfitRoundupCheckbox(
                  value: _applyProfitRoundup,
                  onChanged: (value) {
                    setState(() {
                      _applyProfitRoundup = value;
                      if (!value) return;
                      applyRecommendedSellPricesWhereEmpty([
                        (purchase: _stockBuy, sell: _stockSell),
                      ]);
                    });
                  },
                ),
              ],
              const SizedBox(height: 12),
            ],
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
