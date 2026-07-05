import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/roles/stock_permissions.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/utils/etb_amount_display.dart';
import '../../core/widgets/slash_dd_mm_yyyy_input.dart';

class BatchRowData {
  const BatchRowData({
    required this.batchId,
    required this.batchNo,
    required this.expiryIso,
    required this.qtyOnHand,
    this.unitCost,
    this.sellPrice,
  });

  final String batchId;
  final String batchNo;
  final String expiryIso;
  final num qtyOnHand;
  final num? unitCost;
  final num? sellPrice;
}

/// Bottom sheet to edit batch qty, prices, and metadata.
Future<bool?> showBatchEditSheet({
  required BuildContext context,
  required BatchRowData batch,
  required String teamId,
  required String branchId,
  required String? viewerRole,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _BatchEditSheet(
      batch: batch,
      teamId: teamId,
      branchId: branchId,
      canIncreaseStock: canAddStockInForRole(viewerRole),
    ),
  );
}

class _BatchEditSheet extends StatefulWidget {
  const _BatchEditSheet({
    required this.batch,
    required this.teamId,
    required this.branchId,
    required this.canIncreaseStock,
  });

  final BatchRowData batch;
  final String teamId;
  final String branchId;
  final bool canIncreaseStock;

  @override
  State<_BatchEditSheet> createState() => _BatchEditSheetState();
}

class _BatchEditSheetState extends State<_BatchEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _batchNoCtl;
  late final TextEditingController _expiryCtl;
  late final TextEditingController _buyCtl;
  late final TextEditingController _sellCtl;
  late final TextEditingController _adjustQtyCtl;
  late final TextEditingController _adjustReasonCtl;
  bool _isReduce = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _batchNoCtl = TextEditingController(text: widget.batch.batchNo);
    _expiryCtl = TextEditingController(
      text: formatDdMmYyyy(widget.batch.expiryIso),
    );
    _buyCtl = TextEditingController(
      text: widget.batch.unitCost != null
          ? formatEtbAmount(widget.batch.unitCost!)
          : '',
    );
    _sellCtl = TextEditingController(
      text: widget.batch.sellPrice != null
          ? formatEtbAmount(widget.batch.sellPrice!)
          : '',
    );
    _adjustQtyCtl = TextEditingController();
    _adjustReasonCtl = TextEditingController();
    if (!widget.canIncreaseStock) _isReduce = true;
  }

  @override
  void dispose() {
    _batchNoCtl.dispose();
    _expiryCtl.dispose();
    _buyCtl.dispose();
    _sellCtl.dispose();
    _adjustQtyCtl.dispose();
    _adjustReasonCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final expiryIso = slashDdMmYyyyToIso(_expiryCtl.text.trim());
      if (expiryIso == null) {
        setState(() {
          _error = 'Invalid expiry date';
          _loading = false;
        });
        return;
      }
      final buyParsed = num.tryParse(_buyCtl.text.trim());
      final sellParsed = num.tryParse(_sellCtl.text.trim());
      await client
          .from('medicine_batches')
          .update({
            'batch_no': _batchNoCtl.text.trim().isEmpty
                ? null
                : _batchNoCtl.text.trim(),
            'expiry_date': expiryIso,
            'unit_cost_base': buyParsed,
            'sell_price_base': sellParsed,
          })
          .eq('id', widget.batch.batchId);

      final adjustRaw = _adjustQtyCtl.text.trim();
      if (adjustRaw.isNotEmpty) {
        final adjustQty = num.parse(adjustRaw);
        if (adjustQty > 0) {
          final signedQty = _isReduce ? -adjustQty : adjustQty;
          await client.rpc(
            'apply_stock_movement',
            params: {
              'p_team_id': widget.teamId,
              'p_branch_id': widget.branchId,
              'p_batch_id': widget.batch.batchId,
              'p_type': 'adjustment',
              'p_qty': signedQty,
              'p_reason': _adjustReasonCtl.text.trim(),
              'p_ref_type': 'adjustment',
              'p_ref_id': null,
            },
          );
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userFacingError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit batch', style: t.textTheme.titleLarge),
              Text(
                'On hand ${widget.batch.qtyOnHand}',
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _batchNoCtl,
                decoration: const InputDecoration(
                  labelText: 'Batch number',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _expiryCtl,
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _buyCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}$'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Buy price',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _sellCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}$'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Sell price',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Adjust quantity', style: t.textTheme.titleSmall),
              const SizedBox(height: 6),
              if (widget.canIncreaseStock)
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment<bool>(value: false, label: Text('Add')),
                    ButtonSegment<bool>(value: true, label: Text('Reduce')),
                  ],
                  selected: {_isReduce},
                  onSelectionChanged: (next) {
                    setState(() => _isReduce = next.first);
                  },
                )
              else
                Text(
                  'Only reductions are allowed for your role.',
                  style: t.textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _adjustQtyCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}$'),
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Amount (optional)',
                  hintText: 'Leave empty to skip',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _adjustReasonCtl,
                decoration: InputDecoration(
                  labelText: _adjustQtyCtl.text.trim().isEmpty
                      ? 'Reason (if adjusting)'
                      : 'Reason *',
                ),
                validator: (value) {
                  if (_adjustQtyCtl.text.trim().isEmpty) return null;
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a reason for the adjustment';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: t.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save batch'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddBatchPayload {
  const AddBatchPayload({
    this.batchNo,
    required this.expiryIso,
    this.qty,
    this.unitCost,
    this.sellPrice,
  });

  final String? batchNo;
  final String expiryIso;
  final num? qty;
  final num? unitCost;
  final num? sellPrice;
}

Future<AddBatchPayload?> showAddBatchSheet({
  required BuildContext context,
  num? defaultBuy,
  num? defaultSell,
}) {
  return showModalBottomSheet<AddBatchPayload>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _AddBatchSheet(
      defaultBuy: defaultBuy,
      defaultSell: defaultSell,
    ),
  );
}

class _AddBatchSheet extends StatefulWidget {
  const _AddBatchSheet({this.defaultBuy, this.defaultSell});

  final num? defaultBuy;
  final num? defaultSell;

  @override
  State<_AddBatchSheet> createState() => _AddBatchSheetState();
}

class _AddBatchSheetState extends State<_AddBatchSheet> {
  final _formKey = GlobalKey<FormState>();
  final _batchNoCtl = TextEditingController();
  final _expiryCtl = TextEditingController();
  final _qtyCtl = TextEditingController();
  final _buyCtl = TextEditingController();
  final _sellCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.defaultBuy != null) {
      _buyCtl.text = formatEtbAmount(widget.defaultBuy!);
    }
    if (widget.defaultSell != null) {
      _sellCtl.text = formatEtbAmount(widget.defaultSell!);
    }
  }

  @override
  void dispose() {
    _batchNoCtl.dispose();
    _expiryCtl.dispose();
    _qtyCtl.dispose();
    _buyCtl.dispose();
    _sellCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add batch',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _batchNoCtl,
                decoration: const InputDecoration(
                  labelText: 'Batch number (optional)',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _expiryCtl,
                keyboardType: TextInputType.number,
                inputFormatters: [SlashDdMmYyyyInputFormatter()],
                decoration: slashDdMmYyyyInputDecoration(
                  context,
                  label: 'Expiry *',
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
              const SizedBox(height: 10),
              TextFormField(
                controller: _qtyCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}$'),
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Quantity (optional)',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _buyCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}$'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Buy price',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _sellCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}$'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Sell price',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() != true) return;
                        final iso = slashDdMmYyyyToIso(_expiryCtl.text.trim());
                        if (iso == null) return;
                        final qtyRaw = _qtyCtl.text.trim();
                        Navigator.pop(
                          context,
                          AddBatchPayload(
                            batchNo: _batchNoCtl.text.trim().isEmpty
                                ? null
                                : _batchNoCtl.text.trim(),
                            expiryIso: iso,
                            qty: qtyRaw.isEmpty ? null : num.parse(qtyRaw),
                            unitCost: num.tryParse(_buyCtl.text.trim()),
                            sellPrice: num.tryParse(_sellCtl.text.trim()),
                          ),
                        );
                      },
                      child: const Text('Add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
