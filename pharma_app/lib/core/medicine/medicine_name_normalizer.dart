/// Normalizes medicine names for fuzzy catalog matching during import.
String normalizeMedicineMatchKey(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s*]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Strips common pack-size tokens so "Amoxil 400mg 10x10" can match "Amoxil 400mg".
String normalizeMedicineMatchKeyLoose(String raw) {
  var key = normalizeMedicineMatchKey(raw);
  key = key
      .replaceAll(RegExp(r'\b\d+\s*[x*]\s*\d+\b'), ' ')
      .replaceAll(RegExp(r'\b(box|pkt|pack|strip|blister)\s+of\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return key;
}

/// Match keys derived from a product line (name, generic, combined).
List<String> medicineMatchKeys({
  String? name,
  String? genericName,
  String? description,
}) {
  final keys = <String>{};
  void add(String? raw) {
    if (raw == null || raw.trim().isEmpty) return;
    final strict = normalizeMedicineMatchKey(raw);
    if (strict.isNotEmpty) keys.add(strict);
    final loose = normalizeMedicineMatchKeyLoose(raw);
    if (loose.isNotEmpty) keys.add(loose);
  }

  add(name);
  add(genericName);
  add(description);
  if (name != null &&
      genericName != null &&
      name.trim().isNotEmpty &&
      genericName.trim().isNotEmpty) {
    add('${name.trim()} ${genericName.trim()}');
    add('${name.trim()} (${genericName.trim()})');
  }
  return keys.toList(growable: false);
}
