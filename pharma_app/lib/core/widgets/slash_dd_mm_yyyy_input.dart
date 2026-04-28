import 'package:flutter/services.dart';

/// Digits-only entry with auto `/` as **dd/MM/yyyy** (e.g. `05/12/2027`).
class SlashDdMmYyyyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) {
      return oldValue;
    }
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(digits[i]);
    }
    final built = buf.toString();
    return TextEditingValue(
      text: built,
      selection: TextSelection.collapsed(offset: built.length),
    );
  }
}

/// Converts `dd/MM/yyyy` to `yyyy-MM-dd` for Postgres, or `null` if incomplete/invalid.
String? slashDdMmYyyyToIso(String raw) {
  final parts = raw.trim().split('/');
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (year < 2000 || year > 2100) return null;
  final dt = DateTime(year, month, day);
  if (dt.year != year || dt.month != month || dt.day != day) return null;
  return '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

/// `null` if valid and not before [today] (date-only); otherwise an error message.
String? slashDdMmYyyyExpiryError(String raw, DateTime today) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return 'Enter expiry (dd/MM/yyyy)';
  if (digits.length < 8) return 'Enter full date dd/MM/yyyy';
  final iso = slashDdMmYyyyToIso(raw);
  if (iso == null) return 'Invalid date';
  final d = DateTime.parse(iso);
  if (d.isBefore(today)) return 'Expiry cannot be in the past';
  return null;
}
