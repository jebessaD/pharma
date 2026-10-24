/// One sheet of tabular data (header + body rows).
class SpreadsheetTable {
  const SpreadsheetTable({
    required this.name,
    required this.headers,
    required this.rows,
  });

  final String name;
  final List<String> headers;

  /// Body rows aligned to [headers] length (missing cells become '').
  final List<List<String>> rows;
}

/// Parsed workbook: one or more sheets.
class SpreadsheetWorkbook {
  const SpreadsheetWorkbook({
    required this.filename,
    required this.kind,
    required this.sheets,
  });

  final String filename;

  /// `xlsx` or `csv`.
  final String kind;
  final List<SpreadsheetTable> sheets;
}

/// Canonical fields we can map spreadsheet columns into.
enum ImportCanonicalField {
  name,
  genericName,
  manualCode,
  barcode,
  batchNo,
  expiryDate,
  quantity,
  unitCost,
  sellPrice,
  categoryKey,
  subcategory,
  strength,
  dosageForm,
  presentation,
  company,
  country,
  reorderLevel,
}

extension ImportCanonicalFieldX on ImportCanonicalField {
  String get label => switch (this) {
    ImportCanonicalField.name => 'Medicine name',
    ImportCanonicalField.genericName => 'Generic name',
    ImportCanonicalField.manualCode => 'Code',
    ImportCanonicalField.barcode => 'Barcode',
    ImportCanonicalField.batchNo => 'Batch',
    ImportCanonicalField.expiryDate => 'Expiry',
    ImportCanonicalField.quantity => 'Quantity',
    ImportCanonicalField.unitCost => 'Buy / unit cost',
    ImportCanonicalField.sellPrice => 'Sell price',
    ImportCanonicalField.categoryKey => 'Category',
    ImportCanonicalField.subcategory => 'Subcategory',
    ImportCanonicalField.strength => 'Strength',
    ImportCanonicalField.dosageForm => 'Dosage form',
    ImportCanonicalField.presentation => 'Presentation',
    ImportCanonicalField.company => 'Company',
    ImportCanonicalField.country => 'Country',
    ImportCanonicalField.reorderLevel => 'Reorder level',
  };

  bool get isRequiredForStockIn =>
      this == ImportCanonicalField.name ||
      this == ImportCanonicalField.quantity ||
      this == ImportCanonicalField.expiryDate;
}
