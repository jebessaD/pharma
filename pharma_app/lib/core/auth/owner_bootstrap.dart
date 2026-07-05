import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../registration/registration_location.dart';
import 'auth_persistence.dart';
import 'ethiopian_phone.dart';

/// Creates an owner profile when the auth user exists but [profiles] row is missing.
/// Returns true when a profile is present after this call (existing or newly created).
Future<bool> tryBootstrapOwnerProfile({
  required SharedPreferences prefs,
  required User user,
  required SupabaseClient client,
}) async {
  final existingProfile = await client
      .from('profiles')
      .select('id')
      .eq('id', user.id)
      .maybeSingle();
  if (existingProfile != null) return true;

  final pending = readPendingOwnerSignup(prefs);
  final meta = user.userMetadata ?? const <String, dynamic>{};
  final authEmail = user.email?.trim().toLowerCase() ?? '';
  final authPhone = user.phone?.trim() ?? '';
  final pendingEmail = (pending.email ?? '').trim().toLowerCase();
  final pendingPhone = (pending.phone ?? '').trim();

  final isPendingEmail = authEmail.isNotEmpty && authEmail == pendingEmail;
  final normalizedAuthPhone = tryNormalizeEthiopianPhone(authPhone)?.e164;
  final normalizedPendingPhone =
      tryNormalizeEthiopianPhone(pendingPhone)?.e164;
  final isPendingPhone = normalizedAuthPhone != null &&
      normalizedPendingPhone != null &&
      normalizedAuthPhone == normalizedPendingPhone;

  final isPending = isPendingEmail || isPendingPhone;

  final teamName =
      (isPending ? pending.teamName : null) ??
      (meta['team_name'] as String?) ??
      '';
  final fullName =
      (isPending ? pending.fullName : null) ??
      (meta['full_name'] as String?) ??
      '';

  if (teamName.trim().length < 2 || fullName.trim().isEmpty) {
    return false;
  }

  final pendingLocation =
      isPending ? pending.registrationLocation : RegistrationLocation.empty;
  final metadataLocation = RegistrationLocation.fromAuthMetadata(meta);
  final registrationLocation = pendingLocation.isEmpty
      ? metadataLocation
      : pendingLocation;

  try {
    await client.rpc(
      'bootstrap_owner_team',
      params: {
        'p_team_name': teamName.trim(),
        'p_full_name': fullName.trim(),
        ...registrationLocation.toRpcParams(),
      },
    );
    await clearPendingOwnerSignup(prefs);
    return true;
  } on PostgrestException catch (e) {
    if (e.message.contains('profile_exists')) {
      await clearPendingOwnerSignup(prefs);
      return true;
    }
    rethrow;
  }
}
