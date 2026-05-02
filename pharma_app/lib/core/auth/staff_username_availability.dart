import 'package:supabase_flutter/supabase_flutter.dart';

import 'staff_login_email.dart';

/// `null` if skipped (invalid / error); `true` / `false` from edge when check ran.
Future<bool?> queryStaffUsernameAvailable(
  SupabaseClient client,
  String raw,
) async {
  final n = normalizeStaffUsername(raw);
  if (n.length < 3 || n.length > 32) return null;
  if (!RegExp(r'^[a-z0-9_]+$').hasMatch(n)) return null;
  try {
    final res = await client.functions.invoke(
      'staff-username-available',
      body: {'username': n},
    );
    if (res.status >= 400) return null;
    final d = res.data;
    if (d is Map && d['available'] is bool) {
      return d['available'] as bool;
    }
  } catch (_) {
    /* network / missing function */
  }
  return null;
}
