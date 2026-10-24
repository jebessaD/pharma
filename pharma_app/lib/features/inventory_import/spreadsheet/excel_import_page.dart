import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/pharmacy_profile_provider.dart';
import '../../../core/providers/selected_branch_provider.dart';
import '../../../core/roles/stock_permissions.dart';
import '../../../core/widgets/form_error_banner.dart';
import '../../../core/widgets/pharmacy_page_app_bar.dart';
import '../import_models.dart';
import '../import_review_session.dart';
import 'column_mapper.dart';
import 'rows_to_extracted.dart';
import 'spreadsheet_models.dart';
import 'xlsx_parser.dart';

/// Wizard: pick Excel/CSV → select sheet → confirm mapping → review.
class ExcelImportPage extends ConsumerStatefulWidget {
  const ExcelImportPage({super.key});

  @override
  ConsumerState<ExcelImportPage> createState() => _ExcelImportPageState();
}

class _ExcelImportPageState extends ConsumerState<ExcelImportPage> {
  SpreadsheetWorkbook? _book;
  SpreadsheetTable? _sheet;
  ColumnMapping? _mapping;
  bool _busy = false;
  String? _error;
  ImportCanonicalField? _pendingPriceRole;
  bool _didAutoPick = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didAutoPick) return;
      _didAutoPick = true;
      _pickFile(popIfCancelled: true);
    });
  }

  Future<void> _pickFile({bool popIfCancelled = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        if (!mounted) return;
        setState(() => _busy = false);
        if (popIfCancelled && _book == null) {
          context.pop();
        }
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('Could not read the selected file.');
      }
      final name = file.name;
      final lower = name.toLowerCase();
      final SpreadsheetWorkbook book;
      if (lower.endsWith('.csv')) {
        book = parseCsvBytes(bytes: Uint8List.fromList(bytes), filename: name);
      } else if (lower.endsWith('.xlsx')) {
        book = parseXlsxBytes(bytes: Uint8List.fromList(bytes), filename: name);
      } else {
        throw const FormatException('Use an .xlsx or .csv file.');
      }
      if (!mounted) return;
      setState(() {
        _book = book;
        _sheet = book.sheets.length == 1 ? book.sheets.first : null;
        _mapping = _sheet == null ? null : autoMapColumns(_sheet!);
        _busy = false;
        _pendingPriceRole = _mapping?.needsPriceRoleConfirmation == true
            ? ImportCanonicalField.unitCost
            : null;
      });
      if (_mapping?.needsPriceRoleConfirmation == true && mounted) {
        await _askPriceRole();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _askPriceRole() async {
    final mapping = _mapping;
    if (mapping == null || mapping.ambiguousPriceColumns.isEmpty) return;
    final choice = await showDialog<ImportCanonicalField>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('What is this price column?'),
        content: const Text(
          'A column looks like money/price but is unclear. '
          'Is it buy (unit cost) or sell price?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImportCanonicalField.unitCost),
            child: const Text('Buy / unit cost'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ImportCanonicalField.sellPrice),
            child: const Text('Sell price'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      for (final col in mapping.ambiguousPriceColumns) {
        mapping.fieldByColumn[col] = choice;
      }
      _pendingPriceRole = null;
    });
  }

  void _selectSheet(SpreadsheetTable sheet) {
    final mapping = autoMapColumns(sheet);
    setState(() {
      _sheet = sheet;
      _mapping = mapping;
      _error = null;
    });
    if (mapping.needsPriceRoleConfirmation) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askPriceRole());
    }
  }

  Future<void> _continueToReview() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final role = profile?['role'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    final book = _book;
    final sheet = _sheet;
    final mapping = _mapping;
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch first.');
      return;
    }
    if (!canAddStockInForRole(role)) {
      setState(() => _error = 'Excel import is limited to owners and admins.');
      return;
    }
    if (book == null || sheet == null || mapping == null) {
      setState(() => _error = 'Pick a file and sheet first.');
      return;
    }
    if (!mapping.hasName &&
        !mapping.fieldByColumn.values.contains(ImportCanonicalField.manualCode) &&
        !mapping.fieldByColumn.values.contains(ImportCanonicalField.barcode)) {
      setState(
        () => _error =
            'Map at least a medicine name, code, or barcode column.',
      );
      return;
    }
    if (!mapping.hasQuantity) {
      setState(
        () => _error =
            'This looks like stock-in: map a quantity (Amount/Qty) column.',
      );
      return;
    }

    final extraction = spreadsheetToExtraction(table: sheet, mapping: mapping);
    if (extraction.lines.isEmpty) {
      setState(() => _error = 'No usable data rows found.');
      return;
    }

    setImportReviewSession(
      ImportReviewSession(
        mode: ImportMode.directStockIn,
        extraction: extraction,
        teamId: teamId,
        branchId: branchId,
        spreadsheetMeta: SpreadsheetImportMeta(
          sourceKind: book.kind,
          filename: book.filename,
          sheetName: sheet.name,
        ),
      ),
    );
    final committed = await context.push<bool>('/pharmacy/import-review');
    if (committed == true && mounted) {
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final sheet = _sheet;
    final mapping = _mapping;

    return Scaffold(
      appBar: pharmacyPageAppBar(
        context,
        title: 'Import Excel / CSV',
        subtitle: 'Smart column matching for stock-in',
        actions: [
          IconButton(
            tooltip: 'Import history',
            onPressed: () => context.push('/pharmacy/import-history'),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: _busy && book == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          if (book != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _pickFile(),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text('Change file (${book.filename})'),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FormErrorBanner(message: _error!),
          ],
          if (book != null && book.sheets.length > 1) ...[
            const SizedBox(height: 20),
            Text(
              'Select sheet',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: book.sheets.map((s) {
                final selected = sheet?.name == s.name;
                return ChoiceChip(
                  label: Text(s.name),
                  selected: selected,
                  onSelected: (_) => _selectSheet(s),
                );
              }).toList(),
            ),
          ],
          if (sheet != null && mapping != null) ...[
            const SizedBox(height: 20),
            Text(
              'Column mapping (${sheet.rows.length} data rows)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...List.generate(sheet.headers.length, (i) {
              final header = sheet.headers[i];
              if (header.trim().isEmpty) return const SizedBox.shrink();
              final current = mapping.fieldByColumn[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        header,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_forward, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<ImportCanonicalField?>(
                        // ignore: deprecated_member_use
                        value: current,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<ImportCanonicalField?>(
                            value: null,
                            child: Text('Ignore'),
                          ),
                          ...ImportCanonicalField.values.map(
                            (f) => DropdownMenuItem(
                              value: f,
                              child: Text(f.label),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => mapping.fieldByColumn[i] = v);
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_pendingPriceRole != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _askPriceRole,
                child: const Text('Confirm price column role'),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Next: review screen matches your catalog like photo import — '
              'existing medicines are linked, new ones are created only when needed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _continueToReview,
              child: const Text('Continue to review'),
            ),
            const SizedBox(height: 8),
            Text(
              'Expiry is required in the review list. Batch is optional. '
              'Amount = quantity unless it looks like ETB/money.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
