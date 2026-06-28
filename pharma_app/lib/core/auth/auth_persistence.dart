import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../registration/registration_location.dart';

const lastAuthenticatedUserIdKey = 'last_authenticated_user_id';
const lastLoginAtKey = 'last_login_at';
const pendingOwnerSignupEmailKey = 'pending_owner_signup_email';
const pendingOwnerSignupTeamNameKey = 'pending_owner_signup_team_name';
const pendingOwnerSignupFullNameKey = 'pending_owner_signup_full_name';
const pendingOwnerSignupCountryCodeKey =
    'pending_owner_signup_registration_country_code';
const pendingOwnerSignupCountryNameKey =
    'pending_owner_signup_registration_country_name';
const pendingOwnerSignupRegionKey = 'pending_owner_signup_registration_region';
const pendingOwnerSignupCityKey = 'pending_owner_signup_registration_city';
const pendingOwnerSignupLocationSourceKey =
    'pending_owner_signup_registration_location_source';

Future<void> persistLocalAuthMarker(SharedPreferences prefs, User user) async {
  await prefs.setString(lastAuthenticatedUserIdKey, user.id);
  await prefs.setString(
    lastLoginAtKey,
    DateTime.now().toUtc().toIso8601String(),
  );
}

Future<void> clearLocalAuthMarker(SharedPreferences prefs) async {
  await prefs.remove(lastAuthenticatedUserIdKey);
  await prefs.remove(lastLoginAtKey);
}

Future<void> persistPendingOwnerSignup(
  SharedPreferences prefs, {
  required String email,
  required String teamName,
  required String fullName,
  RegistrationLocation registrationLocation = RegistrationLocation.empty,
}) async {
  await prefs.setString(pendingOwnerSignupEmailKey, email.trim().toLowerCase());
  await prefs.setString(pendingOwnerSignupTeamNameKey, teamName.trim());
  await prefs.setString(pendingOwnerSignupFullNameKey, fullName.trim());
  await _setNullableString(
    prefs,
    pendingOwnerSignupCountryCodeKey,
    registrationLocation.countryCode,
  );
  await _setNullableString(
    prefs,
    pendingOwnerSignupCountryNameKey,
    registrationLocation.countryName,
  );
  await _setNullableString(
    prefs,
    pendingOwnerSignupRegionKey,
    registrationLocation.region,
  );
  await _setNullableString(
    prefs,
    pendingOwnerSignupCityKey,
    registrationLocation.city,
  );
  await _setNullableString(
    prefs,
    pendingOwnerSignupLocationSourceKey,
    registrationLocation.source,
  );
}

({
  String? email,
  String? teamName,
  String? fullName,
  RegistrationLocation registrationLocation,
})
readPendingOwnerSignup(SharedPreferences prefs) {
  return (
    email: prefs.getString(pendingOwnerSignupEmailKey),
    teamName: prefs.getString(pendingOwnerSignupTeamNameKey),
    fullName: prefs.getString(pendingOwnerSignupFullNameKey),
    registrationLocation: RegistrationLocation(
      countryCode: prefs.getString(pendingOwnerSignupCountryCodeKey),
      countryName: prefs.getString(pendingOwnerSignupCountryNameKey),
      region: prefs.getString(pendingOwnerSignupRegionKey),
      city: prefs.getString(pendingOwnerSignupCityKey),
      source: prefs.getString(pendingOwnerSignupLocationSourceKey),
    ).normalized(),
  );
}

Future<void> clearPendingOwnerSignup(SharedPreferences prefs) async {
  await prefs.remove(pendingOwnerSignupEmailKey);
  await prefs.remove(pendingOwnerSignupTeamNameKey);
  await prefs.remove(pendingOwnerSignupFullNameKey);
  await prefs.remove(pendingOwnerSignupCountryCodeKey);
  await prefs.remove(pendingOwnerSignupCountryNameKey);
  await prefs.remove(pendingOwnerSignupRegionKey);
  await prefs.remove(pendingOwnerSignupCityKey);
  await prefs.remove(pendingOwnerSignupLocationSourceKey);
}

Future<void> _setNullableString(
  SharedPreferences prefs,
  String key,
  String? value,
) async {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    await prefs.remove(key);
  } else {
    await prefs.setString(key, normalized);
  }
}
