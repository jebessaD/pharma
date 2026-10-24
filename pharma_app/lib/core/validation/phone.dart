/// Digits only; used for length checks (E.164 allows 7–15).
int phoneDigitCount(String value) {
  return value.replaceAll(RegExp(r'\D'), '').length;
}

/// Accepts common phone formats: optional +, digits, spaces, dashes, dots,
/// parentheses. Rejects letters. Length is based on digit count only.
bool isValidPhoneNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  if (!RegExp(r'^\+?[0-9][0-9\s\-().]{5,30}[0-9]$').hasMatch(trimmed)) {
    return false;
  }
  final digits = phoneDigitCount(trimmed);
  return digits >= 7 && digits <= 15;
}

String? phoneValidationError(String? value) {
  final s = value?.trim() ?? '';
  if (s.isEmpty) return 'Enter a phone number';
  if (!isValidPhoneNumber(s)) {
    return 'Enter a valid phone number (7–15 digits)';
  }
  return null;
}
