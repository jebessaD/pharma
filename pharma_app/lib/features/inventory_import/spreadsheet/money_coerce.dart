/// Parses money-like cells: strips ETB/Br/$, commas, spaces.
num? parseSpreadsheetMoney(String? raw) {
  if (raw == null) return null;
  var t = raw.trim();
  if (t.isEmpty) return null;
  t = t.replaceAll(
    RegExp(r'\b(etb|usd|birr|br)\b', caseSensitive: false),
    '',
  );
  t = t.replaceAll(RegExp(r'[^\d,.\-]'), '');
  t = t.trim();
  if (t.isEmpty) return null;

  // European 1.234,56 vs US 1,234.56
  if (t.contains(',') && t.contains('.')) {
    if (t.lastIndexOf(',') > t.lastIndexOf('.')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '');
    }
  } else if (t.contains(',')) {
    final parts = t.split(',');
    if (parts.length == 2 && parts[1].length <= 2) {
      t = '${parts[0]}.${parts[1]}';
    } else {
      t = t.replaceAll(',', '');
    }
  }

  return num.tryParse(t);
}

num? parseSpreadsheetQty(String? raw) {
  if (raw == null) return null;
  var t = raw.trim();
  if (t.isEmpty) return null;
  // Qty should not include currency words — if present, treat as money not qty.
  if (RegExp(r'\b(etb|usd|birr)\b', caseSensitive: false).hasMatch(t) ||
      t.contains(r'$')) {
    return null;
  }
  t = t.replaceAll(RegExp(r'[^\d,.\-]'), '');
  t = t.replaceAll(',', '');
  return num.tryParse(t);
}
