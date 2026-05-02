/// Synthetic auth domain for staff (must match edge `STAFF_EMAIL_DOMAIN`).
const kStaffAuthEmailDomain = 'staff.internal';

/// Same normalization as edge `normalizeUsername`.
String normalizeStaffUsername(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
}

/// Auth email for staff: `{username}@staff.internal` (globally unique username).
String staffSyntheticLoginEmail(String usernameOrRaw) {
  final u = normalizeStaffUsername(usernameOrRaw);
  return '$u@$kStaffAuthEmailDomain';
}

/// Display / derived sign-in email when Auth email is not loaded (matches new staff shape).
String staffSignInEmail({required String username}) {
  return staffSyntheticLoginEmail(username);
}
