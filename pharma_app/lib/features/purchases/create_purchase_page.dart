import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/branch_change_guard_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/slash_dd_mm_yyyy_input.dart';
import '../medicines/searchable_picker_fields.dart';

class CreatePurchasePage extends ConsumerStatefulWidget {
  const CreatePurchasePage({super.key});

  @override
  ConsumerState<CreatePurchasePage> createState() => _CreatePurchasePageState();
}

class _CreatePurchasePageState extends ConsumerState<CreatePurchasePage> {
  static const _guardKey = 'create_purchase_page';
  final _formKey = GlobalKey<FormState>();
  String? _supplierId;
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _medicines = [];
  String? _selectedMedicineId;
  final _invoice = TextEditingController();
  final _batch = TextEditingController();
  final _expiry = TextEditingController();
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _lastPurchaseId;

  @override
  void initState() {
    super.initState();
    _invoice.addListener(_syncDirtyState);
    _batch.addListener(_syncDirtyState);
    _expiry.addListener(_syncDirtyState);
    _qty.addListener(_syncDirtyState);
    _cost.addListener(_syncDirtyState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(branchChangeGuardProvider.notifier)
          .register(_guardKey, onDiscard: _discardChanges);
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
    ref.read(branchChangeGuardProvider.notifier).unregister(_guardKey);
    _invoice.dispose();
    _batch.dispose();
    _expiry.dispose();
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _selectedMedicineId != null ||
      (_supplierId != null &&
          _suppliers.isNotEmpty &&
          _supplierId != _suppliers.first['id']) ||
      _invoice.text.trim().isNotEmpty ||
      _batch.text.trim().isNotEmpty ||
      _expiry.text.trim().isNotEmpty ||
      _qty.text.trim().isNotEmpty ||
      _cost.text.trim().isNotEmpty;

  void _syncDirtyState() {
    ref.read(branchChangeGuardProvider.notifier).setDirty(_guardKey, _isDirty);
  }

  void _discardChanges() {
    if (!mounted) return;
    setState(() {
      _selectedMedicineId = null;
      _invoice.clear();
      _batch.clear();
      _expiry.clear();
      _qty.clear();
      _cost.clear();
      _lastPurchaseId = null;
      _error = null;
      if (_suppliers.isNotEmpty) {
        _supplierId = _suppliers.first['id'] as String;
      } else {
        _supplierId = null;
      }
    });
    ref.read(branchChangeGuardProvider.notifier).clearDirty(_guardKey);
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
      setState(() {
        _suppliers = List<Map<String, dynamic>>.from(sup as List);
        _medicines = List<Map<String, dynamic>>.from(med as List);
        if (_suppliers.isNotEmpty) {
          _supplierId = _suppliers.first['id'] as String;
        }
      });
    } catch (e) {
      setState(
        () => _error = 'Failed to load suppliers or medicines. Please refresh.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveDraft() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null || _supplierId == null) {
      setState(() => _error = 'Select supplier and branch first');
      return;
    }
    final mid = _selectedMedicineId;
    if (mid == null) {
      setState(() => _error = 'Select a medicine');
      return;
    }
    final qty = num.tryParse(_qty.text);
    final cost = num.tryParse(_cost.text);
    final expiryError = slashDdMmYyyyExpiryError(
      _expiry.text,
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    );
    final expiryIso = slashDdMmYyyyToIso(_expiry.text);
    if (qty == null ||
        qty <= 0 ||
        cost == null ||
        cost < 0 ||
        expiryError != null ||
        expiryIso == null) {
      setState(() => _error = 'Enter valid quantity and unit cost');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
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
          .select('id')
          .single();
      final pid = purchase['id'] as String;
      await Supabase.instance.client.from('purchase_items').insert({
        'purchase_id': pid,
        'medicine_id': mid,
        'batch_no': _batch.text.trim(),
        'expiry_date': expiryIso,
        'qty_base_unit': qty,
        'unit_cost': cost,
      });
      setState(() => _lastPurchaseId = pid);
      _syncDirtyState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft saved. You can now receive goods.'),
          ),
        );
      }
    } catch (_) {
      setState(
        () => _error =
            'Could not save draft purchase. Check inputs and try again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _receive() async {
    final id = _lastPurchaseId;
    if (id == null) {
      setState(() => _error = 'Save a draft purchase first');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Receive goods?'),
        content: const Text(
          'This posts stock into inventory for the saved draft purchase. Continue?',
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase received and stock updated.')),
        );
        ref.read(branchChangeGuardProvider.notifier).clearDirty(_guardKey);
        context.pop();
      }
    } catch (_) {
      setState(() => _error = 'Could not receive this purchase right now.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('New purchase')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
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
                  onChanged: (v) {
                    setState(() => _supplierId = v);
                    _syncDirtyState();
                  },
                  validator: (value) =>
                      value == null ? 'Select a supplier' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _invoice,
                  decoration: const InputDecoration(
                    labelText: 'Invoice reference',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Line item',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                MedicineAutocompleteField(
                  rows: _medicines,
                  initialMedicineId: _selectedMedicineId,
                  label: 'Medicine',
                  validator: (_) =>
                      _selectedMedicineId == null ? 'Select a medicine' : null,
                  onPicked: (row) {
                    setState(() => _selectedMedicineId = row['id'] as String);
                    _syncDirtyState();
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _batch,
                  decoration: const InputDecoration(labelText: 'Batch no'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Enter batch number'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _expiry,
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}$'),
                    ),
                  ],
                  decoration: const InputDecoration(labelText: 'Qty base unit'),
                  validator: (value) {
                    final qty = num.tryParse(value ?? '');
                    if (qty == null || qty <= 0) {
                      return 'Enter quantity greater than 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}$'),
                    ),
                  ],
                  decoration: const InputDecoration(labelText: 'Unit cost'),
                  validator: (value) {
                    final cost = num.tryParse(value ?? '');
                    if (cost == null || cost < 0) {
                      return 'Enter a valid unit cost';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _saveDraft,
            child: const Text('Save draft'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _saving ? null : _receive,
            child: const Text('Receive goods'),
          ),
        ],
      ),
    );
  }
}
