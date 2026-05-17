import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/slash_dd_mm_yyyy_input.dart';

class MedicineDetailPage extends ConsumerStatefulWidget {
  const MedicineDetailPage({super.key, required this.medicineId});

  final String medicineId;

  @override
  ConsumerState<MedicineDetailPage> createState() => _MedicineDetailPageState();
}

class _MedicineDetailPageState extends ConsumerState<MedicineDetailPage> {
  Map<String, dynamic>? _medicine;
  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _conversions = [];
  bool _loading = true;
  bool _savingCore = false;
  String? _error;
  final _coreFormKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _manualCodeCtl = TextEditingController();
  final _genericCtl = TextEditingController();
  final _purchasePriceCtl = TextEditingController();
  final _sellingPriceCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _manualCodeCtl.dispose();
    _genericCtl.dispose();
    _purchasePriceCtl.dispose();
    _sellingPriceCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branchId = ref.read(selectedBranchIdProvider);
      if (branchId == null) {
        setState(() => _error = 'Select a branch first.');
        return;
      }
      final m = await Supabase.instance.client
          .from('medicines')
          .select()
          .eq('id', widget.medicineId)
          .eq('branch_id', branchId)
          .single();
      final batches = await Supabase.instance.client
          .from('medicine_batches')
          .select()
          .eq('medicine_id', widget.medicineId)
          .eq('branch_id', branchId)
          .order('expiry_date');
      final conv = await Supabase.instance.client
          .from('unit_conversions')
          .select()
          .eq('medicine_id', widget.medicineId);
      setState(() {
        _medicine = Map<String, dynamic>.from(m);
        _batches = List<Map<String, dynamic>>.from(batches as List);
        _conversions = List<Map<String, dynamic>>.from(conv as List);
        _nameCtl.text = '${_medicine?['name'] ?? ''}';
        _manualCodeCtl.text = '${_medicine?['manual_code'] ?? ''}';
        _genericCtl.text = '${_medicine?['generic_name'] ?? ''}';
        _purchasePriceCtl.text = '${_medicine?['purchase_price'] ?? ''}';
        _sellingPriceCtl.text = '${_medicine?['selling_price'] ?? ''}';
      });
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addBatch() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch in the app bar');
      return;
    }
    final payload = await _showAddBatchDialog();
    if (!context.mounted || payload == null) return;
    try {
      await Supabase.instance.client.from('medicine_batches').insert({
        'team_id': teamId,
        'branch_id': branchId,
        'medicine_id': widget.medicineId,
        'batch_no': (payload.batchNo == null || payload.batchNo!.trim().isEmpty)
            ? null
            : payload.batchNo!.trim(),
        'expiry_date': payload.expiry,
        'quantity_in_base_unit': 0,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
  }

  Future<void> _addConversion() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    if (teamId == null) return;
    final payload = await _showAddConversionDialog();
    if (!context.mounted || payload == null) return;
    try {
      await Supabase.instance.client.from('unit_conversions').insert({
        'team_id': teamId,
        'medicine_id': widget.medicineId,
        'from_unit': payload.fromUnit,
        'to_unit': payload.toUnit,
        'multiplier': payload.multiplier,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
  }

  Future<void> _saveCoreDetails() async {
    if (_coreFormKey.currentState?.validate() != true) return;
    final branchId = ref.read(selectedBranchIdProvider);
    if (branchId == null) {
      setState(() => _error = 'Select a branch first.');
      return;
    }
    setState(() => _savingCore = true);
    try {
      final codeRaw = _manualCodeCtl.text.trim();
      await Supabase.instance.client
          .from('medicines')
          .update({
            'name': _nameCtl.text.trim(),
            'manual_code': codeRaw.isEmpty ? null : codeRaw,
            'generic_name': _genericCtl.text.trim().isEmpty
                ? null
                : _genericCtl.text.trim(),
            'purchase_price': num.parse(_purchasePriceCtl.text.trim()),
            'selling_price': num.parse(_sellingPriceCtl.text.trim()),
          })
          .eq('id', widget.medicineId)
          .eq('branch_id', branchId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine details updated')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    } finally {
      if (mounted) setState(() => _savingCore = false);
    }
  }

  Future<({String? batchNo, String expiry})?> _showAddBatchDialog() async {
    final batchCtl = TextEditingController();
    final expiryCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<({String? batchNo, String expiry})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add batch'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: batchCtl,
                decoration: const InputDecoration(
                  labelText: 'Batch number (optional)',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: expiryCtl,
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final iso = slashDdMmYyyyToIso(expiryCtl.text.trim());
              if (iso == null) return;
              Navigator.pop(ctx, (
                batchNo: batchCtl.text.trim().isEmpty
                    ? null
                    : batchCtl.text.trim(),
                expiry: iso,
              ));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    return value;
  }

  Future<({String fromUnit, String toUnit, num multiplier})?>
  _showAddConversionDialog() async {
    final fromCtl = TextEditingController();
    final toCtl = TextEditingController();
    final multiplierCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final value =
        await showDialog<({String fromUnit, String toUnit, num multiplier})>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Add conversion'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: fromCtl,
                    decoration: const InputDecoration(labelText: 'From unit'),
                    autofocus: true,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Enter from unit'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: toCtl,
                    decoration: const InputDecoration(labelText: 'To unit'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Enter to unit'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: multiplierCtl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,4}$'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Multiplier (> 0)',
                    ),
                    validator: (value) {
                      final parsed = num.tryParse((value ?? '').trim());
                      if (parsed == null || parsed <= 0) {
                        return 'Enter a multiplier greater than 0';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.pop(ctx, (
                    fromUnit: fromCtl.text.trim(),
                    toUnit: toCtl.text.trim(),
                    multiplier: num.parse(multiplierCtl.text.trim()),
                  ));
                },
                child: const Text('Add'),
              ),
            ],
          ),
        );
    return value;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _medicine == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Medicine')),
        body: AppErrorState(
          message: _error ?? 'This medicine was not found.',
          onRetry: () {
            _load();
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_nameCtl.text.trim().isEmpty ? 'Medicine' : _nameCtl.text.trim())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Medicine details',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Form(
            key: _coreFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameCtl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _manualCodeCtl,
                  decoration: const InputDecoration(
                    labelText: 'Manual code (optional)',
                    helperText: 'Unique per branch when set',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _genericCtl,
                  decoration: const InputDecoration(labelText: 'Generic'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _purchasePriceCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}$'),
                          ),
                        ],
                        decoration: const InputDecoration(labelText: 'Buy price'),
                        validator: (value) {
                          final parsed = num.tryParse((value ?? '').trim());
                          if (parsed == null || parsed < 0) {
                            return 'Invalid buy';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _sellingPriceCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}$'),
                          ),
                        ],
                        decoration: const InputDecoration(labelText: 'Sell price'),
                        validator: (value) {
                          final parsed = num.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return 'Invalid sell';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _savingCore ? null : _saveCoreDetails,
                    icon: _savingCore
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save details'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Row(
            children: [
              Text('Batches', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addBatch,
                icon: const Icon(Icons.add),
                label: const Text('Add batch'),
              ),
            ],
          ),
          if (_batches.isEmpty)
            const Text('No batches for selected branch.')
          else
            ..._batches.map(
              (b) => ListTile(
                dense: true,
                title: Text(b['batch_no'] as String? ?? ''),
                subtitle: Text(
                  'Exp ${formatDdMmYyyy(b['expiry_date'])} · qty ${b['quantity_in_base_unit']}',
                ),
              ),
            ),
          const Divider(),
          Row(
            children: [
              Text(
                'Unit conversions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addConversion,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          if (_conversions.isEmpty)
            const Text('None')
          else
            ..._conversions.map(
              (u) => ListTile(
                dense: true,
                title: Text(
                  '${u['from_unit']} → ${u['to_unit']} × ${u['multiplier']}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
