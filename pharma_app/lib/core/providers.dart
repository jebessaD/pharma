import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/supabase_auth_refresh.dart';

final supabaseAuthRefreshProvider = Provider<SupabaseAuthRefresh>((ref) {
  final n = SupabaseAuthRefresh();
  ref.onDispose(n.dispose);
  return n;
});
