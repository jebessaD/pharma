/// Normalized Ethiopian mobile number for auth and SMS.
final class EthiopianPhone {
  const EthiopianPhone({
    required this.msisdn,
    required this.e164,
    required this.national,
  });

  /// SMSEthiopia format: `251911234567` (no plus).
  final String msisdn;

  /// Supabase Auth format: `+251911234567`.
  final String e164;

  /// Local display format: `0911234567`.
  final String national;
}

/// Matches Ethio Telecom mobile numbers after country code `251`.
final RegExp _ethiopianMobileMsisdn = RegExp(r'^251(9[1-9]|7[0-9])\d{7}$');

/// Returns null when [raw] is not a valid Ethiopian mobile number.
EthiopianPhone? tryNormalizeEthiopianPhone(String raw) {
  var digits = raw.trim().replaceAll(RegExp(r'[\s\-().]'), '');
  if (digits.startsWith('+')) {
    digits = digits.substring(1);
  }

  late String msisdn;
  if (digits.startsWith('251') && digits.length == 12) {
    msisdn = digits;
  } else if (digits.startsWith('0') && digits.length == 10) {
    msisdn = '251${digits.substring(1)}';
  } else if (digits.length == 9 && RegExp(r'^[79]').hasMatch(digits)) {
    msisdn = '251$digits';
  } else {
    return null;
  }

  if (!_ethiopianMobileMsisdn.hasMatch(msisdn)) {
    return null;
  }

  return EthiopianPhone(
    msisdn: msisdn,
    e164: '+$msisdn',
    national: '0${msisdn.substring(3)}',
  );
}

/// True when [raw] looks like an Ethiopian phone (not email / staff username).
bool looksLikeEthiopianPhone(String raw) {
  return tryNormalizeEthiopianPhone(raw) != null;
}

String ethiopianPhoneValidationMessage() {
  return 'Enter a valid Ethiopian mobile number (e.g. 0911234567)';
}
