/// Global fixed medicine categories (same keys for every team).
/// Backed by [medicines.category_key] in Postgres.
const List<MedicineCategoryOption> medicineCategoryCatalog = [
  MedicineCategoryOption(key: 'medicine', label: 'Medicine'),
  MedicineCategoryOption(key: 'consumable', label: 'Consumable'),
  MedicineCategoryOption(key: 'medical_device', label: 'Medical Device'),
  MedicineCategoryOption(key: 'supplements', label: 'Supplements'),
  MedicineCategoryOption(key: 'personal_care', label: 'Personal Care'),
  MedicineCategoryOption(key: 'diagnostics', label: 'Diagnostics'),
  MedicineCategoryOption(key: 'other', label: 'Other'),
];

class MedicineCategoryOption {
  const MedicineCategoryOption({required this.key, required this.label});

  final String key;
  final String label;
}

String medicineCategoryLabel(String? key) {
  if (key == null || key.isEmpty) return '';
  for (final c in medicineCategoryCatalog) {
    if (c.key == key) return c.label;
  }
  return key;
}

List<Map<String, dynamic>> medicineCategoryRowsForUi() {
  return medicineCategoryCatalog
      .map(
        (c) => <String, dynamic>{
          'id': c.key,
          'name': c.label,
          'is_active': true,
        },
      )
      .toList(growable: false);
}
