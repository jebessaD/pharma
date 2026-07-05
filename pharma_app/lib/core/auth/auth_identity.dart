import 'ethiopian_phone.dart';

enum AuthIdentityKind { email, phone, staffUsername }

AuthIdentityKind classifyAuthIdentity(String raw) {
  final trimmed = raw.trim();
  if (trimmed.contains('@')) {
    return AuthIdentityKind.email;
  }
  if (looksLikeEthiopianPhone(trimmed)) {
    return AuthIdentityKind.phone;
  }
  return AuthIdentityKind.staffUsername;
}
