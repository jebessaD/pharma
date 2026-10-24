import 'header_aliases.dart';
import 'money_coerce.dart';
import 'spreadsheet_models.dart';

class ColumnMapping {
  ColumnMapping({
    required this.headers,
    required this.fieldByColumn,
    this.ambiguousPriceColumns = const [],
    this.needsPriceRoleConfirmation = false,
  });

  final List<String> headers;

  /// column index → canonical field (or null if unmapped)
  final Map<int, ImportCanonicalField?> fieldByColumn;

  /// Columns that look like a generic "price" and need buy vs sell confirmation.
  final List<int> ambiguousPriceColumns;

  final bool needsPriceRoleConfirmation;

  ImportCanonicalField? fieldFor(int col) => fieldByColumn[col];

  bool get hasQuantity =>
      fieldByColumn.values.contains(ImportCanonicalField.quantity);

  bool get hasName => fieldByColumn.values.contains(ImportCanonicalField.name);

  bool get hasExpiry =>
      fieldByColumn.values.contains(ImportCanonicalField.expiryDate);
}

ColumnMapping autoMapColumns(SpreadsheetTable table) {
  final used = <ImportCanonicalField>{};
  final map = <int, ImportCanonicalField?>{};
  final ambiguousPrice = <int>[];

  for (var i = 0; i < table.headers.length; i++) {
    final header = table.headers[i];
    final samples = table.rows
        .take(40)
        .map((r) => i < r.length ? r[i] : '')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    var field = _matchAlias(header, used);

    // Amount + money signal → unit cost (money), not qty.
    final norm = normalizeHeader(header);
    if (field == ImportCanonicalField.quantity &&
        (headerLooksLikeMoney(header) || cellsLookLikeMoney(samples))) {
      field = used.contains(ImportCanonicalField.unitCost)
          ? ImportCanonicalField.sellPrice
          : ImportCanonicalField.unitCost;
    }

    // Bare "price" / "amount" money without buy/sell cue → ask user.
    if (field == null &&
        (norm == 'price' ||
            (norm == 'amount' &&
                (headerLooksLikeMoney(header) ||
                    cellsLookLikeMoney(samples))))) {
      ambiguousPrice.add(i);
      map[i] = null;
      continue;
    }

    // Content sniffing fallbacks
    field ??= _sniffField(samples, used);

    if (field != null) used.add(field);
    map[i] = field;
  }

  return ColumnMapping(
    headers: table.headers,
    fieldByColumn: map,
    ambiguousPriceColumns: ambiguousPrice,
    needsPriceRoleConfirmation: ambiguousPrice.isNotEmpty,
  );
}

ImportCanonicalField? _matchAlias(
  String header,
  Set<ImportCanonicalField> used,
) {
  final n = normalizeHeader(header);
  if (n.isEmpty) return null;

  ImportCanonicalField? best;
  var bestScore = 0;
  for (final entry in kHeaderAliases.entries) {
    if (used.contains(entry.key)) continue;
    for (final alias in entry.value) {
      final a = normalizeHeader(alias);
      var score = 0;
      if (n == a) {
        score = 100;
      } else if (n.contains(a) || a.contains(n)) {
        score = 70;
      }
      if (score > bestScore) {
        bestScore = score;
        best = entry.key;
      }
    }
  }
  return bestScore >= 70 ? best : null;
}

ImportCanonicalField? _sniffField(
  List<String> samples,
  Set<ImportCanonicalField> used,
) {
  if (samples.isEmpty) return null;

  var dateHits = 0;
  var qtyHits = 0;
  var moneyHits = 0;
  for (final s in samples.take(20)) {
    if (RegExp(r'\d{1,4}[/.\-]\d{1,4}([/.\-]\d{2,4})?').hasMatch(s)) {
      dateHits++;
    }
    if (parseSpreadsheetQty(s) != null &&
        !RegExp(r'etb|birr|\$', caseSensitive: false).hasMatch(s)) {
      qtyHits++;
    }
    if (parseSpreadsheetMoney(s) != null &&
        (RegExp(r'etb|birr|\$', caseSensitive: false).hasMatch(s) ||
            s.contains('.'))) {
      moneyHits++;
    }
  }

  if (!used.contains(ImportCanonicalField.expiryDate) && dateHits >= 3) {
    return ImportCanonicalField.expiryDate;
  }
  if (!used.contains(ImportCanonicalField.quantity) &&
      qtyHits >= 3 &&
      moneyHits < qtyHits) {
    return ImportCanonicalField.quantity;
  }
  if (!used.contains(ImportCanonicalField.unitCost) && moneyHits >= 3) {
    return ImportCanonicalField.unitCost;
  }
  return null;
}
