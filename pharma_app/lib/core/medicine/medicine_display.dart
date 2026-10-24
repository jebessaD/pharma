/// Generic-first labels for medicine rows (`name` = brand, `generic_name` = ingredient).
String medicineText(Map<String, dynamic> row, String key) {
  return row[key]?.toString().trim() ?? '';
}

String medicineBrandName(Map<String, dynamic> row) => medicineText(row, 'name');

String medicineGenericName(Map<String, dynamic> row) =>
    medicineText(row, 'generic_name');

/// Primary staff-facing label: generic when present, otherwise brand.
String medicinePrimaryLabel(Map<String, dynamic> row) {
  final generic = medicineGenericName(row);
  if (generic.isNotEmpty) return generic;
  final brand = medicineBrandName(row);
  return brand.isEmpty ? 'Medicine' : brand;
}

/// Brand line when both generic and brand are set.
String? medicineSecondaryLabel(Map<String, dynamic> row) {
  final brand = medicineBrandName(row);
  final generic = medicineGenericName(row);
  if (brand.isEmpty || generic.isEmpty) return null;
  return brand;
}

/// Autocomplete / picker display with optional code or barcode suffix.
String medicineAutocompleteLabel(
  Map<String, dynamic> row, {
  bool includeCode = true,
}) {
  final primary = medicinePrimaryLabel(row);
  if (!includeCode) return primary;
  final code = medicineText(row, 'manual_code');
  final barcode = medicineText(row, 'barcode');
  final parts = <String>[];
  if (code.isNotEmpty) parts.add(code);
  if (barcode.isNotEmpty) parts.add(barcode);
  if (parts.isEmpty) return primary;
  return '$primary (${parts.join(' / ')})';
}

/// Combined report/export label: `generic · brand` when both differ.
String medicineReportDisplayLabel({
  String? brand,
  String? generic,
}) {
  final b = brand?.trim() ?? '';
  final g = generic?.trim() ?? '';
  if (g.isNotEmpty && b.isNotEmpty && g.toLowerCase() != b.toLowerCase()) {
    return '$g · $b';
  }
  if (g.isNotEmpty) return g;
  if (b.isNotEmpty) return b;
  return 'Unknown medicine';
}

/// Splits a combined `generic · brand` label for two-line UI.
(String primary, String? brand) splitMedicineDisplayLabel(String combined) {
  final text = combined.trim();
  final sep = text.indexOf(' · ');
  if (sep > 0) {
    final primary = text.substring(0, sep).trim();
    final brand = text.substring(sep + 3).trim();
    if (primary.isNotEmpty && brand.isNotEmpty) {
      return (primary, brand);
    }
  }
  return (text, null);
}

List<String> medicineDetailParts(Map<String, dynamic> row) {
  return [
    medicineText(row, 'country'),
    medicineText(row, 'manual_code'),
  ].where((value) => value.isNotEmpty).toList(growable: false);
}
