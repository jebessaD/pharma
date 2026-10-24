import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/medicine_category_catalog.dart';
import '../../core/widgets/apply_profit_roundup_checkbox.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';
import '../../core/widgets/slash_dd_mm_yyyy_input.dart';
import '../../core/pricing/recommended_sell_price.dart';
import 'import_commit_service.dart';
import 'import_error_text.dart';
import 'import_medicine_matcher.dart';
import 'import_medicine_sheets.dart';
import 'import_models.dart';
import 'import_medicine_similarity.dart';
import 'import_progress_steps.dart';
import 'import_review_row.dart';
import 'import_review_session.dart';
import 'import_supplier_resolver.dart';

/// Review + confirm screen for extracted invoice/stock rows.
class ImportReviewPage extends ConsumerStatefulWidget {
  const ImportReviewPage({
    super.key,
    required this.mode,
    required this.extraction,
    required this.teamId,
    required this.branchId,
    this.spreadsheetMeta,
  });

  final ImportMode mode;
  final ExtractionResult extraction;
  final String teamId;
  final String branchId;
  final SpreadsheetImportMeta? spreadsheetMeta;

  @override
  ConsumerState<ImportReviewPage> createState() => _ImportReviewPageState();
}

class _ImportReviewPageState extends ConsumerState<ImportReviewPage> {
  final _matcher = ImportMedicineMatcher();
  final _commit = ImportCommitService();
  final _supplierResolver = ImportSupplierResolver();
  late final List<ImportReviewRow> _rows;
  late final TextEditingController _invoice;
  late final TextEditingController _supplier;

  bool _matching = true;
  int _matchCompleted = 0;
  bool _submitting = false;
  bool _applyProfitRoundup = false;
  String? _error;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _rows = widget.extraction.lines.map(ImportReviewRow.fromExtracted).toList();
    _invoice = TextEditingController(
      text: widget.extraction.header.invoiceNo ?? '',
    );
    _supplier = TextEditingController(
      text: widget.extraction.header.supplierName ?? '',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _runMatching());
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _invoice.dispose();
    _supplier.dispose();
    super.dispose();
  }

  Future<void> _runMatching() async {
    final total = _rows.length;
    final catalog = await _matcher.loadCatalog(
      teamId: widget.teamId,
      branchId: widget.branchId,
    );
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (mounted) {
        setState(() => _matchCompleted = i);
      }
      try {
        final match = await _matcher.match(
          teamId: widget.teamId,
          branchId: widget.branchId,
          line: row.source,
          catalog: catalog,
        );
        if (!mounted) return;
        setState(() => row.applyMatch(match));
      } catch (_) {
        if (mounted) {
          setState(() {
            row.createNew = true;
          });
        }
      }
    }
    if (mounted) {
      setState(() {
        for (final row in _rows) {
          if (row.medicineId == null && !row.createNew) {
            row.createNew = true;
          }
        }
        _matchCompleted = total;
        _matching = false;
      });
    }
  }

  Future<void> _selectFromList(ImportReviewRow row) async {
    final search = row.genericName.text.trim().isNotEmpty
        ? row.genericName.text.trim()
        : row.name.text.trim();
    final picked = await showSelectMedicineSheet(
      context,
      teamId: widget.teamId,
      branchId: widget.branchId,
      suggestions: row.match?.candidates ?? const [],
      initialSearch: search.isEmpty ? null : search,
      matchQuery: row.match?.query ?? search,
    );
    if (picked != null && mounted) {
      setState(() => row.selectMedicine(picked));
    }
  }

  void _useAsNew(ImportReviewRow row) {
    setState(() => row.clearMedicineLink());
  }

  int get _invalidCount => _rows
      .where((r) => !r.removed && r.status(_today) == ImportRowStatus.invalid)
      .length;

  void _onApplyProfitRoundupChanged(bool value) {
    setState(() {
      _applyProfitRoundup = value;
      if (!value) return;
      applyRecommendedSellPricesWhereEmpty(
        _rows
            .where((r) => !r.removed)
            .map((r) => (purchase: r.unitCost, sell: r.sellPrice)),
      );
    });
  }

  int get _activeCount => _rows.where((r) => !r.removed).length;

  int get _committableCount =>
      _rows.where((r) => !r.removed && r.isCommittable(_today)).length;

  bool get _allRowsCommittable =>
      _activeCount > 0 && _committableCount == _activeCount;

  Future<void> _createMissingMedicinesForConfirm() async {
    for (final row in _rows) {
      if (row.removed || row.medicineId != null) continue;
      if (row.status(_today) != ImportRowStatus.newMedicine) continue;
      final name = row.name.text.trim();
      if (name.isEmpty) continue;
      final purchasePrice = num.tryParse(row.unitCost.text.trim()) ?? 0;
      final existingSell = num.tryParse(row.sellPrice.text.trim());
      final sellPrice =
          existingSell ??
          (purchasePrice > 0 ? recommendedSellPrice(purchasePrice) : 0);
      final id = await _matcher.createMedicine(
        teamId: widget.teamId,
        branchId: widget.branchId,
        name: name,
        genericName: row.genericName.text.trim().isEmpty
            ? null
            : row.genericName.text.trim(),
        manualCode: row.manualCode.text.trim().isEmpty
            ? null
            : row.manualCode.text.trim(),
        barcode: row.barcode.text.trim().isEmpty ? null : row.barcode.text.trim(),
        categoryKey: row.newCategoryKey,
        strength: row.source.strength,
        dosageForm: row.source.dosageForm,
        presentation: row.source.presentation,
        reorderLevel: num.tryParse(row.reorderLevel.text.trim()) ?? 1,
        purchasePrice: purchasePrice,
        sellingPrice: sellPrice,
      );
      row.sellPrice.text = sellPrice > 0
          ? priceText(sellPrice)
          : row.sellPrice.text;
      row.markCreated(id, name);
    }
  }

  Future<bool> _showConfirmDialog() async {
    final active = _rows.where((r) => !r.removed).toList();
    final total = active.length;
    if (total == 0) return false;

    final newCount = active
        .where((r) => r.medicineId == null && r.status(_today) == ImportRowStatus.newMedicine)
        .length;
    final linkedCount = total - newCount;

    final medicineWord = total == 1 ? 'medicine' : 'medicines';
    final lines = <String>[
      if (widget.mode.isPurchase)
        'You are creating a purchase draft with $total $medicineWord line(s).'
      else
        'You are stocking in $total different $medicineWord.',
      if (newCount > 0 && linkedCount > 0)
        '$linkedCount linked to existing catalog item(s), $newCount will be added as new medicine(s).'
      else if (newCount > 0)
        'All $newCount will be added as new medicine(s) in your catalog.'
      else if (linkedCount > 0)
        'All $linkedCount linked to existing catalog medicine(s).',
      'Double-check names, quantities, expiry dates, batch numbers, and prices before you confirm.',
      if (_totalMismatch) ...[
        '',
        'Warning: line totals (${importFormatTotal(_computedLinesTotal())}) do not '
        'match the document total '
        '(${importFormatTotal(widget.extraction.header.grandTotal!)}). '
        'Review unit costs and quantities carefully.',
      ],
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.mode.isPurchase ? 'Create purchase draft?' : 'Confirm stock in?'),
        content: SingleChildScrollView(
          child: Text(lines.join('\n\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(widget.mode.isPurchase ? 'Create draft' : 'Stock in'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _addManualRow() {
    final nextIndex = _rows.fold<int>(
      0,
      (max, r) => r.source.rowIndex > max ? r.source.rowIndex : max,
    );
    final row = ImportReviewRow.fromExtracted(
      ExtractedLine(rowIndex: nextIndex + 1),
    );
    row.createNew = true;
    setState(() => _rows.add(row));
  }

  num _computedLinesTotal() {
    return importSumLineTotals(
      _rows.where((r) => !r.removed).map(
        (r) => (
          qty: parseImportQty(r.qty.text),
          unitCost: num.tryParse(r.unitCost.text.trim()),
          lineTotal: r.source.lineTotal,
        ),
      ),
    );
  }

  bool get _totalMismatch => importTotalsMismatch(
    documentTotal: widget.extraction.header.grandTotal,
    linesTotal: _computedLinesTotal(),
  );

  Future<void> _confirm() async {
    if (_submitting) return;
    if (!_allRowsCommittable) {
      setState(
        () => _error =
            'Fill quantity and expiry on every row before stocking in.',
      );
      return;
    }
    if (!await _showConfirmDialog()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _createMissingMedicinesForConfirm();
      if (!mounted) return;
      final supplierId = widget.mode.isPurchase
          ? await _supplierResolver.resolveOrCreate(
              teamId: widget.teamId,
              supplierName: _supplier.text,
            )
          : null;
      if (!mounted) return;
      final sheet = widget.spreadsheetMeta;
      final result = await _commit.commit(
        mode: widget.mode,
        teamId: widget.teamId,
        branchId: widget.branchId,
        rows: _rows,
        today: _today,
        supplierId: supplierId,
        invoiceReference: _invoice.text,
        sourceKind: sheet?.sourceKind ??
            (widget.mode == ImportMode.directStockIn ? 'photo' : null),
        sourceFilename: sheet?.filename,
        sheetName: sheet?.sheetName,
        meta: sheet == null
            ? null
            : {
                'sheet_name': sheet.sheetName,
                'filename': sheet.filename,
              },
      );
      if (!mounted) return;
      final skippedMsg = result.skipped > 0
          ? ' ${result.skipped} row(s) skipped.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.mode.isPurchase
                ? 'Purchase draft created with ${result.committed} item(s).$skippedMsg'
                : 'Stocked in ${result.committed} row(s).$skippedMsg',
          ),
        ),
      );
      if (widget.mode.isPurchase && result.purchaseId != null) {
        context.go('/pharmacy/purchases/${result.purchaseId}');
      } else {
        context.pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = importErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _rows.where((r) => !r.removed).toList();
    return Scaffold(
      appBar: pharmacyPageAppBar(
        context,
        title: 'Review import',
        subtitle: widget.mode.isPurchase
            ? 'Confirm items for a purchase draft'
            : 'Confirm items for stock-in',
      ),
      bottomNavigationBar: _BottomBar(
        submitting: _submitting,
        ready: _committableCount,
        total: active.length,
        invalidCount: _invalidCount,
        allReady: _allRowsCommittable,
        purchaseMode: widget.mode.isPurchase,
        onConfirm: _confirm,
        onAddAnother: _addManualRow,
      ),
      body: Column(
        children: [
          if (_matching)
            ImportDeterminateProgressBanner(
              title: 'Matching medicines to your catalog',
              completed: _matchCompleted,
              total: _rows.length,
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _HeaderCard(
                  extraction: widget.extraction,
                  invoiceController: _invoice,
                  supplierController: _supplier,
                  purchaseMode: widget.mode.isPurchase,
                  linesTotal: _computedLinesTotal(),
                  totalMismatch: _totalMismatch,
                ),
                const SizedBox(height: 8),
                ApplyProfitRoundupCheckbox(
                  value: _applyProfitRoundup,
                  onChanged: _onApplyProfitRoundupChanged,
                ),
                const SizedBox(height: 4),
                if (_error != null) ...[
                  FormErrorBanner(message: _error!),
                  const SizedBox(height: 8),
                ],
                for (var i = 0; i < active.length; i++)
                  _RowCard(
                    rowNumber: i + 1,
                    row: active[i],
                    today: _today,
                    onChanged: () => setState(() {}),
                    onSelectFromList: () => _selectFromList(active[i]),
                    onUseAsNew: () => _useAsNew(active[i]),
                    onRemove: () => setState(() => active[i].removed = true),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.extraction,
    required this.invoiceController,
    required this.supplierController,
    required this.purchaseMode,
    required this.linesTotal,
    required this.totalMismatch,
  });

  final ExtractionResult extraction;
  final TextEditingController invoiceController;
  final TextEditingController supplierController;
  final bool purchaseMode;
  final num linesTotal;
  final bool totalMismatch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = extraction.header;
    final docTotal = h.grandTotal;
    final chips = <String>[
      if ((h.supplierName ?? '').isNotEmpty) 'Supplier: ${h.supplierName}',
      if ((h.invoiceDate ?? '').isNotEmpty) 'Date: ${h.invoiceDate}',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'Extracted document',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: chips
                    .map(
                      (c) => Chip(
                        label: Text(c),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
            ],
            if (docTotal != null && docTotal > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _TotalTile(
                      label: 'Document total',
                      value: importFormatTotal(docTotal),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TotalTile(
                      label: 'Lines total',
                      value: importFormatTotal(linesTotal),
                      highlight: totalMismatch,
                    ),
                  ),
                ],
              ),
            ],
            if (totalMismatch) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Totals do not match — check unit costs, quantities, '
                        'and line prices in detail.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (purchaseMode) ...[
              const SizedBox(height: 10),
              AppTextFormField(
                controller: supplierController,
                label: 'Supplier',
              ),
              const SizedBox(height: 10),
              AppTextFormField(
                controller: invoiceController,
                label: 'Invoice reference',
              ),
              const SizedBox(height: 4),
              Text(
                'Supplier will be matched by name or created on the purchase draft.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? cs.errorContainer.withValues(alpha: 0.35)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: highlight ? Border.all(color: cs.error.withValues(alpha: 0.5)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: highlight ? cs.error : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.rowNumber,
    required this.row,
    required this.today,
    required this.onChanged,
    required this.onSelectFromList,
    required this.onUseAsNew,
    required this.onRemove,
  });

  final int rowNumber;
  final ImportReviewRow row;
  final DateTime today;
  final VoidCallback onChanged;
  final VoidCallback onSelectFromList;
  final VoidCallback onUseAsNew;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = row.status(today);
    final priceFilter = FilteringTextInputFormatter.allow(
      RegExp(r'^\d*\.?\d{0,2}$'),
    );
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                  child: Text(
                    '$rowNumber',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusDot(status: status),
                const SizedBox(width: 8),
                Expanded(child: _MedicineLine(row: row)),
                IconButton(
                  tooltip: 'Remove row',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 6),
            AppTextFormField(
              controller: row.genericName,
              label: 'Generic name',
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextFormField(
                    controller: row.name,
                    label: 'Brand / trade name',
                    onChanged: (_) => onChanged(),
                  ),
                ),
                if (row.medicineId != null)
                  TextButton(
                    onPressed: onUseAsNew,
                    child: const Text('Use as new'),
                  ),
                TextButton(
                  onPressed: onSelectFromList,
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppTextFormField(
                    controller: row.manualCode,
                    label: 'Manual code',
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppTextFormField(
                    controller: row.barcode,
                    label: 'Barcode',
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: row.newCategoryKey,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      isDense: true,
                    ),
                    items: medicineCategoryCatalog
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.key,
                            child: Text(c.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      row.newCategoryKey = v;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppTextFormField(
                    controller: row.reorderLevel,
                    label: 'Reorder level',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [priceFilter],
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppTextFormField(
                    controller: row.batchNo,
                    label: 'Batch',
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: row.expiry,
                    keyboardType: TextInputType.number,
                    inputFormatters: [SlashDdMmYyyyInputFormatter()],
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Expiry *',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppTextFormField(
                    controller: row.qty,
                    label: 'Qty *',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [priceFilter],
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppTextFormField(
                    controller: row.unitCost,
                    label: 'Unit cost',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [priceFilter],
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppTextFormField(
                    controller: row.sellPrice,
                    label: 'Sell',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [priceFilter],
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            if (row.displayWarnings.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                row.displayWarnings.join(' - '),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.tertiary),
              ),
            ],
            const SizedBox(height: 4),
            _RowStatusLabel(row: row, status: status, today: today),
          ],
        ),
      ),
    );
  }
}

class _RowStatusLabel extends StatelessWidget {
  const _RowStatusLabel({
    required this.row,
    required this.status,
    required this.today,
  });

  final ImportReviewRow row;
  final ImportRowStatus status;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Text(
      _statusText(status),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: _statusColor(context, status),
      ),
    );
  }

  String _statusText(ImportRowStatus s) => switch (s) {
    ImportRowStatus.ready => 'Ready',
    ImportRowStatus.needsChoice => 'Tap Change to link a medicine',
    ImportRowStatus.newMedicine => 'Will add as new on confirm',
    ImportRowStatus.invalid => row.invalidHint(today),
  };

  Color _statusColor(BuildContext context, ImportRowStatus s) {
    final cs = Theme.of(context).colorScheme;
    return switch (s) {
      ImportRowStatus.ready => cs.primary,
      ImportRowStatus.needsChoice => cs.tertiary,
      ImportRowStatus.newMedicine => cs.secondary,
      ImportRowStatus.invalid => cs.error,
    };
  }
}

class _MedicineLine extends StatelessWidget {
  const _MedicineLine({required this.row});

  final ImportReviewRow row;

  @override
  Widget build(BuildContext context) {
    final label = row.medicineLabel;
    if (label != null && label.isNotEmpty) {
      return Text(
        label,
        style: Theme.of(context).textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text(
      row.createNew ? 'New medicine' : 'Tap Change to link',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final ImportRowStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (status) {
      ImportRowStatus.ready => cs.primary,
      ImportRowStatus.needsChoice => cs.tertiary,
      ImportRowStatus.newMedicine => cs.secondary,
      ImportRowStatus.invalid => cs.error,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.submitting,
    required this.ready,
    required this.total,
    required this.invalidCount,
    required this.allReady,
    required this.purchaseMode,
    required this.onConfirm,
    required this.onAddAnother,
  });

  final bool submitting;
  final int ready;
  final int total;
  final int invalidCount;
  final bool allReady;
  final bool purchaseMode;
  final VoidCallback onConfirm;
  final VoidCallback onAddAnother;

  @override
  Widget build(BuildContext context) {
    final canConfirm = !submitting && allReady;
    final statusText = allReady
        ? '$ready of $total row(s) ready'
        : invalidCount > 0
        ? '$ready of $total ready — $invalidCount row(s) need qty/expiry'
        : '$ready of $total ready — finish remaining rows';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(statusText, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: submitting ? null : onAddAnother,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add another stock'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canConfirm ? onConfirm : null,
                    icon: submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(purchaseMode ? 'Create draft' : 'Stock in'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
