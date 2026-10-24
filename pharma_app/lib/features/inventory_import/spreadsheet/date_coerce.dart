/// Result of normalizing a spreadsheet date cell to ISO `YYYY-MM-DD`.
class CoercedDate {
  const CoercedDate({
    required this.iso,
    required this.displayDdMmYyyy,
    this.monthYearOnly = false,
  });

  final String iso;
  final String displayDdMmYyyy;
  final bool monthYearOnly;
}

enum _DateOrder { dayMonth, monthDay }

/// Infers DD/MM vs MM/DD from column samples, then coerces one cell.
/// Month/year only (`01/2029`) → last day of that month.
class SpreadsheetDateCoercer {
  SpreadsheetDateCoercer(List<String> samples) : _order = _inferOrder(samples);

  final _DateOrder _order;

  static _DateOrder _inferOrder(List<String> samples) {
    var firstIsDay = false;
    var secondIsDay = false;
    for (final raw in samples) {
      final parts = _splitParts(raw);
      if (parts == null || parts.length < 2) continue;
      if (parts.length == 2 && parts[1] > 31) {
        // month/year — ignore for order
        continue;
      }
      if (parts.length >= 2) {
        if (parts[0] > 12) firstIsDay = true;
        if (parts[1] > 12) secondIsDay = true;
      }
    }
    if (firstIsDay && !secondIsDay) return _DateOrder.dayMonth;
    if (secondIsDay && !firstIsDay) return _DateOrder.monthDay;
    // Ambiguous (all ≤ 12) → app standard DD/MM.
    return _DateOrder.dayMonth;
  }

  CoercedDate? coerce(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    final isoDirect = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
    if (isoDirect != null) {
      final y = int.parse(isoDirect.group(1)!);
      final m = int.parse(isoDirect.group(2)!);
      final d = int.parse(isoDirect.group(3)!);
      return _fromYmd(y, m, d);
    }

    final parts = _splitParts(t);
    if (parts == null) return null;

    if (parts.length == 2) {
      // MM/YYYY → last day of month
      final a = parts[0];
      final b = parts[1];
      if (b >= 1000 && a >= 1 && a <= 12) {
        final last = DateTime(b, a + 1, 0).day;
        return _fromYmd(b, a, last, monthYearOnly: true);
      }
      if (a >= 1000 && b >= 1 && b <= 12) {
        final last = DateTime(a, b + 1, 0).day;
        return _fromYmd(a, b, last, monthYearOnly: true);
      }
      return null;
    }

    if (parts.length != 3) return null;
    final x = parts[0];
    final y = parts[1];
    final year = _normalizeYear(parts[2]);
    late final int day;
    late final int month;
    if (_order == _DateOrder.dayMonth) {
      day = x;
      month = y;
    } else {
      month = x;
      day = y;
    }
    return _fromYmd(year, month, day);
  }
}

List<int>? _splitParts(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'[.\-]'), '/');
  final bits = cleaned.split('/').map((s) => s.trim()).where((s) => s.isNotEmpty);
  final nums = <int>[];
  for (final b in bits) {
    final n = int.tryParse(b);
    if (n == null) return null;
    nums.add(n);
  }
  if (nums.isEmpty) return null;
  return nums;
}

int _normalizeYear(int y) {
  if (y >= 100) return y;
  return y >= 70 ? 1900 + y : 2000 + y;
}

CoercedDate? _fromYmd(
  int year,
  int month,
  int day, {
  bool monthYearOnly = false,
}) {
  if (month < 1 || month > 12) return null;
  final last = DateTime(year, month + 1, 0).day;
  if (day < 1 || day > last) return null;
  final iso =
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
  final display =
      '${day.toString().padLeft(2, '0')}/'
      '${month.toString().padLeft(2, '0')}/'
      '${year.toString().padLeft(4, '0')}';
  return CoercedDate(
    iso: iso,
    displayDdMmYyyy: display,
    monthYearOnly: monthYearOnly,
  );
}
