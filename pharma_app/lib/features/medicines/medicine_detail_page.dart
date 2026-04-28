import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/app_error_state.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await Supabase.instance.client
          .from('medicines')
          .select()
          .eq('id', widget.medicineId)
          .single();
      final branchId = ref.read(selectedBranchIdProvider);
      var batchesQuery = Supabase.instance.client
          .from('medicine_batches')
          .select()
          .eq('medicine_id', widget.medicineId);
      if (branchId != null) {
        batchesQuery = batchesQuery.eq('branch_id', branchId);
      }
      final batches = await batchesQuery.order('expiry_date');
      final conv = await Supabase.instance.client
          .from('unit_conversions')
          .select()
          .eq('medicine_id', widget.medicineId);
      setState(() {
        _medicine = Map<String, dynamic>.from(m);
        _batches = List<Map<String, dynamic>>.from(batches as List);
        _conversions = List<Map<String, dynamic>>.from(conv as List);
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
        'batch_no': payload.batchNo,
        'expiry_date': payload.expiry,
        'quantity_in_base_unit': 0,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<({String batchNo, String expiry})?> _showAddBatchDialog() async {
    final batchCtl = TextEditingController();
    final expiryCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? selectedExpiry;
    final value = await showDialog<({String batchNo, String expiry})>(
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
                decoration: const InputDecoration(labelText: 'Batch number'),
                autofocus: true,
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Enter batch number' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: expiryCtl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Expiry date',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedExpiry ?? DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked == null) return;
                  selectedExpiry = picked;
                  expiryCtl.text =
                      '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                },
                validator: (_) => selectedExpiry == null ? 'Pick expiry date' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(
                ctx,
                (batchNo: batchCtl.text.trim(), expiry: expiryCtl.text.trim()),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    batchCtl.dispose();
    expiryCtl.dispose();
    return value;
  }

  Future<({String fromUnit, String toUnit, num multiplier})?> _showAddConversionDialog() async {
    final fromCtl = TextEditingController();
    final toCtl = TextEditingController();
    final multiplierCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<({String fromUnit, String toUnit, num multiplier})>(
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
                    (value == null || value.trim().isEmpty) ? 'Enter from unit' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: toCtl,
                decoration: const InputDecoration(labelText: 'To unit'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Enter to unit' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: multiplierCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}$'))],
                decoration: const InputDecoration(labelText: 'Multiplier (> 0)'),
                validator: (value) {
                  final parsed = num.tryParse((value ?? '').trim());
                  if (parsed == null || parsed <= 0) return 'Enter a multiplier greater than 0';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(
                ctx,
                (
                  fromUnit: fromCtl.text.trim(),
                  toUnit: toCtl.text.trim(),
                  multiplier: num.parse(multiplierCtl.text.trim()),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    fromCtl.dispose();
    toCtl.dispose();
    multiplierCtl.dispose();
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
    final m = _medicine!;
    return Scaffold(
      appBar: AppBar(title: Text(m['name'] as String? ?? 'Medicine')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Manual code'),
            subtitle: Text(m['manual_code'] as String? ?? ''),
          ),
          ListTile(
            title: const Text('Generic'),
            subtitle: Text(m['generic_name'] as String? ?? '—'),
          ),
          ListTile(
            title: const Text('Prices'),
            subtitle: Text(
              'Buy ${m['purchase_price']} · Sell ${m['selling_price']}',
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
                subtitle: Text('Exp ${b['expiry_date']} · qty ${b['quantity_in_base_unit']}'),
              ),
            ),
          const Divider(),
          Row(
            children: [
              Text('Unit conversions', style: Theme.of(context).textTheme.titleMedium),
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
                title: Text('${u['from_unit']} → ${u['to_unit']} × ${u['multiplier']}'),
              ),
            ),
        ],
      ),
    );
  }
}
