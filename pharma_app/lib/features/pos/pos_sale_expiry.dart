/// Calendar-day expiry check aligned with DB `expiry_date < CURRENT_DATE` (today still valid).
DateTime? parseBatchExpiryDay(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) {
    return DateTime(raw.year, raw.month, raw.day);
  }
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final head = s.split('T').first;
    final parts = head.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]);
      final mo = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && mo != null && d != null) {
        return DateTime(y, mo, d);
      }
    }
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
  return null;
}

/// True if the batch expiry calendar day is strictly before today (local).
bool batchExpiryIsBeforeToday(Object? expiryRaw) {
  final exp = parseBatchExpiryDay(expiryRaw);
  if (exp == null) return false;
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  return exp.isBefore(today);
}

const kPosExpiredStockOnlyKey = '_pos_expired_stock_only';
