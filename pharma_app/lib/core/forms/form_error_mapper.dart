import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps [AuthException], [PostgrestException], [FunctionException], and generic errors to user-readable copy.
String userFacingError(Object error) {
  if (error is AuthException) {
    return _userFacingAuth(error);
  }
  if (error is PostgrestException) {
    return _userFacingPostgrest(error);
  }
  if (error is FunctionException) {
    return _userFacingFunction(error);
  }
  final recovered = _functionExceptionFromToString(error.toString());
  if (recovered != null) {
    return _userFacingFunction(recovered);
  }
  return _userFacingString(error.toString());
}

/// Parses [FunctionException.toString] when `error is FunctionException` fails (e.g. wrapped types).
FunctionException? _functionExceptionFromToString(String raw) {
  if (!raw.contains('FunctionException')) return null;
  final re = RegExp(
    r'FunctionException\(status:\s*(\d+),\s*details:\s*(.*?),\s*reasonPhrase:',
    dotAll: true,
  );
  final m = re.firstMatch(raw);
  if (m == null) return null;
  final status = int.tryParse(m.group(1) ?? '') ?? 500;
  final detailsRaw = m.group(2);
  if (detailsRaw == null) return FunctionException(status: status, details: '');
  return FunctionException(status: status, details: detailsRaw);
}

String _functionDetailsToMessage(dynamic d) {
  if (d == null) return '';
  if (d is String) {
    final s = d.trim();
    if (s.startsWith('{')) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) {
          final err = decoded['error'] ??
              decoded['message'] ??
              decoded['msg'] ??
              decoded['error_description'];
          if (err != null) return err.toString().trim();
        }
      } catch (_) {
        /* use raw string */
      }
    }
    return s;
  }
  if (d is Map) {
    final err = d['error'] ?? d['message'] ?? d['msg'] ?? d['error_description'];
    if (err != null) return err.toString().trim();
    return jsonEncode(d);
  }
  if (d is Uint8List) {
    try {
      return utf8.decode(d).trim();
    } catch (_) {
      return '';
    }
  }
  if (d is List<int>) {
    try {
      return utf8.decode(d).trim();
    } catch (_) {
      return '';
    }
  }
  return d.toString().trim();
}

String _userFacingFunction(FunctionException e) {
  var text = _functionDetailsToMessage(e.details);
  if (text.isEmpty) {
    return switch (e.status) {
      401 => 'Your session has expired. Please sign in again.',
      403 => 'Only team administrators can add staff accounts.',
      404 =>
        'The create-staff service was not found (HTTP 404). Deploy the edge function admin-create-user in Supabase, then try again.',
      503 => 'The server is temporarily unavailable. Try again in a moment.',
      _ =>
        'Request failed (HTTP ${e.status}). If you are the project owner, confirm the admin-create-user function is deployed and secrets (SUPABASE_SERVICE_ROLE_KEY) are set.',
    };
  }
  final lower = text.toLowerCase();

  if (lower == 'invalid_credentials' || lower.contains('invalid login')) {
    return 'Invalid username or password. Check your details and try again.';
  }
  if (e.status == 401 || lower == 'unauthorized') {
    return 'Your session has expired. Please sign in again.';
  }
  if (e.status == 403 || lower == 'forbidden') {
    return 'Only team administrators can add staff accounts.';
  }
  if (lower == 'missing_fields' || lower == 'invalid_fields') {
    return 'Please fill in all required fields correctly.';
  }
  if (lower == 'bad_role') {
    return 'The selected role is not allowed.';
  }
  if (lower == 'username_taken') {
    return 'This username is already taken on your team. Pick another.';
  }
  if (lower == 'invalid_username' || lower == 'missing_username') {
    return 'Enter a valid username (3–32 characters: letters, numbers, underscores).';
  }
  if (lower == 'user_not_found') {
    return 'That user was not found.';
  }
  if (lower == 'password_too_short') {
    return 'Password must be at least 8 characters.';
  }
  if (lower == 'ambiguous_username') {
    return 'That username exists on more than one pharmacy. Sign in with the full email instead.';
  }
  if (lower == 'profile_exists') {
    return 'This account already has a pharmacy profile. Sign in instead of registering again.';
  }
  if (lower == 'invalid_team_name' || lower == 'invalid_full_name') {
    return 'Enter a valid pharmacy name and your full name.';
  }
  if (lower == 'server_env_missing' || lower == 'method_not_allowed') {
    return 'The server could not run this action. Check edge function secrets (e.g. SUPABASE_SERVICE_ROLE_KEY) or contact support.';
  }
  if (lower.contains('admin-create-user') ||
      lower.contains('function not found') ||
      lower.contains('route not found') ||
      lower.contains('not found')) {
    return 'Staff creation service is missing in the connected backend. Deploy edge function admin-create-user on the pharma Supabase project.';
  }
  if (lower.contains('already been registered') ||
      lower.contains('user already registered') ||
      lower.contains('email address has already been') ||
      (lower.contains('duplicate') && lower.contains('key'))) {
    return 'This sign-in address is already in use. Try a different username or remove the existing user in Supabase Auth first.';
  }
  if (lower.contains('password') && (lower.contains('weak') || lower.contains('at least'))) {
    return 'Password is too weak. Use at least 8 characters, or follow your organization rules.';
  }
  if (lower.contains('foreign key') || (lower.contains('violates') && lower.contains('fkey'))) {
    return 'The selected branch is invalid. Pick another branch or “No branch”.';
  }
  if (text.length < 280 && text.split('\n').length <= 3) {
    return text;
  }
  return 'Could not create the user. If this keeps happening, contact support with the time you tried.';
}

String _userFacingAuth(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid') &&
      (m.contains('password') || m.contains('login') || m.contains('email'))) {
    return 'Invalid email or password. Check your details and try again.';
  }
  if (m.contains('email not confirmed')) {
    return 'Please confirm your email before signing in.';
  }
  return e.message.isNotEmpty
      ? e.message
      : 'Could not sign in. Please try again.';
}

String _userFacingPostgrest(PostgrestException e) {
  final m = e.message.toLowerCase();
  if (m.contains('jwt') || m.contains('pgrst301') || m.contains('session')) {
    return 'Your session has expired. Please sign in again.';
  }
  if (m.contains('permission') || m.contains('row-level') || m.contains('policy')) {
    return 'You do not have permission for this action.';
  }
  if (m.contains('relation') && m.contains('does not exist')) {
    if (m.contains('branches')) {
      return 'Branches table is missing in the connected database. Connect the pharma Supabase project and run pharma migrations.';
    }
    if (m.contains('profiles') || m.contains('user_profiles')) {
      return 'Profile tables do not match this app schema. Connect the correct pharma Supabase project and run migrations.';
    }
    return 'Database schema is incomplete for this screen. Connect the correct pharma project and run migrations.';
  }
  if (e.code == '23505' || m.contains('duplicate') || m.contains('unique')) {
    return 'This record already exists. Use a different value.';
  }
  if (m.contains('billing_blocked')) {
    return 'This account cannot record changes until billing is resolved. Contact support or your owner.';
  }
  if (m.contains('team_suspended')) {
    return 'This pharmacy team is suspended. Contact support.';
  }
  if (m.contains('insufficient_stock')) {
    return 'Not enough stock for this sale. Reduce quantities or choose another batch.';
  }
  if (m.contains('expired_batch')) {
    return 'This batch is expired and cannot be sold.';
  }
  if (m.contains('bulk_stock_bad_row')) {
    return 'Each bulk row needs medicine, batch, expiry, and quantity greater than zero.';
  }
  if (m.contains('bulk_stock_empty')) {
    return 'Add at least one line to bulk stock in.';
  }
  if (m.contains('expiry_in_past')) {
    return 'Expiry date cannot be in the past.';
  }
  if (m.contains('medicine_not_found')) {
    return 'One of the medicines was not found for your team.';
  }
  if (m.contains('branch_not_found')) {
    return 'A selected branch was not found.';
  }
  if (m.contains('same_branch')) {
    return 'Source and target branch must be different.';
  }
  if (m.contains('conflict_mode_not_supported')) {
    return 'Only skip-existing duplication mode is supported.';
  }
  if (m.contains('bad_branch')) {
    return 'That branch is not valid for your team.';
  }
  if (e.message.length < 200 &&
      !m.contains('relation') &&
      !m.contains('null value') &&
      m.split('\n').length == 1) {
    return e.message.trim();
  }
  return 'Could not load data. Please check your connection and try again.';
}

String _userFacingString(String raw) {
  final recovered = _functionExceptionFromToString(raw);
  if (recovered != null) {
    return _userFacingFunction(recovered);
  }
  final lower = raw.toLowerCase();
  if (lower.contains('functionexception')) {
    return 'Edge function error. Deploy admin-create-user or check the Dashboard → Edge Functions logs.';
  }
  if (lower.contains('invalid login credentials') || lower.contains('invalid credentials')) {
    return 'Invalid email or password. Check your details and try again.';
  }
  if (lower.contains('duplicate') || lower.contains('already exists')) {
    return 'This record already exists. Use a different value.';
  }

  // Browser / fetch (Flutter web): NOT the same as "Wi‑Fi off". Often CORS, extensions, or bad URL.
  if (lower.contains('failed to fetch') ||
      lower.contains('xmlhttprequest') ||
      lower.contains('load failed') ||
      lower.contains('cors')) {
    return 'The browser could not complete the request to Supabase. '
        'Open DevTools (F12) → Network, retry, and look for a red entry to admin-create-user. '
        'Common causes: ad blocker, wrong Supabase URL in the app build, or HTTPS/certificate issues.';
  }
  if (lower.contains('clientexception')) {
    return 'The HTTP request to Supabase failed. This is often a browser block (extensions), CORS, or an invalid project URL—not necessarily your Wi‑Fi. Check DevTools → Network, or try from the iOS/Android app.';
  }

  // Real transport failures only (avoid matching unrelated text that contains "connection").
  final looksLikeTransport = lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('host lookup failed') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('connection aborted') ||
      lower.contains('connection closed') ||
      lower.contains('connection timed out') ||
      lower.contains('errno = 7') ||
      lower.contains('errno = 8') ||
      (lower.contains('network') &&
          (lower.contains('unreachable') || lower.contains('error')));

  if (looksLikeTransport) {
    return 'No connection to the server. Check your network, VPN, and that you can open the Supabase dashboard in the same browser.';
  }
  if (lower.contains('permission denied') || lower.contains('not authorized')) {
    return 'You do not have permission for this action.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'The request took too long. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}

String mapFormError(Object error) => userFacingError(error);
