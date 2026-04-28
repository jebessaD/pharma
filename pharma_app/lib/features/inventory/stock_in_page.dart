import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/branch_change_guard_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/slash_dd_mm_yyyy_input.dart';
import '../medicines/searchable_picker_fields.dart';

class _BulkLine {
  _BulkLine()
      : batchNo = TextEditingController(),
        qty = TextEditingController(),
        expiry = TextEditingController();

  String? medicineId;
  final TextEditingController batchNo;
  final TextEditingController qty;
  final TextEditingController expiry;

  void dispose() {
    batchNo.dispose();
    qty.dispose();
    expiry.dispose();
  }
}

/// Stock in: **One batch** and **Many lines** on one screen (tabs). Expiry: `dd/MM/yyyy` digits + slashes.
class StockInPage extends ConsumerStatefulWidget {
  const StockInPage({super.key, this.openBulkTab = false});

  /// Open with the "Many lines" tab (e.g. `/pharmacy/stock-in?tab=bulk`).
  final bool openBulkTab;

  @override
  ConsumerState<StockInPage> createState() => _StockInPageState();
}

class _StockInPageState extends ConsumerState<StockInPage>
    with SingleTickerProviderStateMixin {
  static const _guardKey = 'stock_in_page';
  late final TabController _tabs;

  final _singleFormKey = GlobalKey<FormState>();
  final _batchNo = TextEditingController();
  final _expiry = TextEditingController();
  final _qty = TextEditingController();
  List<Map<String, dynamic>> _medicines = [];
  String? _selectedMedicineId;
  bool _singleLoading = false;

  final List<_BulkLine> _bulkLines = [_BulkLine()];
  bool _bulkSubmitting = false;

  bool _bootstrapping = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.openBulkTab ? 1 : 0,
    );
    _tabs.addListener(_onTabChanged);
    _batchNo.addListener(_syncDirtyState);
    _expiry.addListener(_syncDirtyState);
    _qty.addListener(_syncDirtyState);
    for (final l in _bulkLines) {
      l.batchNo.addListener(_syncDirtyState);
      l.qty.addListener(_syncDirtyState);
      l.expiry.addListener(_syncDirtyState);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(branchChangeGuardProvider.notifier).register(
            _guardKey,
            onDiscard: _discardAll,
          );
    });
    Future.microtask(_bootstrap);
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) setState(() {});
    _syncDirtyState();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _batchNo.removeListener(_syncDirtyState);
    _expiry.removeListener(_syncDirtyState);
    _qty.removeListener(_syncDirtyState);
    ref.read(branchChangeGuardProvider.notifier).unregister(_guardKey);
    _batchNo.dispose();
    _expiry.dispose();
    _qty.dispose();
    for (final l in _bulkLines) {
      l.dispose();
    }
    super.dispose();
  }

  DateTime get _today =>
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  bool get _singleDirty =>
      _selectedMedicineId != null ||
      _batchNo.text.trim().isNotEmpty ||
      _expiry.text.trim().isNotEmpty ||
      _qty.text.trim().isNotEmpty;

  bool get _bulkDirty =>
      _bulkLines.any(
        (l) =>
            l.medicineId != null ||
            l.batchNo.text.trim().isNotEmpty ||
            l.qty.text.trim().isNotEmpty ||
            l.expiry.text.trim().isNotEmpty,
      );

  void _syncDirtyState() {
    ref.read(branchChangeGuardProvider.notifier).setDirty(_guardKey, _singleDirty || _bulkDirty);
  }

  void _discardAll() {
    if (!mounted) return;
    for (final l in _bulkLines) {
      l.dispose();
    }
    _bulkLines
      ..clear()
      ..add(_BulkLine());
    _bulkLines.first.batchNo.addListener(_syncDirtyState);
    _bulkLines.first.qty.addListener(_syncDirtyState);
    _bulkLines.first.expiry.addListener(_syncDirtyState);
    setState(() {
      _selectedMedicineId = null;
      _batchNo.clear();
      _expiry.clear();
      _qty.clear();
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
          _error = 'Could not load medicines. Please check team setup.';
        });
      }
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('medicines')
          .select('id, name, manual_code, generic_name')
          .eq('team_id', teamId)
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(() => _medicines = List<Map<String, dynamic>>.from(data as List));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Unable to load medicine list. Try again.');
    } finally {
      if (mounted) setState(() => _bootstrapping = false);
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('duplicate key')) {
      return 'This batch already exists for the medicine.';
    }
    if (raw.contains('violates')) {
      return 'Could not save stock. Check required fields and try again.';
    }
    return userFacingError(error);
  }

  Future<void> _submitSingle() async {
    if (!(_singleFormKey.currentState?.validate() ?? false)) return;
    final iso = slashDdMmYyyyToIso(_expiry.text);
    final expErr = slashDdMmYyyyExpiryError(_expiry.text, _today);
    if (expErr != null || iso == null) {
      setState(() => _error = expErr ?? 'Invalid expiry');
      return;
    }
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Please select a branch before recording stock.');
      return;
    }
    final mid = _selectedMedicineId;
    if (mid == null) {
      setState(() => _error = 'Please select a medicine.');
      return;
    }
    final qty = num.tryParse(_qty.text);
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Quantity must be > 0');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply stock in?'),
        content: Text(
          'This will add $qty base units to batch "${_batchNo.text.trim()}" (exp $iso).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _singleLoading = true;
      _error = null;
    });
    try {
      final ins = await Supabase.instance.client
          .from('medicine_batches')
          .insert({
            'team_id': teamId,
            'branch_id': branchId,
            'medicine_id': mid,
            'batch_no': _batchNo.text.trim(),
            'expiry_date': iso,
            'quantity_in_base_unit': 0,
          })
          .select('id')
          .single();
      final batchId = ins['id'] as String;
      await Supabase.instance.client.rpc(
        'apply_stock_movement',
        params: {
          'p_team_id': teamId,
          'p_branch_id': branchId,
          'p_batch_id': batchId,
          'p_type': 'purchase_in',
          'p_qty': qty,
          'p_reason': 'manual_stock_in',
          'p_ref_type': 'manual',
          'p_ref_id': null,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock in recorded successfully.')),
        );
        ref.read(branchChangeGuardProvider.notifier).clearDirty(_guardKey);
        context.pop();
      }
    } catch (error) {
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _singleLoading = false);
    }
  }

  void _addBulkLine() {
    setState(() {
      final n = _BulkLine();
      n.batchNo.addListener(_syncDirtyState);
      n.qty.addListener(_syncDirtyState);
      n.expiry.addListener(_syncDirtyState);
      _bulkLines.add(n);
    });
    _syncDirtyState();
  }

  void _removeBulkLine(int i) {
    if (_bulkLines.length <= 1) return;
    setState(() {
      final r = _bulkLines.removeAt(i);
      r.dispose();
    });
    _syncDirtyState();
  }

  void _resetBulkAfterSuccess() {
    for (final l in _bulkLines) {
      l.dispose();
    }
    _bulkLines
      ..clear()
      ..add(_BulkLine());
    _bulkLines.first.batchNo.addListener(_syncDirtyState);
    _bulkLines.first.qty.addListener(_syncDirtyState);
    _bulkLines.first.expiry.addListener(_syncDirtyState);
    setState(() {});
    _syncDirtyState();
  }

  Future<void> _submitBulk() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch.');
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (final l in _bulkLines) {
      final mid = l.medicineId;
      final bn = l.batchNo.text.trim();
      final q = num.tryParse(l.qty.text.trim());
      final exRaw = l.expiry.text.trim();
      if (mid == null && bn.isEmpty && l.qty.text.trim().isEmpty && exRaw.isEmpty) {
        continue;
      }
      if (mid == null || bn.isEmpty || q == null || q <= 0 || exRaw.isEmpty) {
        setState(() => _error = 'Each row needs medicine, batch, expiry (dd/MM/yyyy), qty > 0.');
        return;
      }
      final expErr = slashDdMmYyyyExpiryError(exRaw, _today);
      if (expErr != null) {
        setState(() => _error = '$expErr (batch $bn)');
        return;
      }
      final iso = slashDdMmYyyyToIso(exRaw);
      if (iso == null) {
        setState(() => _error = 'Invalid expiry for batch $bn');
        return;
      }
      items.add({
        'medicine_id': mid,
        'batch_no': bn,
        'expiry_date': iso,
        'qty': q,
      });
    }
    if (items.isEmpty) {
      setState(() => _error = 'Add at least one complete row.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply all rows?'),
        content: Text('This will create ${items.length} batch(es) and add stock.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _bulkSubmitting = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'bulk_stock_in',
        params: {
          'p_branch_id': branchId,
          'p_items': items,
        },
      );
      if (mounted) {
        ref.read(branchChangeGuardProvider.notifier).clearDirty(_guardKey);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recorded ${items.length} line(s).')),
        );
        _resetBulkAfterSuccess();
        _tabs.animateTo(0);
      }
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _bulkSubmitting = false);
    }
  }

  static final _slashFmt = [SlashDdMmYyyyInputFormatter()];

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock in'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'One batch'),
            Tab(text: 'Many lines'),
          ],
        ),
        actions: [
          if (_tabs.index == 1)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add row',
              onPressed: _addBulkLine,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: t.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: Text(_error!, style: TextStyle(color: t.colorScheme.onErrorContainer))),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Form(
                      key: _singleFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          MedicineAutocompleteField(
                            rows: _medicines,
                            initialMedicineId: _selectedMedicineId,
                            label: 'Medicine',
                            validator: (_) => _selectedMedicineId == null ? 'Select a medicine' : null,
                            onPicked: (row) {
                              setState(() => _selectedMedicineId = row['id'] as String);
                              _syncDirtyState();
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _batchNo,
                            decoration: const InputDecoration(labelText: 'Batch number'),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty) ? 'Enter batch number' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _expiry,
                            keyboardType: TextInputType.number,
                            inputFormatters: _slashFmt,
                            decoration: const InputDecoration(
                              labelText: 'Expiry',
                              hintText: 'dd/MM/yyyy',
                              helperText: 'Type digits only — slashes appear automatically',
                            ),
                            validator: (v) => slashDdMmYyyyExpiryError(v ?? '', _today),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _qty,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
                            ],
                            decoration: const InputDecoration(labelText: 'Qty (base unit)'),
                            validator: (value) {
                              final q = num.tryParse(value ?? '');
                              if (q == null || q <= 0) return 'Enter quantity greater than 0';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _singleLoading ? null : _submitSingle,
                      child: _singleLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Apply'),
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'One row per medicine/batch. Expiry: dd/MM/yyyy (digits only). Empty rows skipped.',
                      style: t.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_bulkLines.length, (i) {
                      final line = _bulkLines[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text('Row ${i + 1}', style: t.textTheme.titleSmall),
                                  const Spacer(),
                                  if (_bulkLines.length > 1)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _removeBulkLine(i),
                                    ),
                                ],
                              ),
                              MedicineAutocompleteField(
                                rows: _medicines,
                                initialMedicineId: line.medicineId,
                                label: 'Medicine',
                                onPicked: (row) {
                                  setState(() => line.medicineId = row['id'] as String);
                                  _syncDirtyState();
                                },
                              ),
                              TextFormField(
                                controller: line.batchNo,
                                decoration: const InputDecoration(labelText: 'Batch number'),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: line.expiry,
                                keyboardType: TextInputType.number,
                                inputFormatters: _slashFmt,
                                decoration: const InputDecoration(
                                  labelText: 'Expiry',
                                  hintText: 'dd/MM/yyyy',
                                ),
                                onChanged: (_) => _syncDirtyState(),
                              ),
                              TextFormField(
                                controller: line.qty,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
                                ],
                                decoration: const InputDecoration(labelText: 'Qty (base unit)'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    FilledButton(
                      onPressed: _bulkSubmitting ? null : _submitBulk,
                      child: _bulkSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Apply all rows'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
