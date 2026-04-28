import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/branch_change_guard_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../medicines/searchable_picker_fields.dart';

class StockAdjustPage extends ConsumerStatefulWidget {
  const StockAdjustPage({super.key});

  @override
  ConsumerState<StockAdjustPage> createState() => _StockAdjustPageState();
}

class _StockAdjustPageState extends ConsumerState<StockAdjustPage> {
  static const _guardKey = 'stock_adjust_page';
  final _formKey = GlobalKey<FormState>();
  final _delta = TextEditingController();
  final _reason = TextEditingController();
  List<Map<String, dynamic>> _medicines = [];
  List<Map<String, dynamic>> _batches = [];
  String? _selectedMedicineId;
  String? _selectedBatchId;
  bool _loading = false;
  bool _bootstrapping = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _delta.addListener(_syncDirtyState);
    _reason.addListener(_syncDirtyState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(branchChangeGuardProvider.notifier).register(
            _guardKey,
            onDiscard: _discardChanges,
          );
    });
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _delta.removeListener(_syncDirtyState);
    _reason.removeListener(_syncDirtyState);
    ref.read(branchChangeGuardProvider.notifier).unregister(_guardKey);
    _delta.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _selectedMedicineId != null ||
      _selectedBatchId != null ||
      _delta.text.trim().isNotEmpty ||
      _reason.text.trim().isNotEmpty;

  void _syncDirtyState() {
    ref.read(branchChangeGuardProvider.notifier).setDirty(_guardKey, _isDirty);
  }

  void _discardChanges() {
    if (!mounted) return;
    setState(() {
      _selectedMedicineId = null;
      _selectedBatchId = null;
      _batches = [];
      _delta.clear();
      _reason.clear();
      _error = null;
    });
    ref.read(branchChangeGuardProvider.notifier).clearDirty(_guardKey);
  }

  Future<void> _bootstrap() async {
    final profile = await ref.read(pharmacyProfileProvider.future);
    final teamId = profile?['team_id'] as String?;
    if (teamId == null) {
      if (mounted) {
        setState(() {
          _bootstrapping = false;
          _error = 'Could not load data for stock adjustment.';
        });
      }
      return;
    }
    try {
      final med = await Supabase.instance.client
          .from('medicines')
          .select('id, name, manual_code, generic_name')
          .eq('team_id', teamId)
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(() => _medicines = List<Map<String, dynamic>>.from(med as List));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load medicine list. Please refresh.');
    } finally {
      if (mounted) setState(() => _bootstrapping = false);
    }
  }

  Future<void> _loadBatchesForMedicine(String medicineId) async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) return;
    try {
      final batches = await Supabase.instance.client
          .from('medicine_batches')
          .select('id, batch_no, expiry_date')
          .eq('medicine_id', medicineId)
          .eq('branch_id', branchId)
          .order('expiry_date');
      final balances = await Supabase.instance.client
          .from('stock_balances')
          .select('medicine_batch_id, qty_base_unit')
          .eq('team_id', teamId)
          .eq('branch_id', branchId);
      final balMap = <String, num>{};
      for (final row in balances as List) {
        final map = row as Map<String, dynamic>;
        balMap[map['medicine_batch_id'] as String] = map['qty_base_unit'] as num? ?? 0;
      }
      final merged = List<Map<String, dynamic>>.from(batches as List).map((row) {
        final id = row['id'] as String;
        return {...row, 'qty_on_hand': balMap[id] ?? 0};
      }).toList();
      if (!mounted) return;
      setState(() {
        _batches = merged;
        _selectedBatchId = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load batches for this medicine.');
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('not found')) {
      return 'Could not find the selected batch.';
    }
    if (raw.contains('violates')) {
      return 'Adjustment failed due to validation rules.';
    }
    return userFacingError(error);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Missing team or branch');
      return;
    }
    final bid = _selectedBatchId ?? '';
    if (bid.isEmpty) {
      setState(() => _error = 'Select a batch to adjust');
      return;
    }
    final delta = num.tryParse(_delta.text);
    if (delta == null || delta == 0) {
      setState(() => _error = 'Non-zero delta required (+ or −)');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply stock adjustment?'),
        content: Text(
          'This will ${delta > 0 ? 'increase' : 'decrease'} stock by ${delta.abs()} base units.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'apply_stock_movement',
        params: {
          'p_team_id': teamId,
          'p_branch_id': branchId,
          'p_batch_id': bid,
          'p_type': 'adjustment',
          'p_qty': delta,
          'p_reason': _reason.text.trim().isEmpty ? 'adjustment' : _reason.text.trim(),
          'p_ref_type': 'adjustment',
          'p_ref_id': null,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock adjustment applied successfully.')),
        );
        ref.read(branchChangeGuardProvider.notifier).clearDirty(_guardKey);
        context.pop();
      }
    } catch (error) {
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Adjust stock')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MedicineAutocompleteField(
                  rows: _medicines,
                  initialMedicineId: _selectedMedicineId,
                  label: 'Medicine',
                  validator: (_) => _selectedMedicineId == null ? 'Select a medicine' : null,
                  onPicked: (row) {
                    final id = row['id'] as String;
                    setState(() => _selectedMedicineId = id);
                    _loadBatchesForMedicine(id);
                    _syncDirtyState();
                  },
                ),
                const SizedBox(height: 12),
                BatchAutocompleteField(
                  rows: _batches,
                  initialBatchId: _selectedBatchId,
                  label: 'Batch',
                  validator: (_) => _selectedBatchId == null ? 'Select a batch' : null,
                  onPicked: (row) {
                    setState(() => _selectedBatchId = row['id'] as String);
                    _syncDirtyState();
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _delta,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}$')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Qty change (base units)',
                    hintText: 'Use negative to reduce stock',
                  ),
                  validator: (value) {
                    final delta = num.tryParse(value ?? '');
                    if (delta == null || delta == 0) return 'Enter a non-zero value';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Enter reason' : null,
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
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
