/// Synthetic auth domain for staff (must match edge `STAFF_EMAIL_DOMAIN`).
const kStaffAuthEmailDomain = 'staff.internal';

/// Same normalization as edge `normalizeUsername`.
String normalizeStaffUsername(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
}

/// Hostname label: `{slug(teamName)}-{first8 hex of teamId}` (DNS-safe, unique per team).
/// Must match `teamMailHostLabel` in edge functions `admin-create-user` and `staff-sign-in-username`.
String teamMailHostLabel(String teamName, String teamUuid) {
  var s = teamName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  s = s.replaceAll(RegExp(r'-+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.isEmpty) s = 'pharma';
  final hex = teamUuid.replaceAll('-', '');
  final short = hex.length >= 8 ? hex.substring(0, 8) : hex.padRight(8, '0');
  var host = '$s-$short';
  if (host.length > 63) {
    host = host.substring(0, 63).replaceAll(RegExp(r'-+$'), '');
  }
  if (host.isEmpty) host = 'pharma-$short';
  return host;
}

/// Sign-in email for a staff username on a team (matches Auth after create).
String staffSignInEmail({
  required String username,
  required String teamName,
  required String teamId,
}) {
  final u = normalizeStaffUsername(username);
  final host = teamMailHostLabel(teamName, teamId);
  return '$u@$host.$kStaffAuthEmailDomain';
}
