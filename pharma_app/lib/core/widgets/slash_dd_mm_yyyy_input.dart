import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

String _normalizeDigitsFromSlashTypedInput(String raw) {
  if (!raw.contains('/')) return _digitsOnly(raw);
  final parts = raw.split('/');
  var month = parts.isNotEmpty ? _digitsOnly(parts[0]) : '';
  var day = parts.length > 1 ? _digitsOnly(parts[1]) : '';
  final year = parts.length > 2
      ? _digitsOnly(parts.sublist(2).join(''))
      : '';

  final monthWasExplicit = raw.contains('/');
  final dayWasExplicit = RegExp(r'^\s*[^/]+/\s*[^/]*\/').hasMatch(raw);
  if (monthWasExplicit && month.length == 1) {
    month = '0$month';
  }
  if (dayWasExplicit && day.length == 1) {
    day = '0$day';
  }
  final merged = '$month$day$year';
  return merged.length > 8 ? merged.substring(0, 8) : merged;
}

String _formatDigitsToSlash(String digits) {
  if (digits.isEmpty) return '';
  final buf = StringBuffer();
  for (var i = 0; i < digits.length && i < 8; i++) {
    if (i == 2 || i == 4) buf.write('/');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Digits-only entry with auto `/` as **DD/MM/YYYY** (e.g. `05/12/2027`).
/// Slashes stay fixed once the segment is started; caret follows digit count.
class SlashDdMmYyyyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newDigits = _normalizeDigitsFromSlashTypedInput(newValue.text);
    if (newDigits.length > 8) {
      return oldValue;
    }
    var built = _formatDigitsToSlash(newDigits);
    final parts = newValue.text.split('/');
    final monthDigits = parts.isNotEmpty ? _digitsOnly(parts[0]) : '';
    final dayDigits = parts.length > 1 ? _digitsOnly(parts[1]) : '';
    final hasExplicitMonthSlash = newValue.text.contains('/');
    final hasExplicitDaySlash =
        RegExp(r'^\s*[^/]+/\s*[^/]*\/').hasMatch(newValue.text);
    final yearDigits = parts.length > 2
        ? _digitsOnly(parts.sublist(2).join(''))
        : '';
    if (hasExplicitMonthSlash &&
        (monthDigits.length >= 2 || monthDigits.length == 1) &&
        dayDigits.isEmpty &&
        !built.endsWith('/')) {
      built = '$built/';
    }
    if (hasExplicitDaySlash &&
        (dayDigits.length >= 2 || dayDigits.length == 1) &&
        yearDigits.isEmpty &&
        !built.endsWith('/')) {
      built = '$built/';
    }

    var sel = newValue.selection.baseOffset;
    if (sel < 0) sel = built.length;
    final uptoSel = _digitsOnly(newValue.text.substring(0, sel.clamp(0, newValue.text.length)));
    var offset = 0;
    var d = 0;
    while (offset < built.length && d < uptoSel.length) {
      if (built[offset] == '/') {
        offset++;
        continue;
      }
      offset++;
      d++;
    }
    if (uptoSel.length >= 2 && offset == 2) offset = 3;
    if (uptoSel.length >= 4 && offset == 5) offset = 6;
    if (newValue.text.endsWith('/')) offset = built.length;
    offset = offset.clamp(0, built.length);
    return TextEditingValue(
      text: built,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Converts `DD/MM/YYYY` to `YYYY-MM-DD` for Postgres, or `null` if incomplete/invalid.
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
  if (digits.isEmpty) return 'Enter expiry (DD/MM/YYYY)';
  if (digits.length < 8) return 'Enter full date DD/MM/YYYY';
  final iso = slashDdMmYyyyToIso(raw);
  if (iso == null) return 'Invalid date';
  final d = DateTime.parse(iso);
  if (d.isBefore(today)) return 'Expiry cannot be in the past';
  return null;
}

/// Inline hint while typing (month/day range only; full validity uses [slashDdMmYyyyToIso]).
String? slashDdMmYyyySoftError(String raw) {
  final d = _digitsOnly(raw);
  if (d.isEmpty) return null;
  if (d.length >= 1) {
    final m1 = int.tryParse(d[0]);
    if (m1 == null) return 'Use digits only';
    if (d.length == 1 && m1 > 3) return 'Invalid month';
  }
  if (d.length >= 2) {
    final mo = int.tryParse(d.substring(0, 2));
    if (mo == null || mo < 1 || mo > 12) return 'Month must be 01–12';
  }
  if (d.length >= 3) {
    final d0 = int.tryParse(d[2]);
    if (d0 == null) return null;
    if (d.length == 3 && d0 > 3) return 'Invalid day';
  }
  if (d.length >= 4) {
    final day = int.tryParse(d.substring(2, 4));
    if (day == null || day < 1 || day > 31) return 'Day must be 01–31';
    final mo = int.tryParse(d.substring(0, 2));
    if (mo != null && day > _daysInMonthClamped(mo)) {
      return 'Invalid day for this month';
    }
  }
  return null;
}

int _daysInMonthClamped(int month) {
  return switch (month) {
    2 => 29,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };
}

/// Shared decoration for DD/MM/YYYY expiry fields.
InputDecoration slashDdMmYyyyInputDecoration(BuildContext context, {String? label}) {
  return InputDecoration(
    labelText: label ?? 'Expiry (DD/MM/YYYY)',
    hintText: '__/__/____',
    helperText: 'Day / month / year — slashes are added automatically.',
  );
}
