import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final pharmacyProfileProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return null;
  return Supabase.instance.client
      .from('profiles')
      .select()
      .eq('id', session.user.id)
      .maybeSingle();
});
