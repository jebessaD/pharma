import '../import_models.dart';
import 'column_mapper.dart';
import 'date_coerce.dart';
import 'money_coerce.dart';
import 'spreadsheet_models.dart';

/// Converts a mapped spreadsheet table into [ExtractionResult] for the
/// existing review/commit pipeline (stock-in mode).
ExtractionResult spreadsheetToExtraction({
  required SpreadsheetTable table,
  required ColumnMapping mapping,
}) {
  final dateSamples = <String>[];
  for (final entry in mapping.fieldByColumn.entries) {
    if (entry.value == ImportCanonicalField.expiryDate) {
      final col = entry.key;
      for (final row in table.rows.take(80)) {
        if (col < row.length && row[col].trim().isNotEmpty) {
          dateSamples.add(row[col]);
        }
      }
    }
  }
  final dates = SpreadsheetDateCoercer(dateSamples);
  final lines = <ExtractedLine>[];

  for (var i = 0; i < table.rows.length; i++) {
    final row = table.rows[i];
    String? cell(ImportCanonicalField f) {
      for (final e in mapping.fieldByColumn.entries) {
        if (e.value == f && e.key < row.length) {
          final v = row[e.key].trim();
          if (v.isNotEmpty) return v;
        }
      }
      return null;
    }

    final name = cell(ImportCanonicalField.name);
    final code = cell(ImportCanonicalField.manualCode);
    final barcode = cell(ImportCanonicalField.barcode);
    if ((name == null || name.isEmpty) &&
        (code == null || code.isEmpty) &&
        (barcode == null || barcode.isEmpty)) {
      continue;
    }

    final expiryRaw = cell(ImportCanonicalField.expiryDate);
    final coerced = expiryRaw == null ? null : dates.coerce(expiryRaw);
    final qty = parseSpreadsheetQty(cell(ImportCanonicalField.quantity));
    final unitCost = parseSpreadsheetMoney(cell(ImportCanonicalField.unitCost));
    final sellPrice = parseSpreadsheetMoney(cell(ImportCanonicalField.sellPrice));
    final reorder = parseSpreadsheetQty(cell(ImportCanonicalField.reorderLevel));

    final warnings = <String>[];
    if (qty == null || qty <= 0) {
      warnings.add('Quantity missing or invalid');
    }
    if (coerced == null) {
      warnings.add('Expiry missing or invalid — fill before commit');
    }

    lines.add(
      ExtractedLine(
        rowIndex: i + 1,
        name: name,
        description: name,
        genericName: cell(ImportCanonicalField.genericName),
        manualCode: code,
        barcode: barcode,
        batchNo: cell(ImportCanonicalField.batchNo),
        expiryDate: coerced?.iso,
        expiryDateRaw: coerced?.displayDdMmYyyy ?? expiryRaw,
        quantity: qty,
        unitCost: unitCost,
        sellPrice: sellPrice,
        reorderLevel: reorder,
        categoryKey: cell(ImportCanonicalField.categoryKey),
        subcategory: cell(ImportCanonicalField.subcategory),
        strength: cell(ImportCanonicalField.strength),
        dosageForm: cell(ImportCanonicalField.dosageForm),
        presentation: cell(ImportCanonicalField.presentation),
        warnings: warnings,
        confidence: const FieldConfidence(
          name: 1,
          batchNo: 1,
          expiryDate: 1,
          quantity: 1,
          unitCost: 1,
        ),
      ),
    );
  }

  return ExtractionResult(
    documentType: 'spreadsheet',
    isSupported: true,
    header: const ExtractedHeader(),
    lines: lines,
    documentWarnings: lines.isEmpty
        ? const ['No usable rows found after column mapping.']
        : const [],
  );
}
