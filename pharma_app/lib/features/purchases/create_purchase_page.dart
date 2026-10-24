import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/refresh_alerts_silent.dart';
import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/medicine_catalog/medicine_catalog.dart';
import '../../core/medicine/medicine_display.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/pharmacy_redirect_cache_provider.dart';
import '../../core/providers/branch_change_guard_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/medicine_catalog_form_fields.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';
import '../../core/widgets/slash_dd_mm_yyyy_input.dart';
import '../medicines/searchable_picker_fields.dart';
import 'purchase_drafts_refresh_provider.dart';

/// Loose UUID shape check so route segments like `drafts` are not used as ids.
final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

class CreatePurchasePage extends ConsumerStatefulWidget {
  const CreatePurchasePage({
    super.key,
    this.purchaseId,
    this.initialSupplierId,
  });

  /// When set, load this draft purchase (must be `status = draft`).
  final String? purchaseId;

  /// Preselect a supplier when opening a new purchase from the supplier list.
  final String? initialSupplierId;

  @override
  ConsumerState<CreatePurchasePage> createState() => _CreatePurchasePageState();
}

class _CreatePurchasePageState extends ConsumerState<CreatePurchasePage> {
  static const _guardKey = 'create_purchase_page';
  final _formKey = GlobalKey<FormState>();
  late final BranchChangeGuard _branchGuard;
  String? _supplierId;
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _medicines = [];
  String? _selectedMedicineId;
  final _invoice = TextEditingController();
  final _batch = TextEditingController();
  final _expiry = TextEditingController();
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  final _sellPrice = TextEditingController();
  int _medicinePickerKey = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _purchaseId;
  List<Map<String, dynamic>> _lineItems = [];
  Map<String, dynamic>? _purchaseHeader;

  bool get _supplierLocked => _lineItems.isNotEmpty;

  String _medicineDisplayName(String medicineId) {
    for (final m in _medicines) {
      if (m['id'] == medicineId) {
        return medicineAutocompleteLabel(m);
      }
    }
    return 'Medicine';
  }

  @override
  void initState() {
    super.initState();
    _branchGuard = ref.read(branchChangeGuardProvider.notifier);
    _purchaseId = widget.purchaseId;
    _invoice.addListener(_syncDirtyState);
    _batch.addListener(_syncDirtyState);
    _expiry.addListener(_syncDirtyState);
    _qty.addListener(_syncDirtyState);
    _cost.addListener(_syncDirtyState);
    _sellPrice.addListener(_syncDirtyState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _branchGuard.register(_guardKey, onDiscard: _discardChanges);
    });
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _invoice.removeListener(_syncDirtyState);
    _batch.removeListener(_syncDirtyState);
    _expiry.removeListener(_syncDirtyState);
    _qty.removeListener(_syncDirtyState);
    _cost.removeListener(_syncDirtyState);
    _sellPrice.removeListener(_syncDirtyState);
    _branchGuard.unregister(_guardKey);
    _invoice.dispose();
    _batch.dispose();
    _expiry.dispose();
    _qty.dispose();
    _cost.dispose();
    _sellPrice.dispose();
    super.dispose();
  }

  bool get _partialLine =>
      _selectedMedicineId != null ||
      _batch.text.trim().isNotEmpty ||
      _expiry.text.trim().isNotEmpty ||
      _qty.text.trim().isNotEmpty ||
      _cost.text.trim().isNotEmpty ||
      _sellPrice.text.trim().isNotEmpty;

  bool get _isDirty {
    if (_partialLine) return true;
    if (_lineItems.isEmpty) {
      final defaultSupplierId =
          widget.initialSupplierId ??
          (_suppliers.isNotEmpty ? _suppliers.first['id'] as String : null);
      return _invoice.text.trim().isNotEmpty ||
          (_supplierId != null && _supplierId != defaultSupplierId);
    }
    final inv = _purchaseHeader?['invoice_reference'] as String?;
    final invNorm = inv?.trim() ?? '';
    if (_invoice.text.trim() != invNorm) return true;
    final sid = _purchaseHeader?['supplier_id'] as String?;
    if (_supplierId != sid) return true;
    return false;
  }

  void _syncDirtyState() {
    if (!mounted) return;
    _branchGuard.setDirty(_guardKey, _isDirty);
  }

  void _clearLineForm() {
    _selectedMedicineId = null;
    _batch.clear();
    _expiry.clear();
    _qty.clear();
    _cost.clear();
    _sellPrice.clear();
    _medicinePickerKey++;
  }

  void _discardChanges() {
    if (!mounted) return;
    setState(() {
      _clearLineForm();
      _error = null;
      if (_purchaseHeader != null) {
        _supplierId = _purchaseHeader!['supplier_id'] as String?;
        final inv = _purchaseHeader!['invoice_reference'] as String?;
        _invoice.text = inv ?? '';
      } else {
        _invoice.clear();
        _supplierId =
            widget.initialSupplierId != null &&
                _suppliers.any((s) => s['id'] == widget.initialSupplierId)
            ? widget.initialSupplierId
            : (_suppliers.isNotEmpty ? _suppliers.first['id'] as String : null);
      }
    });
    _branchGuard.clearDirty(_guardKey);
  }

  Future<void> _loadLineItems(String purchaseId) async {
    final data = await Supabase.instance.client
        .from('purchase_items')
        .select(
          'id, medicine_id, batch_no, expiry_date, qty_base_unit, unit_cost, sell_price',
        )
        .eq('purchase_id', purchaseId)
        .order('id');
    final list = List<Map<String, dynamic>>.from(data as List);
    final out = <Map<String, dynamic>>[];
    for (final row in list) {
      final mid = row['medicine_id'] as String;
      out.add({
        'id': row['id'],
        'medicine_id': mid,
        'medicine_name': _medicineDisplayName(mid),
        'batch_no': row['batch_no'],
        'expiry_date': row['expiry_date'],
        'qty_base_unit': _coerceNum(row['qty_base_unit']),
        'unit_cost': _coerceNum(row['unit_cost']),
        'sell_price': row['sell_price'],
      });
    }
    if (!mounted) return;
    setState(() => _lineItems = out);
  }

  Future<void> _bootstrap() async {
    final profile = await ref.read(pharmacyProfileProvider.future);
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (!mounted) return;
    if (teamId == null) {
      setState(() {
        _loading = false;
        _error = 'No team';
      });
      return;
    }
    if (branchId == null) {
      setState(() {
        _loading = false;
        _error = 'Select a branch first.';
      });
      return;
    }
    final routePid = widget.purchaseId;
    if (routePid != null && !_uuidPattern.hasMatch(routePid)) {
      setState(() {
        _loading = false;
        _error = 'Invalid purchase link.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sup = await Supabase.instance.client
          .from('suppliers')
          .select()
          .eq('team_id', teamId)
          .order('name');
      final med = await Supabase.instance.client
          .from('medicines')
          .select()
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .order('name');
      if (!mounted) return;
      final suppliers = List<Map<String, dynamic>>.from(sup as List);
      final medicines = List<Map<String, dynamic>>.from(med as List);

      final pid = routePid ?? _purchaseId;
      if (pid != null) {
        final pu = await Supabase.instance.client
            .from('purchases')
            .select()
            .eq('id', pid)
            .eq('team_id', teamId)
            .maybeSingle();
        if (!mounted) return;
        if (pu == null) {
          setState(() {
            _suppliers = suppliers;
            _medicines = medicines;
            _error = 'Purchase not found.';
            _loading = false;
          });
          return;
        }
        if ((pu['status'] as String?) != 'draft') {
          setState(() {
            _suppliers = suppliers;
            _medicines = medicines;
            _error = 'This purchase is not a draft.';
            _loading = false;
          });
          return;
        }
        if ((pu['branch_id'] as String?) != branchId) {
          setState(() {
            _suppliers = suppliers;
            _medicines = medicines;
            _error = 'This draft belongs to another branch.';
            _loading = false;
          });
          return;
        }
        final header = Map<String, dynamic>.from(pu);
        final purchaseId = pu['id'] as String;
        final supplierId = pu['supplier_id'] as String?;
        final inv = pu['invoice_reference'] as String?;
        if (!mounted) return;
        setState(() {
          _suppliers = suppliers;
          _medicines = medicines;
          _purchaseHeader = header;
          _purchaseId = purchaseId;
          _supplierId = supplierId;
          _invoice.text = inv ?? '';
        });
        await _loadLineItems(purchaseId);
      } else {
        if (!mounted) return;
        final preferredSupplierId =
            widget.initialSupplierId != null &&
                suppliers.any((s) => s['id'] == widget.initialSupplierId)
            ? widget.initialSupplierId
            : (suppliers.isNotEmpty ? suppliers.first['id'] as String : null);
        setState(() {
          _suppliers = suppliers;
          _medicines = medicines;
          _purchaseHeader = null;
          _purchaseId = null;
          _lineItems = [];
          _supplierId = preferredSupplierId;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Failed to load suppliers or medicines. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _syncDirtyState();
      }
    }
  }

  Future<bool> _addLineFromFields(_AddLineFields f) async {
    final profile = await ref.read(pharmacyProfileProvider.future);
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null || _supplierId == null) {
      setState(() => _error = 'Select supplier and branch first');
      return false;
    }
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final expiryError = slashDdMmYyyyExpiryError(f.expiryText, today);
    final expiryIso = slashDdMmYyyyToIso(f.expiryText);
    if (f.qty <= 0 || f.cost < 0 || expiryError != null || expiryIso == null) {
      setState(() => _error = 'Enter valid quantity, unit cost, and expiry');
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var pid = _purchaseId;
      if (pid == null) {
        final purchase = await Supabase.instance.client
            .from('purchases')
            .insert({
              'team_id': teamId,
              'branch_id': branchId,
              'supplier_id': _supplierId,
              'invoice_reference': _invoice.text.trim().isEmpty
                  ? null
                  : _invoice.text.trim(),
              'status': 'draft',
            })
            .select('id, supplier_id, invoice_reference')
            .single();
        pid = purchase['id'] as String;
        _purchaseHeader = Map<String, dynamic>.from(purchase);
        if (!mounted) return false;
        setState(() => _purchaseId = pid);
      } else {
        await Supabase.instance.client
            .from('purchases')
            .update({
              'invoice_reference': _invoice.text.trim().isEmpty
                  ? null
                  : _invoice.text.trim(),
            })
            .eq('id', pid);
        _purchaseHeader = {
          if (_purchaseHeader != null)
            ...Map<String, dynamic>.from(_purchaseHeader!),
          'id': pid,
          'supplier_id': _supplierId,
          'invoice_reference': _invoice.text.trim().isEmpty
              ? null
              : _invoice.text.trim(),
        };
      }
      final insertPayload = <String, dynamic>{
        'purchase_id': pid,
        'medicine_id': f.medicineId,
        'batch_no': f.batch.trim(),
        'expiry_date': expiryIso,
        'qty_base_unit': f.qty,
        'unit_cost': f.cost,
      };
      if (f.sellPrice != null) insertPayload['sell_price'] = f.sellPrice;
      final inserted = await Supabase.instance.client
          .from('purchase_items')
          .insert(insertPayload)
          .select('id')
          .single();
      if (!mounted) return false;
      setState(() {
        _lineItems = [
          ..._lineItems,
          {
            'id': inserted['id'],
            'medicine_id': f.medicineId,
            'medicine_name': _medicineDisplayName(f.medicineId),
            'batch_no': f.batch.trim(),
            'expiry_date': expiryIso,
            'qty_base_unit': f.qty,
            'unit_cost': f.cost,
            'sell_price': f.sellPrice,
          },
        ];
        _purchaseHeader = {
          'supplier_id': _supplierId,
          'invoice_reference': _invoice.text.trim().isEmpty
              ? null
              : _invoice.text.trim(),
        };
        _selectedMedicineId = null;
        _batch.clear();
        _expiry.clear();
        _qty.clear();
        _cost.clear();
        _sellPrice.clear();
        _medicinePickerKey++;
      });
      _syncDirtyState();
      ref.read(purchaseDraftsRefreshProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Line added to this draft.')),
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not add line. Check inputs and try again.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showAddSupplierDialog() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    if (teamId == null) {
      setState(() => _error = 'No team');
      return;
    }

    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final phone = TextEditingController();
    String? formError;

    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final screenW = MediaQuery.sizeOf(ctx).width;
        final dialogWidth = (screenW - 48).clamp(320.0, 560.0);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            title: const Text('Quick add supplier'),
            content: SizedBox(
              width: dialogWidth,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) =>
                          FormValidators.requiredText(v, label: 'Name'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        formError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (formKey.currentState?.validate() != true) return;
                  try {
                    final row = await Supabase.instance.client
                        .from('suppliers')
                        .insert({
                          'team_id': teamId,
                          'name': name.text.trim(),
                          'phone': phone.text.trim().isEmpty
                              ? null
                              : phone.text.trim(),
                        })
                        .select()
                        .single();
                    if (ctx.mounted) {
                      Navigator.pop(ctx, Map<String, dynamic>.from(row));
                    }
                  } catch (e) {
                    setDialogState(() => formError = userFacingError(e));
                  }
                },
                child: const Text('Save & select'),
              ),
            ],
          ),
        );
      },
    );

    name.dispose();
    phone.dispose();
    if (created == null || !mounted) return;
    final id = created['id'] as String?;
    if (id == null) return;
    setState(() {
      _suppliers = [created, ..._suppliers.where((s) => s['id'] != id)];
      _supplierId = id;
      _error = null;
    });
    _syncDirtyState();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Supplier added and selected.')),
    );
  }

  Future<void> _showAddMedicineDialog() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Please select a branch first.');
      return;
    }
    List<Map<String, dynamic>> categories;
    try {
      final data = await ref.read(
        activeBranchMedicineCategoriesProvider.future,
      );
      categories = List<Map<String, dynamic>>.from(data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load categories. Please retry.');
      return;
    }
    if (categories.isEmpty) {
      setState(() => _error = 'Category list is unavailable. Please retry.');
      return;
    }
    List<MedicineCatalogEntry> catalog;
    try {
      catalog = await ref.read(medicineCatalogProvider.future);
    } catch (_) {
      catalog = const [];
    }
    if (!mounted) return;

    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => _AddMedicineFromPurchaseDialog(
        teamId: teamId,
        branchId: branchId,
        categories: categories,
        catalog: catalog,
      ),
    );

    if (created == null || !mounted) return;
    final row = Map<String, dynamic>.from(created);
    final createdId = row['id'] as String?;
    if (createdId == null) return;
    setState(() {
      _medicines = [row, ..._medicines.where((m) => m['id'] != createdId)];
      _selectedMedicineId = createdId;
      _medicinePickerKey++;
      _error = null;
    });
    _syncDirtyState();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medicine added. Continue with batch and quantities.'),
        ),
      );
    }
  }

  Future<void> _showAddLineDialog({required bool isPharmacist}) async {
    if (_supplierId == null) {
      setState(() => _error = 'Select a supplier first.');
      return;
    }

    final dialogFormKey = GlobalKey<FormState>();
    final batch = TextEditingController();
    final expiry = TextEditingController();
    final qty = TextEditingController();
    final cost = TextEditingController();
    final sellPrice = TextEditingController();
    var selectedMedicineId = _selectedMedicineId;
    var pickerKey = _medicinePickerKey;
    var dialogSaving = false;
    String? lineError;

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final screen = MediaQuery.sizeOf(ctx);
          final dialogWidth = (screen.width - 32).clamp(340.0, 720.0);
          final maxHeight = screen.height * 0.82;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
              title: Text(
                _lineItems.isEmpty ? 'Add first line' : 'Add another line',
              ),
              content: SizedBox(
                width: dialogWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: SingleChildScrollView(
                    child: Form(
                      key: dialogFormKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          MedicineAutocompleteField(
                            key: ValueKey('purchase-med-dialog-$pickerKey'),
                            rows: _medicines,
                            initialMedicineId: selectedMedicineId,
                            label: 'Search medicine',
                            validator: (_) => selectedMedicineId == null
                                ? 'Select a medicine'
                                : null,
                            onPicked: (row) {
                              final id = row['id'] as String;
                              setState(() => _selectedMedicineId = id);
                              setDialogState(() => selectedMedicineId = id);
                              _syncDirtyState();
                            },
                          ),
                          const SizedBox(height: 10),
                          if (!isPharmacist)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: dialogSaving
                                    ? null
                                    : () async {
                                        await _showAddMedicineDialog();
                                        if (!mounted || !ctx.mounted) return;
                                        setDialogState(() {
                                          selectedMedicineId =
                                              _selectedMedicineId;
                                          pickerKey = _medicinePickerKey;
                                        });
                                      },
                                icon: const Icon(Icons.medication_outlined),
                                label: const Text('Not found? Add medicine'),
                              ),
                            ),
                          if (!isPharmacist) const SizedBox(height: 16),
                          TextFormField(
                            controller: batch,
                            decoration: const InputDecoration(
                              labelText: 'Batch no',
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'Enter batch number'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: expiry,
                            keyboardType: TextInputType.number,
                            inputFormatters: [SlashDdMmYyyyInputFormatter()],
                            decoration: slashDdMmYyyyInputDecoration(
                              context,
                              label: 'Expiry',
                            ),
                            validator: (value) => slashDdMmYyyyExpiryError(
                              value ?? '',
                              DateTime(
                                DateTime.now().year,
                                DateTime.now().month,
                                DateTime.now().day,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: qty,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}$'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Qty (base units)',
                              helperText: 'Added to stock on receive',
                            ),
                            validator: (value) {
                              final q = num.tryParse(value ?? '');
                              if (q == null || q <= 0) {
                                return 'Enter quantity greater than 0';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: cost,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}$'),
                                    ),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Unit cost (ETB)',
                                    isDense: true,
                                  ),
                                  validator: (value) {
                                    final co = num.tryParse(value ?? '');
                                    if (co == null || co < 0) {
                                      return 'Enter a valid unit cost';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: sellPrice,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}$'),
                                    ),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Sell price',
                                    helperText: 'Optional',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (lineError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              lineError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: dialogSaving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: dialogSaving
                      ? null
                      : () async {
                          if (dialogFormKey.currentState?.validate() != true) {
                            return;
                          }
                          final mid = selectedMedicineId;
                          if (mid == null) {
                            setDialogState(
                              () => lineError = 'Select a medicine',
                            );
                            return;
                          }
                          final parsedQty = num.tryParse(qty.text);
                          final parsedCost = num.tryParse(cost.text);
                          if (parsedQty == null ||
                              parsedQty <= 0 ||
                              parsedCost == null ||
                              parsedCost < 0) {
                            setDialogState(
                              () => lineError = 'Enter valid quantity and cost',
                            );
                            return;
                          }
                          setDialogState(() {
                            dialogSaving = true;
                            lineError = null;
                          });
                          final ok = await _addLineFromFields(
                            _AddLineFields(
                              medicineId: mid,
                              batch: batch.text,
                              expiryText: expiry.text,
                              qty: parsedQty,
                              cost: parsedCost,
                              sellPrice: num.tryParse(sellPrice.text.trim()),
                            ),
                          );
                          if (!ctx.mounted) return;
                          if (ok) {
                            Navigator.pop(ctx);
                          } else {
                            setDialogState(() => dialogSaving = false);
                          }
                        },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(dialogSaving ? 'Adding...' : 'Add line'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      batch.dispose();
      expiry.dispose();
      qty.dispose();
      cost.dispose();
      sellPrice.dispose();
    }
  }

  Future<void> _receive() async {
    final id = _purchaseId;
    if (id == null || _lineItems.isEmpty) {
      setState(
        () => _error = 'Add at least one line to this draft before receiving.',
      );
      return;
    }
    final lineSummaries = _lineItems
        .map((row) {
          final name = row['medicine_name'] as String? ?? '';
          final q = _formatQty(row['qty_base_unit']);
          return '· $name — +$q base units to stock';
        })
        .join('\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Receive goods?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Stock will increase by the quantities below for ${_lineItems.length} line(s).',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              SelectableText(
                lineSummaries,
                style: Theme.of(
                  ctx,
                ).textTheme.bodySmall?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 12),
              Text('Continue?', style: Theme.of(ctx).textTheme.bodyMedium),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Receive'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'receive_purchase',
        params: {'p_purchase_id': id},
      );
      if (!mounted) return;
      final profile = ref.read(pharmacyProfileProvider).value;
      final tid = profile?['team_id'] as String?;
      final bid = ref.read(selectedBranchIdProvider);
      if (tid != null && bid != null) {
        await refreshAlertsSilent(teamId: tid, branchId: bid);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = userFacingError(e));
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    _branchGuard.clearDirty(_guardKey);
    ref.read(purchaseDraftsRefreshProvider.notifier).bump();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Purchase marked as received (no longer a draft). Stock updated.',
        ),
      ),
    );
    context.go('/pharmacy/purchases');
  }

  String _formatExpiryLine(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.split('T').first;
  }

  static num _coerceNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  static String _formatQty(dynamic v) {
    final n = _coerceNum(v);
    if (n == n.roundToDouble()) return n.round().toString();
    return n.toString();
  }

  static String _formatUnitCost(dynamic v) {
    final n = _coerceNum(v);
    return n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(selectedBranchIdProvider, (prev, next) {
      if (!mounted || prev == next) return;
      if (_isDirty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Branch resolved from null (e.g. first hydrate) — reload, do not treat as switch-away.
        if (prev == null && next != null) {
          Future.microtask(_bootstrap);
          return;
        }
        if (prev == null || next == null) return;
        if (widget.purchaseId != null || _purchaseId != null) {
          context.go('/pharmacy/purchases');
          return;
        }
        Future.microtask(_bootstrap);
      });
    });

    final branchId = ref.watch(selectedBranchIdProvider);
    final isPharmacist =
        ref.watch(pharmacyRedirectCacheProvider)?.role == 'pharmacist';
    final isEditMode = widget.purchaseId != null;
    final title = isEditMode ? 'Edit draft' : 'New purchase';
    final t = Theme.of(context);
    final cs = t.colorScheme;

    final formScroll = ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'supplier_${branchId ?? ''}_${_purchaseId ?? 'new'}_${_lineItems.length}',
                      ),
                      initialValue: _supplierId,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                      items: _suppliers
                          .map(
                            (s) => DropdownMenuItem(
                              value: s['id'] as String,
                              child: Text(s['name'] as String? ?? ''),
                            ),
                          )
                          .toList(),
                      onChanged: _supplierLocked
                          ? null
                          : (v) {
                              setState(() => _supplierId = v);
                              _syncDirtyState();
                            },
                      validator: (value) =>
                          value == null ? 'Select a supplier' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: IconButton.filledTonal(
                      tooltip: 'Quick add supplier',
                      onPressed: _supplierLocked || _saving
                          ? null
                          : _showAddSupplierDialog,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                    ),
                  ),
                ],
              ),
              if (_supplierLocked)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Supplier is fixed after the first line.',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _invoice,
                decoration: const InputDecoration(
                  labelText: 'Invoice reference',
                ),
              ),
              if (_lineItems.isNotEmpty) ...[
                const SizedBox(height: 24),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.65),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 22,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Lines on this draft',
                                style: t.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            Text(
                              '${_lineItems.length} ${_lineItems.length == 1 ? 'line' : 'lines'}',
                              style: t.textTheme.labelLarge?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'These quantities post to stock when you receive.',
                          style: t.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._lineItems.map((row) {
                          final name = row['medicine_name'] as String? ?? '';
                          final batch = row['batch_no'] as String? ?? '';
                          final exp = _formatExpiryLine(row['expiry_date']);
                          final q = _formatQty(row['qty_base_unit']);
                          final c = _formatUnitCost(row['unit_cost']);
                          final sp = row['sell_price'];
                          final spLabel = sp != null
                              ? ' · Sell ${_formatUnitCost(sp)} ETB'
                              : '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: t.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Qty $q base units · Cost $c ETB$spLabel',
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.82,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Batch $batch · Expiry $exp',
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () => _showAddLineDialog(isPharmacist: isPharmacist),
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  _lineItems.isEmpty ? 'Add first line' : 'Add another line',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _lineItems.isEmpty
                    ? 'Lines are added in a focused popup so this page stays about the purchase.'
                    : 'Add more batches without scrolling through the whole editor.',
                style: t.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: cs.error)),
        ],
        const SizedBox(height: 12),
        if (_lineItems.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Receive goods posts each line’s quantity (shown above) into stock for this branch.',
            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _saving || _lineItems.isEmpty ? null : _receive,
          icon: const Icon(Icons.inventory_rounded),
          label: const Text('Receive goods'),
        ),
      ],
    );

    if (_loading) {
      if (isEditMode) {
        return Scaffold(
          appBar: pharmacyPageAppBar(
            context,
            title: title,
            actions: [
              TextButton(
                onPressed: () => context.go('/pharmacy/purchases'),
                child: const Text('All purchases'),
              ),
            ],
          ),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (isEditMode) {
      return Scaffold(
        appBar: pharmacyPageAppBar(
          context,
          title: title,
          actions: [
            TextButton(
              onPressed: () => context.go('/pharmacy/purchases'),
              child: const Text('All purchases'),
            ),
          ],
        ),
        body: formScroll,
      );
    }

    return formScroll;
  }
}

class _AddLineFields {
  const _AddLineFields({
    required this.medicineId,
    required this.batch,
    required this.expiryText,
    required this.qty,
    required this.cost,
    this.sellPrice,
  });

  final String medicineId;
  final String batch;
  final String expiryText;
  final num qty;
  final num cost;
  final num? sellPrice;
}

/// Owns dialog [TextEditingController]s so they are disposed only after the
/// route is removed (avoids "used after being disposed" when saving).
class _AddMedicineFromPurchaseDialog extends StatefulWidget {
  const _AddMedicineFromPurchaseDialog({
    required this.teamId,
    required this.branchId,
    required this.categories,
    required this.catalog,
  });

  final String teamId;
  final String branchId;
  final List<Map<String, dynamic>> categories;
  final List<MedicineCatalogEntry> catalog;

  @override
  State<_AddMedicineFromPurchaseDialog> createState() =>
      _AddMedicineFromPurchaseDialogState();
}

class _AddMedicineFromPurchaseDialogState
    extends State<_AddMedicineFromPurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _generic;
  late final TextEditingController _code;
  late final TextEditingController _barcode;
  late final TextEditingController _subcategory;
  late final TextEditingController _country;
  late final TextEditingController _presentation;
  late final TextEditingController _strength;
  late final TextEditingController _dosageForm;
  late String _categoryKey;
  bool _saving = false;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _generic = TextEditingController();
    _code = TextEditingController();
    _barcode = TextEditingController();
    _subcategory = TextEditingController();
    _country = TextEditingController();
    _presentation = TextEditingController();
    _strength = TextEditingController();
    _dosageForm = TextEditingController();
    _categoryKey = widget.categories.first['id'] as String;
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

  Future<void> _onSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _dialogError = null;
    });
    try {
      final codeRaw = _code.text.trim();
      final inserted = await Supabase.instance.client
          .from('medicines')
          .insert({
            'team_id': widget.teamId,
            'branch_id': widget.branchId,
            'name': _name.text.trim(),
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
            'purchase_price': 0,
            'selling_price': 0,
          })
          .select(
            'id, name, manual_code, barcode, generic_name, subcategory, country, presentation, strength, dosage_form',
          )
          .single();
      if (!mounted) return;
      Navigator.of(context).pop(Map<String, dynamic>.from(inserted));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _dialogError = mapFormError(e));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Add medicine'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MedicineCatalogAutocompleteField(
                  controller: _generic,
                  catalog: widget.catalog,
                  label: 'Generic name',
                  hintText: 'Search by generic, brand, or strength',
                  displayTextForOption: (entry) =>
                      entry.genericName ?? entry.name,
                  onSelected: _applyCatalogEntry,
                ),
                const SizedBox(height: 10),
                MedicineCatalogAutocompleteField(
                  controller: _name,
                  catalog: widget.catalog,
                  label: 'Brand / trade name',
                  hintText: 'e.g. Aldaz, Panadol',
                  onSelected: _applyCatalogEntry,
                  validator: (v) => FormValidators.requiredText(
                    v,
                    label: 'Brand / trade name',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: 'Manual code (optional)',
                    helperText: 'Unique per branch when set',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _barcode,
                  decoration: const InputDecoration(
                    labelText: 'Barcode (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey(_categoryKey),
                  initialValue: _categoryKey,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: widget.categories
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c['id'] as String,
                          child: Text(c['name'] as String? ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _categoryKey = value);
                          }
                        },
                  validator: (value) =>
                      value == null ? 'Select a category' : null,
                ),
                const SizedBox(height: 10),
                MedicineOptionalDetailsSection(
                  subcategory: _subcategory,
                  country: _country,
                  presentation: _presentation,
                  strength: _strength,
                  dosageForm: _dosageForm,
                ),
                if (_dialogError != null) ...[
                  const SizedBox(height: 10),
                  Text(_dialogError!, style: TextStyle(color: cs.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _onSave,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
