import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const lastAuthenticatedUserIdKey = 'last_authenticated_user_id';
const lastLoginAtKey = 'last_login_at';
const pendingOwnerSignupEmailKey = 'pending_owner_signup_email';
const pendingOwnerSignupTeamNameKey = 'pending_owner_signup_team_name';
const pendingOwnerSignupFullNameKey = 'pending_owner_signup_full_name';

/// Last successful pharmacy `team_id`; optional hint for staff username sign-in when usernames collide across teams.
const lastTeamIdForStaffSignInKey = 'last_team_id_for_staff_sign_in';

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

Future<void> persistLastTeamIdForStaffSignIn(
  SharedPreferences prefs,
  String teamId,
) async {
  await prefs.setString(lastTeamIdForStaffSignInKey, teamId);
}

Future<void> clearLastTeamIdForStaffSignIn(SharedPreferences prefs) async {
  await prefs.remove(lastTeamIdForStaffSignInKey);
}

Future<void> persistPendingOwnerSignup(
  SharedPreferences prefs, {
  required String email,
  required String teamName,
  required String fullName,
}) async {
  await prefs.setString(pendingOwnerSignupEmailKey, email.trim().toLowerCase());
  await prefs.setString(pendingOwnerSignupTeamNameKey, teamName.trim());
  await prefs.setString(pendingOwnerSignupFullNameKey, fullName.trim());
}

({String? email, String? teamName, String? fullName}) readPendingOwnerSignup(
  SharedPreferences prefs,
) {
  return (
    email: prefs.getString(pendingOwnerSignupEmailKey),
    teamName: prefs.getString(pendingOwnerSignupTeamNameKey),
    fullName: prefs.getString(pendingOwnerSignupFullNameKey),
  );
}

Future<void> clearPendingOwnerSignup(SharedPreferences prefs) async {
  await prefs.remove(pendingOwnerSignupEmailKey);
  await prefs.remove(pendingOwnerSignupTeamNameKey);
  await prefs.remove(pendingOwnerSignupFullNameKey);
}
