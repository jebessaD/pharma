import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Team status + display name for [PharmacyShell] header.
/// Cached per [teamId] — do not recreate a Future on every build (that breaks the element tree).
final teamShellMetaProvider =
    FutureProvider.family.autoDispose<Map<String, dynamic>, String>(
  (ref, teamId) async {
    if (teamId.isEmpty) {
      return {'status': null, 'pharmacy_name': ''};
    }
    final team = await Supabase.instance.client
        .from('teams')
        .select('status')
        .eq('id', teamId)
        .maybeSingle();
    final teamProfile = await Supabase.instance.client
        .from('team_profiles')
        .select('pharmacy_name')
        .eq('team_id', teamId)
        .maybeSingle();
    return <String, dynamic>{
      'status': team?['status'],
      'pharmacy_name':
          (teamProfile?['pharmacy_name'] as String? ?? '').trim(),
    };
  },
);
