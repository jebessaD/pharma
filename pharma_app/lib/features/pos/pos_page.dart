import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/branch_change_guard_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../medicines/medicine_search_bar.dart';

class _SellUnitOption {
  const _SellUnitOption({
    required this.label,
    required this.basesPerUnit,
    required this.storageKey,
  });

  final String label;
  final double basesPerUnit;
  final String storageKey;
}

/// One POS cart row: editable qty/price, batch dropdown (default FEFO), unit chips.
class _PosCartLine {
  _PosCartLine({
    required this.medicineId,
    required this.medicineName,
    required this.listPricePerBase,
    required this.batchesWithQty,
    required this.unitOptions,
  })  : selectedBatchId = batchesWithQty.first['id'] as String,
        selectedUnit = unitOptions.first,
        qtyController = TextEditingController(text: '1'),
        priceController = TextEditingController(text: _fmtPrice(listPricePerBase)),
        reasonController = TextEditingController();

  final String medicineId;
  final String medicineName;
  final num listPricePerBase;
  final List<Map<String, dynamic>> batchesWithQty;
  final List<_SellUnitOption> unitOptions;

  String selectedBatchId;
  _SellUnitOption selectedUnit;
  final TextEditingController qtyController;
  final TextEditingController priceController;
  final TextEditingController reasonController;

  static String _fmtPrice(num n) {
    if (n == n.roundToDouble()) return n.toStringAsFixed(0);
    return n.toStringAsFixed(2);
  }

  num maxQtyBase() {
    for (final b in batchesWithQty) {
      if (b['id'] == selectedBatchId) return (b['qty_on_hand'] as num?) ?? 0;
    }
    return (batchesWithQty.first['qty_on_hand'] as num?) ?? 0;
  }

  void setUnit(_SellUnitOption u) {
    selectedUnit = u;
    qtyController.text = '1';
  }

  void dispose() {
    qtyController.dispose();
    priceController.dispose();
    reasonController.dispose();
  }
}

class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  static const _guardKey = 'pos_page';
  final List<_PosCartLine> _lines = [];
  bool _checkoutLoading = false;
  String? _error;
  String _paymentMethod = 'cash';
  final _referenceNo = TextEditingController();
  final _discountCtl = TextEditingController();
  String? _activeBranchId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(branchChangeGuardProvider.notifier).register(
            _guardKey,
            onDiscard: _discardChanges,
          );
    });
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    ref.read(branchChangeGuardProvider.notifier).unregister(_guardKey);
    _referenceNo.dispose();
    _discountCtl.dispose();
    super.dispose();
  }

  void _discardChanges() {
    if (!mounted) return;
    for (final l in _lines) {
      l.dispose();
    }
    setState(() {
      _lines.clear();
      _error = null;
      _paymentMethod = 'cash';
      _referenceNo.clear();
      _discountCtl.clear();
    });
    ref.read(branchChangeGuardProvider.notifier).clearDirty(_guardKey);
  }

  void _syncDirtyState() {
    final dirty = _lines.isNotEmpty ||
        _referenceNo.text.trim().isNotEmpty ||
        _discountCtl.text.trim().isNotEmpty;
    ref.read(branchChangeGuardProvider.notifier).setDirty(_guardKey, dirty);
  }

  List<_SellUnitOption> _unitOptionsForMedicine(List<Map<String, dynamic>> convRows) {
    final out = <_SellUnitOption>[
      const _SellUnitOption(label: 'Base', basesPerUnit: 1, storageKey: 'base'),
    ];
    for (final c in convRows) {
      final to = (c['to_unit'] as String? ?? '').toLowerCase().trim();
      if (to != 'base') continue;
      final from = (c['from_unit'] as String? ?? 'unit').trim();
      if (from.isEmpty) continue;
      final mult = (c['multiplier'] as num?)?.toDouble() ?? 0;
      if (mult <= 0) continue;
      out.add(_SellUnitOption(label: from, basesPerUnit: mult, storageKey: from));
    }
    return out;
  }

  Future<void> _pickMedicine(Map<String, dynamic> medicine) async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch');
      return;
    }
    final mid = medicine['id'] as String;
    final sell = (medicine['selling_price'] as num?) ?? 0;
    final batches = await Supabase.instance.client
        .from('medicine_batches')
        .select('id, batch_no, expiry_date')
        .eq('medicine_id', mid)
        .eq('branch_id', branchId)
        .order('expiry_date');
    final batchRows = List<Map<String, dynamic>>.from(batches as List);
    if (batchRows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No batches for this medicine at this branch')),
        );
      }
      return;
    }
    final balances = await Supabase.instance.client
        .from('stock_balances')
        .select('medicine_batch_id, qty_base_unit')
        .eq('team_id', teamId)
        .eq('branch_id', branchId);
    final balMap = <String, num>{};
    for (final b in balances as List) {
      final m = b as Map<String, dynamic>;
      balMap[m['medicine_batch_id'] as String] = m['qty_base_unit'] as num? ?? 0;
    }
    final eligible = batchRows.where((row) {
      final id = row['id'] as String;
      return (balMap[id] ?? 0) > 0;
    }).toList()
      ..sort((a, b) {
        final da = a['expiry_date'] as String? ?? '';
        final db = b['expiry_date'] as String? ?? '';
        return da.compareTo(db);
      });
    if (!mounted) return;
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stock on hand for this medicine')),
      );
      return;
    }

    final withQty = eligible
        .map(
          (row) => {
            ...row,
            'qty_on_hand': balMap[row['id'] as String] ?? 0,
          },
        )
        .toList();

    final convData = await Supabase.instance.client
        .from('unit_conversions')
        .select()
        .eq('medicine_id', mid);
    final unitOptions = _unitOptionsForMedicine(List<Map<String, dynamic>>.from(convData as List));
    if (!mounted) return;

    final line = _PosCartLine(
      medicineId: mid,
      medicineName: medicine['name'] as String? ?? 'Medicine',
      listPricePerBase: sell,
      batchesWithQty: withQty,
      unitOptions: unitOptions,
    );

    setState(() {
      _lines.add(line);
      _error = null;
    });
    _syncDirtyState();
  }

  void _removeLine(int i) {
    setState(() {
      _lines[i].dispose();
      _lines.removeAt(i);
    });
    _syncDirtyState();
  }

  num get _cartSubtotal {
    num sum = 0;
    for (final line in _lines) {
      final qb = _qtyBaseForLine(line);
      final up = num.tryParse(line.priceController.text.trim());
      if (qb != null && up != null) sum += qb * up;
    }
    return sum;
  }

  num? _qtyBaseForLine(_PosCartLine line) {
    final q = num.tryParse(line.qtyController.text.trim());
    if (q == null || q <= 0) return null;
    return q * line.selectedUnit.basesPerUnit;
  }

  num get _discountAmount {
    final d = num.tryParse(_discountCtl.text.trim());
    if (d == null || d < 0) return 0;
    return d;
  }

  num get _cartTotal {
    final t = _cartSubtotal - _discountAmount;
    return t < 0 ? 0 : t;
  }

  bool _showPriceReason(_PosCartLine line) {
    final pc = num.tryParse(line.priceController.text.trim());
    return pc != null && (pc - line.listPricePerBase).abs() > 0.0001;
  }

  String? _validateCartForCheckout() {
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final qb = _qtyBaseForLine(line);
      if (qb == null) return 'Line ${i + 1}: enter a valid quantity.';
      final maxB = line.maxQtyBase();
      if (qb > maxB) return 'Line ${i + 1}: quantity exceeds on-hand ($maxB base).';
      final up = num.tryParse(line.priceController.text.trim());
      if (up == null || up < 0) return 'Line ${i + 1}: enter a valid unit price (base).';
      final list = line.listPricePerBase;
      if ((up - list).abs() > 0.0001 && line.reasonController.text.trim().isEmpty) {
        return 'Line ${i + 1}: price differs from list — enter a reason.';
      }
    }
    return null;
  }

  Future<void> _checkout() async {
    final branchId = ref.read(selectedBranchIdProvider);
    if (branchId == null) {
      setState(() => _error = 'Select a branch');
      return;
    }
    if (_lines.isEmpty) return;
    final disc = _discountAmount;
    if (disc > _cartSubtotal) {
      setState(() => _error = 'Discount cannot exceed subtotal.');
      return;
    }
    final v = _validateCartForCheckout();
    if (v != null) {
      setState(() => _error = v);
      return;
    }
    setState(() {
      _checkoutLoading = true;
      _error = null;
    });
    try {
      final items = <Map<String, dynamic>>[];
      for (final line in _lines) {
        final qb = _qtyBaseForLine(line)!;
        final up = num.parse(line.priceController.text.trim());
        final list = line.listPricePerBase;
        final reason = (up - list).abs() > 0.0001
            ? line.reasonController.text.trim()
            : null;
        items.add({
          'medicine_batch_id': line.selectedBatchId,
          'qty': qb,
          'unit_price': up,
          'price_override_reason': reason,
        });
      }
      final needRef = _paymentMethod == 'mobile_banking';
      final saleId = await Supabase.instance.client.rpc(
        'create_sale',
        params: {
          'p_branch_id': branchId,
          'p_items': items,
          'p_method': _paymentMethod,
          'p_reference_no': needRef && _referenceNo.text.trim().isNotEmpty
              ? _referenceNo.text.trim()
              : null,
          'p_discount_total': disc,
        },
      );
      final id = saleId is String ? saleId : saleId.toString();
      for (final l in _lines) {
        l.dispose();
      }
      setState(() {
        _lines.clear();
        _paymentMethod = 'cash';
        _referenceNo.clear();
        _discountCtl.clear();
      });
      _syncDirtyState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale completed')));
        context.push('/pharmacy/receipt/$id');
      }
    } catch (e) {
      setState(() => _error = mapFormError(e));
    } finally {
      if (mounted) setState(() => _checkoutLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String? ?? '';
    final branchId = ref.watch(selectedBranchIdProvider);
    final t = Theme.of(context);

    if (_activeBranchId != null && branchId != null && _activeBranchId != branchId && _lines.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _discardChanges();
      });
    }
    _activeBranchId = branchId;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (teamId.isEmpty)
            const Text('Sign in required')
          else
            MedicineSearchBar(
              teamId: teamId,
              onMedicineSelected: _pickMedicine,
            ),
          const SizedBox(height: 12),
          Text('Cart', style: t.textTheme.titleMedium),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
            ),
          Expanded(
            child: _lines.isEmpty
                ? Center(
                    child: Text(
                      'Search a medicine to add a line.\nDefault batch = nearest expiry; change below.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: _lines.length,
                    itemBuilder: (context, i) {
                      final line = _lines[i];
                      final qb = _qtyBaseForLine(line);
                      final up = num.tryParse(line.priceController.text.trim());
                      final lineTotal = (qb != null && up != null) ? qb * up : null;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      line.medicineName,
                                      style: t.textTheme.titleSmall,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _removeLine(i),
                                  ),
                                ],
                              ),
                              InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Batch (default: nearest expiry)',
                                  isDense: true,
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: line.selectedBatchId,
                                    items: line.batchesWithQty.map((b) {
                                      final id = b['id'] as String;
                                      final bn = b['batch_no'] as String? ?? '';
                                      final ex = b['expiry_date'] as String? ?? '';
                                      final qh = b['qty_on_hand'] as num? ?? 0;
                                      return DropdownMenuItem<String>(
                                        value: id,
                                        child: Text('$bn · $ex · $qh', overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList(),
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(() => line.selectedBatchId = v);
                                      _syncDirtyState();
                                    },
                                  ),
                                ),
                              ),
                              if (line.unitOptions.length > 1) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: line.unitOptions.map((u) {
                                    final sel = line.selectedUnit.storageKey == u.storageKey;
                                    return FilterChip(
                                      label: Text(u.label),
                                      selected: sel,
                                      onSelected: (v) {
                                        if (!v) return;
                                        setState(() => line.setUnit(u));
                                        _syncDirtyState();
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: line.qtyController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}$')),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: line.selectedUnit.basesPerUnit == 1
                                            ? 'Qty (base)'
                                            : 'Qty (${line.selectedUnit.label})',
                                        isDense: true,
                                      ),
                                      onChanged: (_) {
                                        setState(() {});
                                        _syncDirtyState();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: line.priceController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: 'Price / base (ETB)',
                                        isDense: true,
                                      ),
                                      onChanged: (_) {
                                        setState(() {});
                                        _syncDirtyState();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'Max ${line.maxQtyBase()} base · line ${lineTotal == null ? '—' : '${lineTotal.toStringAsFixed(2)} ETB'}',
                                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                              ),
                              if (_showPriceReason(line)) ...[
                                const SizedBox(height: 6),
                                TextField(
                                  controller: line.reasonController,
                                  decoration: const InputDecoration(
                                    labelText: 'Price override reason',
                                    isDense: true,
                                  ),
                                  onChanged: (_) => _syncDirtyState(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_lines.isNotEmpty) ...[
            Text(
              'Subtotal: ${_cartSubtotal.toStringAsFixed(2)} ETB',
              textAlign: TextAlign.right,
              style: t.textTheme.bodyLarge,
            ),
            TextField(
              controller: _discountCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
              ],
              decoration: const InputDecoration(
                labelText: 'Cart discount (ETB)',
                hintText: '0',
                isDense: true,
              ),
              onChanged: (_) {
                setState(() {});
                _syncDirtyState();
              },
            ),
            Text(
              'Total: ${_cartTotal.toStringAsFixed(2)} ETB',
              textAlign: TextAlign.right,
              style: t.textTheme.titleMedium,
            ),
          ],
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'cash', label: Text('Cash')),
              ButtonSegment<String>(value: 'mobile_banking', label: Text('Mobile')),
            ],
            selected: {_paymentMethod},
            onSelectionChanged: (selection) {
              setState(() => _paymentMethod = selection.first);
              _syncDirtyState();
            },
          ),
          if (_paymentMethod == 'mobile_banking') ...[
            const SizedBox(height: 6),
            TextField(
              controller: _referenceNo,
              decoration: const InputDecoration(
                labelText: 'Mobile payment ref (optional)',
                isDense: true,
              ),
              onChanged: (_) => _syncDirtyState(),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: (_checkoutLoading || _lines.isEmpty) ? null : _checkout,
            child: _checkoutLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Checkout'),
          ),
        ],
      ),
    );
  }
}
