import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/branch_change_guard_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/slash_dd_mm_yyyy_input.dart';
import 'stock_in_row_state.dart';
import '../medicines/scan/medicine_lookup_resolver.dart';
import '../medicines/scan/medicine_scan_controller.dart';
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

enum _LookupTarget { single, bulk }

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
  late final BranchChangeGuard _branchGuard;

  final _singleFormKey = GlobalKey<FormState>();
  final _batchNo = TextEditingController();
  final _expiry = TextEditingController();
  final _qty = TextEditingController();
  final _singleLookupFocus = FocusNode();
  List<Map<String, dynamic>> _medicines = [];
  String? _selectedMedicineId;
  bool _singleLoading = false;

  final List<_BulkLine> _bulkLines = [_BulkLine()];
  final List<_BulkLine> _retiredBulkLines = [];
  int _activeBulkIndex = 0;
  bool _bulkSubmitting = false;

  bool _bootstrapping = true;
  String? _error;
  final _resolver = const MedicineLookupResolver();
  List<Map<String, dynamic>> _lookupMatches = [];
  _LookupTarget? _lookupTarget;
  int? _lookupBulkIndex;

  @override
  void initState() {
    super.initState();
    _branchGuard = ref.read(branchChangeGuardProvider.notifier);
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
      _branchGuard.register(_guardKey, onDiscard: _discardAll);
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
    _branchGuard.unregister(_guardKey);
    _batchNo.dispose();
    _expiry.dispose();
    _qty.dispose();
    _singleLookupFocus.dispose();
    for (final l in _bulkLines) {
      l.dispose();
    }
    for (final l in _retiredBulkLines) {
      l.dispose();
    }
    super.dispose();
  }

  void _retireLine(_BulkLine line) {
    _retiredBulkLines.add(line);
  }

  DateTime get _today =>
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  bool get _singleDirty =>
      _selectedMedicineId != null ||
      _batchNo.text.trim().isNotEmpty ||
      _expiry.text.trim().isNotEmpty ||
      _qty.text.trim().isNotEmpty;

  bool get _bulkDirty => _bulkLines.any(
    (l) =>
        l.medicineId != null ||
        l.batchNo.text.trim().isNotEmpty ||
        l.qty.text.trim().isNotEmpty ||
        l.expiry.text.trim().isNotEmpty,
  );

  void _syncDirtyState() {
    _branchGuard.setDirty(_guardKey, _singleDirty || _bulkDirty);
  }

  void _discardAll() {
    if (!mounted) return;
    for (final l in _bulkLines) {
      _retireLine(l);
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
      _lookupMatches = [];
      _lookupTarget = null;
      _lookupBulkIndex = null;
      _activeBulkIndex = 0;
      _error = null;
    });
    _branchGuard.clearDirty(_guardKey);
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
      final branchId = ref.read(selectedBranchIdProvider);
      if (branchId == null) {
        if (!mounted) return;
        setState(() => _error = 'Please select a branch.');
        return;
      }
      final data = await Supabase.instance.client
          .from('medicines')
          .select('id, name, manual_code, barcode, generic_name')
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(
        () => _medicines = List<Map<String, dynamic>>.from(data as List),
      );
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
            'batch_no': _batchNo.text.trim().isEmpty
                ? null
                : _batchNo.text.trim(),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved stock line.')));
        setState(() {
          _selectedMedicineId = null;
          _batchNo.clear();
          _expiry.clear();
          _qty.clear();
          _lookupMatches = [];
          _lookupTarget = null;
          _lookupBulkIndex = null;
        });
        _syncDirtyState();
      }
    } catch (error) {
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _singleLoading = false);
    }
  }

  Future<void> _scanForSingle() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) return;
    String? scan;
    try {
      scan = await showCameraScanSheet(context);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Camera scanning is unavailable here. Use search to pick medicine.',
      );
      return;
    }
    if (scan == null || scan.isEmpty) return;
    await _resolveLookup(
      query: scan,
      target: _LookupTarget.single,
      focusAfterApply: _singleLookupFocus,
    );
  }

  Future<void> _scanForBulkLine(_BulkLine line) async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) return;
    String? scan;
    try {
      scan = await showCameraScanSheet(context);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Camera scanning is unavailable here. Use search to pick medicine.',
      );
      return;
    }
    if (scan == null || scan.isEmpty) return;
    await _resolveLookup(
      query: scan,
      target: _LookupTarget.bulk,
      bulkIndex: _activeBulkIndex,
    );
  }

  Future<void> _showAddMedicineDialog({
    required _LookupTarget target,
    int? bulkIndex,
  }) async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Please select a branch first.');
      return;
    }
    List<Map<String, dynamic>> categories;
    try {
      final data = await ref.read(activeBranchMedicineCategoriesProvider.future);
      categories = List<Map<String, dynamic>>.from(data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load categories. Please retry.');
      return;
    }
    if (categories.isEmpty) {
      setState(
        () => _error = 'Create at least one category before adding medicine.',
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final generic = TextEditingController();
    final code = TextEditingController();
    final barcode = TextEditingController();
    final purchase = TextEditingController(text: '0');
    final selling = TextEditingController(text: '0');
    String? categoryId = categories.first['id'] as String?;
    var saving = false;
    String? dialogError;

    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Add medicine'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Name'),
                          validator: (v) =>
                              FormValidators.requiredText(v, label: 'Name'),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: generic,
                          decoration: const InputDecoration(
                            labelText: 'Generic name (optional)',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: code,
                          decoration: const InputDecoration(
                            labelText: 'Manual code (unique)',
                          ),
                          validator: (v) => FormValidators.requiredText(
                            v,
                            label: 'Manual code',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: barcode,
                          decoration: const InputDecoration(
                            labelText: 'Barcode (optional)',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: purchase,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Purchase price',
                          ),
                          validator: (v) => FormValidators.nonNegativeNumber(
                            v,
                            label: 'Purchase price',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: selling,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Selling price',
                          ),
                          validator: (v) => FormValidators.nonNegativeNumber(
                            v,
                            label: 'Selling price',
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: categoryId,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items: categories
                              .map(
                                (c) => DropdownMenuItem<String>(
                                  value: c['id'] as String,
                                  child: Text(c['name'] as String? ?? ''),
                                ),
                              )
                              .toList(),
                          onChanged: saving
                              ? null
                              : (value) =>
                                    setDialogState(() => categoryId = value),
                          validator: (value) =>
                              value == null ? 'Select a category' : null,
                        ),
                        if (dialogError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            dialogError!,
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
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          setDialogState(() {
                            saving = true;
                            dialogError = null;
                          });
                          try {
                            final inserted = await Supabase.instance.client
                                .from('medicines')
                                .insert({
                                  'team_id': teamId,
                                  'branch_id': branchId,
                                  'name': name.text.trim(),
                                  'generic_name': generic.text.trim().isEmpty
                                      ? null
                                      : generic.text.trim(),
                                  'manual_code': code.text.trim(),
                                  'barcode': barcode.text.trim().isEmpty
                                      ? null
                                      : barcode.text.trim(),
                                  'category_id': categoryId,
                                  'purchase_price':
                                      num.tryParse(purchase.text.trim()) ?? 0,
                                  'selling_price':
                                      num.tryParse(selling.text.trim()) ?? 0,
                                })
                                .select(
                                  'id, name, manual_code, barcode, generic_name',
                                )
                                .single();
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop(
                              Map<String, dynamic>.from(
                                inserted as Map<String, dynamic>,
                              ),
                            );
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => dialogError = mapFormError(e));
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => saving = false);
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == null || !mounted) return;
    final createdId = created['id'] as String?;
    if (createdId == null) return;
    setState(() {
      _medicines = [
        created,
        ..._medicines.where((m) => m['id'] != createdId),
      ];
      _error = null;
      _lookupMatches = [];
      _lookupTarget = null;
      _lookupBulkIndex = null;
      if (target == _LookupTarget.single) {
        _selectedMedicineId = createdId;
      } else {
        final idx = bulkIndex ?? _activeBulkIndex;
        if (idx >= 0 && idx < _bulkLines.length) {
          _bulkLines[idx].medicineId = createdId;
          _activeBulkIndex = idx;
        }
      }
    });
    _syncDirtyState();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Medicine added. Continue stock entry.')),
    );
  }

  void _addBulkLine() {
    setState(() {
      final n = _BulkLine();
      n.batchNo.addListener(_syncDirtyState);
      n.qty.addListener(_syncDirtyState);
      n.expiry.addListener(_syncDirtyState);
      _bulkLines.add(n);
      _activeBulkIndex = _bulkLines.length - 1;
    });
    _syncDirtyState();
  }

  void _focusNextBulkRowAfterLookup() {
    final nextIndex = _activeBulkIndex + 1;
    setState(() {
      if (nextIndex < _bulkLines.length) {
        _activeBulkIndex = nextIndex;
      } else {
        final n = _BulkLine();
        n.batchNo.addListener(_syncDirtyState);
        n.qty.addListener(_syncDirtyState);
        n.expiry.addListener(_syncDirtyState);
        _bulkLines.add(n);
        _activeBulkIndex = _bulkLines.length - 1;
      }
    });
    _syncDirtyState();
  }

  Future<void> _addManyRows() async {
    final ctl = TextEditingController(text: '5');
    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add rows'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'How many rows?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctl.text.trim()) ?? 0),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (count == null || count <= 0) return;
    setState(() {
      for (var i = 0; i < count; i++) {
        final n = _BulkLine();
        n.batchNo.addListener(_syncDirtyState);
        n.qty.addListener(_syncDirtyState);
        n.expiry.addListener(_syncDirtyState);
        _bulkLines.add(n);
      }
    });
    _syncDirtyState();
  }

  Future<void> _pasteRowsFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) return;
    var inserted = 0;
    for (final row in lines) {
      final parts = row.split(RegExp(r'\s*,\s*|\t'));
      if (parts.length < 4) continue;
      final result = await _resolver.resolve(
        teamId: teamId,
        branchId: branchId,
        query: parts[0],
      );
      if (result.state != MedicineLookupState.foundSingle) continue;
      final line = _BulkLine()
        ..medicineId = result.matches.first['id'] as String?
        ..batchNo.text = parts[1]
        ..expiry.text = parts[2]
        ..qty.text = parts[3];
      line.batchNo.addListener(_syncDirtyState);
      line.qty.addListener(_syncDirtyState);
      line.expiry.addListener(_syncDirtyState);
      setState(() => _bulkLines.add(line));
      inserted++;
    }
    if (!mounted) return;
    if (inserted > 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Pasted $inserted row(s).')));
    }
    _syncDirtyState();
  }

  void _duplicateBulkLine(int i) {
    final src = _bulkLines[i];
    final copy = _BulkLine()
      ..medicineId = src.medicineId
      ..batchNo.text = src.batchNo.text
      ..qty.text = src.qty.text
      ..expiry.text = src.expiry.text;
    copy.batchNo.addListener(_syncDirtyState);
    copy.qty.addListener(_syncDirtyState);
    copy.expiry.addListener(_syncDirtyState);
    setState(() {
      _bulkLines.insert(i + 1, copy);
      _activeBulkIndex = i + 1;
    });
    _syncDirtyState();
  }

  void _removeBulkLine(int i) {
    if (_bulkLines.length <= 1) return;
    setState(() {
      final r = _bulkLines.removeAt(i);
      _retireLine(r);
      if (_activeBulkIndex >= _bulkLines.length) {
        _activeBulkIndex = _bulkLines.length - 1;
      }
    });
    _syncDirtyState();
  }

  void _resetBulkAfterSuccess() {
    for (final l in _bulkLines) {
      _retireLine(l);
    }
    _bulkLines
      ..clear()
      ..add(_BulkLine());
    _bulkLines.first.batchNo.addListener(_syncDirtyState);
    _bulkLines.first.qty.addListener(_syncDirtyState);
    _bulkLines.first.expiry.addListener(_syncDirtyState);
    setState(() {
      _activeBulkIndex = 0;
      _lookupMatches = [];
      _lookupTarget = null;
      _lookupBulkIndex = null;
    });
    _syncDirtyState();
  }

  StockInRowState _lineState(_BulkLine line) {
    return stockInRowState(
      StockInDraftRow(
        medicineId: line.medicineId,
        batchNo: line.batchNo.text,
        expiryText: line.expiry.text,
        qtyText: line.qty.text,
      ),
      _today,
    );
  }

  int get _readyLineCount => _bulkLines
      .where((line) => _lineState(line) == StockInRowState.ready)
      .length;

  int get _invalidLineCount => _bulkLines
      .where((line) => _lineState(line) == StockInRowState.invalid)
      .length;

  int get _missingLineCount => _bulkLines
      .where((line) => _lineState(line) == StockInRowState.missing)
      .length;

  Color _stateColor(BuildContext context, StockInRowState state) {
    final cs = Theme.of(context).colorScheme;
    return switch (state) {
      StockInRowState.ready => cs.primary,
      StockInRowState.invalid => cs.error,
      StockInRowState.missing => cs.tertiary,
      StockInRowState.empty => cs.outline,
    };
  }

  String _stateLabel(StockInRowState state) {
    return switch (state) {
      StockInRowState.ready => 'Ready',
      StockInRowState.invalid => 'Invalid',
      StockInRowState.missing => 'Missing',
      StockInRowState.empty => 'Empty',
    };
  }

  Future<void> _submitBulkReadyOnly() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch.');
      return;
    }
    final items = <Map<String, dynamic>>[];
    var skipped = 0;
    for (final l in _bulkLines) {
      final mid = l.medicineId;
      final bn = l.batchNo.text.trim();
      final q = num.tryParse(l.qty.text.trim());
      final exRaw = l.expiry.text.trim();
      final state = _lineState(l);
      if (state == StockInRowState.empty) {
        continue;
      }
      if (state != StockInRowState.ready) {
        skipped++;
        continue;
      }
      final expErr = slashDdMmYyyyExpiryError(exRaw, _today);
      if (expErr != null) {
        skipped++;
        continue;
      }
      final iso = slashDdMmYyyyToIso(exRaw);
      if (iso == null) {
        skipped++;
        continue;
      }
      items.add({
        'medicine_id': mid,
        if (bn.isNotEmpty) 'batch_no': bn,
        'expiry_date': iso,
        'qty': q,
      });
    }
    if (items.isEmpty) {
      setState(
        () => _error =
            'No ready rows to save. Fill missing fields or fix invalid rows.',
      );
      return;
    }
    setState(() {
      _bulkSubmitting = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'bulk_stock_in',
        params: {'p_branch_id': branchId, 'p_items': items},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              skipped > 0
                  ? 'Saved ${items.length} row(s). $skipped row(s) need fixes.'
                  : 'Saved ${items.length} row(s).',
            ),
          ),
        );
        final keep = _bulkLines
            .where((line) => _lineState(line) != StockInRowState.ready)
            .toList();
        for (final line in _bulkLines) {
          if (!keep.contains(line)) {
            _retireLine(line);
          }
        }
        if (keep.isEmpty) {
          _resetBulkAfterSuccess();
        } else {
          setState(() {
            _bulkLines
              ..clear()
              ..addAll(keep);
            _activeBulkIndex = 0;
          });
          _syncDirtyState();
        }
      }
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _bulkSubmitting = false);
    }
  }

  static final _slashFmt = [SlashDdMmYyyyInputFormatter()];

  Future<void> _resolveLookup({
    required String query,
    required _LookupTarget target,
    int? bulkIndex,
    FocusNode? focusAfterApply,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) return;
    final result = await _resolver.resolve(
      teamId: teamId,
      branchId: branchId,
      query: trimmed,
    );
    if (!mounted) return;
    if (result.state == MedicineLookupState.foundSingle) {
      _applyLookupMatch(
        result.matches.first,
        target: target,
        bulkIndex: bulkIndex,
        focusAfterApply: focusAfterApply,
      );
      return;
    }
    if (result.state == MedicineLookupState.multipleMatches) {
      setState(() {
        _lookupMatches = result.matches.take(4).toList();
        _lookupTarget = target;
        _lookupBulkIndex = bulkIndex;
        _error = null;
      });
      return;
    }
    setState(() => _error = 'No medicine match for "$trimmed".');
  }

  void _applyLookupMatch(
    Map<String, dynamic> row, {
    required _LookupTarget target,
    int? bulkIndex,
    FocusNode? focusAfterApply,
  }) {
    final id = row['id'] as String?;
    if (id == null) return;
    setState(() {
      if (target == _LookupTarget.single) {
        _selectedMedicineId = id;
      } else {
        final idx = bulkIndex ?? _activeBulkIndex;
        if (idx >= 0 && idx < _bulkLines.length) {
          _bulkLines[idx].medicineId = id;
          _activeBulkIndex = idx;
        }
      }
      _lookupMatches = [];
      _lookupTarget = null;
      _lookupBulkIndex = null;
      _error = null;
    });
    _syncDirtyState();
    if (target == _LookupTarget.bulk) {
      _focusNextBulkRowAfterLookup();
      return;
    }
    if (focusAfterApply != null) {
      focusAfterApply.requestFocus();
    }
  }

  Widget _buildLookupMatches(FocusNode focusAfterApply) {
    if (_lookupMatches.isEmpty || _lookupTarget == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Multiple matches. Tap one:',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _lookupMatches.map((m) {
              final name = m['name'] as String? ?? 'Medicine';
              final code = m['manual_code'] as String? ?? '';
              return ActionChip(
                label: Text(code.isEmpty ? name : '$name ($code)'),
                onPressed: () => _applyLookupMatch(
                  m,
                  target: _lookupTarget!,
                  bulkIndex: _lookupBulkIndex,
                  focusAfterApply: focusAfterApply,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _singleHeader() {
    final selected = _medicines.cast<Map<String, dynamic>?>().firstWhere(
      (m) => m?['id'] == _selectedMedicineId,
      orElse: () => null,
    );
    final selectedName = selected?['name'] as String? ?? '';
    final selectedCode = selected?['manual_code'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MedicineAutocompleteField(
            key: ValueKey('single-med-${_selectedMedicineId ?? 'none'}'),
            rows: _medicines,
            initialMedicineId: _selectedMedicineId,
            label: 'Search medicine',
            onPicked: (row) {
              setState(() => _selectedMedicineId = row['id'] as String);
              _syncDirtyState();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _scanForSingle,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan'),
              ),
              const SizedBox(width: 8),
              if (_selectedMedicineId == null)
                OutlinedButton.icon(
                  onPressed: () =>
                      _showAddMedicineDialog(target: _LookupTarget.single),
                  icon: const Icon(Icons.medication_outlined),
                  label: const Text('Not found? Add medicine'),
                ),
            ],
          ),
          if (_selectedMedicineId != null) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedCode.isEmpty
                            ? selectedName
                            : '$selectedName ($selectedCode)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedMedicineId = null;
                        });
                        _syncDirtyState();
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bulkHeader() {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final t = Theme.of(context).textTheme;
    Widget compactAction({
      required VoidCallback onPressed,
      required IconData icon,
      required String label,
      bool primary = false,
    }) {
      final baseStyle = ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      );
      if (primary) {
        return FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: baseStyle,
        );
      }
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: baseStyle,
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, keyboardOpen ? 8 : 12, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          final actions = <Widget>[
            compactAction(
              onPressed: () => _scanForBulkLine(_bulkLines[_activeBulkIndex]),
              icon: Icons.qr_code_scanner,
              label: 'Scan row ${_activeBulkIndex + 1}',
              primary: true,
            ),
            compactAction(
              onPressed: () => _showAddMedicineDialog(
                target: _LookupTarget.bulk,
                bulkIndex: _activeBulkIndex,
              ),
              icon: Icons.medication_outlined,
              label: 'Add medicine',
            ),
            compactAction(
              onPressed: _addBulkLine,
              icon: Icons.add,
              label: 'Add row',
            ),
            compactAction(
              onPressed: _addManyRows,
              icon: Icons.queue_rounded,
              label: 'Add many',
            ),
            compactAction(
              onPressed: _pasteRowsFromClipboard,
              icon: Icons.content_paste_rounded,
              label: 'Paste',
            ),
          ];
          if (keyboardOpen) {
            return Row(
              children: [
                Expanded(
                  child: Text(
                    'Ready $_readyLineCount/${_bulkLines.length}  •  Row ${_activeBulkIndex + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                compactAction(
                  onPressed: () => _scanForBulkLine(_bulkLines[_activeBulkIndex]),
                  icon: Icons.qr_code_scanner,
                  label: 'Scan',
                  primary: true,
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pick medicine per row, or scan for active row.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 8),
              if (isNarrow)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final action in actions) ...[
                        action,
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Ready $_readyLineCount/${_bulkLines.length}',
                    style: t.labelLarge,
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Active row ${_activeBulkIndex + 1}',
                    style: t.bodySmall,
                  ),
                  if (_invalidLineCount > 0) ...[
                    const SizedBox(width: 14),
                    Text('Invalid $_invalidLineCount', style: t.bodySmall),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBulkList({EdgeInsetsGeometry? padding}) {
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      padding: padding,
      itemCount: _bulkLines.length,
      itemBuilder: (context, i) {
        final line = _bulkLines[i];
        final state = _lineState(line);
        final isSelected = i == _activeBulkIndex;
        final med = _medicines.cast<Map<String, dynamic>?>().firstWhere(
          (m) => m?['id'] == line.medicineId,
          orElse: () => null,
        );
        final medName = med?['name'] as String? ?? 'Select medicine';
        final batch = line.batchNo.text.trim().isEmpty
            ? 'No batch'
            : line.batchNo.text.trim();
        final qty = line.qty.text.trim().isEmpty ? '—' : line.qty.text.trim();
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: InkWell(
            onTap: () => setState(() => _activeBulkIndex = i),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  CircleAvatar(radius: 14, child: Text('${i + 1}')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          medName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Batch: $batch · Qty: $qty',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_stateLabel(state)),
                    side: BorderSide(color: _stateColor(context, state)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBulkDetailPanel({bool floating = false}) {
    final line = _bulkLines[_activeBulkIndex];
    final expErr = line.expiry.text.trim().isEmpty
        ? null
        : slashDdMmYyyyExpiryError(line.expiry.text.trim(), _today);
    final qty = num.tryParse(line.qty.text.trim()) ?? 0;
    final qtyErr = line.qty.text.trim().isEmpty
        ? null
        : (qty <= 0 ? 'Qty must be > 0' : null);
    return Card(
      margin: floating ? EdgeInsets.zero : const EdgeInsets.all(12),
      elevation: floating ? 12 : null,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(floating ? 10 : 12),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Row ${_activeBulkIndex + 1} details',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: 'Duplicate row',
                    onPressed: () => _duplicateBulkLine(_activeBulkIndex),
                  ),
                  if (_bulkLines.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove row',
                      onPressed: () => _removeBulkLine(_activeBulkIndex),
                    ),
                ],
              ),
              MedicineAutocompleteField(
                key: ValueKey(
                  'bulk-med-$_activeBulkIndex-${line.medicineId ?? 'none'}',
                ),
                rows: _medicines,
                initialMedicineId: line.medicineId,
                label: 'Medicine',
                onPicked: (row) {
                  setState(() => line.medicineId = row['id'] as String);
                  _syncDirtyState();
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: line.batchNo,
                decoration: const InputDecoration(
                  labelText: 'Batch number (optional)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: line.expiry,
                keyboardType: TextInputType.number,
                inputFormatters: _slashFmt,
                decoration: slashDdMmYyyyInputDecoration(
                  context,
                  label: 'Expiry',
                ).copyWith(errorText: expErr),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      final current = num.tryParse(line.qty.text.trim()) ?? 0;
                      final next = current > 0 ? current - 1 : 0;
                      setState(() => line.qty.text = next == 0 ? '' : '$next');
                      _syncDirtyState();
                    },
                    icon: const Icon(Icons.remove),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: line.qty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}$'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Qty (base unit)',
                        errorText: qtyErr,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      final current = num.tryParse(line.qty.text.trim()) ?? 0;
                      setState(() => line.qty.text = '${current + 1}');
                      _syncDirtyState();
                    },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = Theme.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Stock in',
          style: t.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
          ),
        ),
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
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: t.colorScheme.onErrorContainer),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),
            ),
          if (_tabs.index == 0) _singleHeader() else _bulkHeader(),
          if (_tabs.index == 0)
            _buildLookupMatches(_singleLookupFocus)
          else
            _buildLookupMatches(_singleLookupFocus),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Form(
                      key: _singleFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _batchNo,
                            decoration: const InputDecoration(
                              labelText: 'Batch number (optional)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _expiry,
                            keyboardType: TextInputType.number,
                            inputFormatters: _slashFmt,
                            decoration: slashDdMmYyyyInputDecoration(
                              context,
                              label: 'Expiry',
                            ),
                            validator: (v) =>
                                slashDdMmYyyyExpiryError(v ?? '', _today),
                          ),
                          const SizedBox(height: 10),
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
                            decoration: const InputDecoration(
                              labelText: 'Qty (base unit)',
                            ),
                            validator: (value) {
                              final q = num.tryParse(value ?? '');
                              if (q == null || q <= 0) {
                                return 'Enter quantity greater than 0';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _singleLoading ? null : _submitSingle,
                            icon: _singleLoading
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('Save and continue'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    if (wide) {
                      return Row(
                        children: [
                          Expanded(flex: 3, child: _buildBulkList()),
                          Expanded(flex: 2, child: _buildBulkDetailPanel()),
                        ],
                      );
                    }
                    if (keyboardOpen) {
                      const editorHeight = 332.0;
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: _buildBulkList(
                              padding: const EdgeInsets.fromLTRB(
                                0,
                                0,
                                0,
                                editorHeight + 12,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: editorHeight,
                              ),
                              child: _buildBulkDetailPanel(floating: true),
                            ),
                          ),
                        ],
                      );
                    }
                    return LayoutBuilder(
                      builder: (context, mobileConstraints) {
                        final listHeight = mobileConstraints.maxHeight * 0.42;
                        return CustomScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.manual,
                          slivers: [
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: listHeight.clamp(180.0, 280.0),
                                child: _buildBulkList(
                                  padding: const EdgeInsets.only(bottom: 4),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(child: _buildBulkDetailPanel()),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 12),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _tabs.index == 1 && !keyboardOpen
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(
                  color: t.colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: t.colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ready: $_readyLineCount  ·  Missing: $_missingLineCount  ·  Invalid: $_invalidLineCount',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _bulkSubmitting ? null : _submitBulkReadyOnly,
                      icon: _bulkSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Save ready rows'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
