import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pharmacy_profile_provider.dart';

/// Global YouTube onboarding settings from [app_client_config] (id = 1).
final youtubeOnboardingConfigProvider =
    FutureProvider.autoDispose<YoutubeOnboardingConfig>((ref) async {
  final row = await Supabase.instance.client
      .from('app_client_config')
      .select(
        'youtube_onboarding_enabled, youtube_drawer_enabled, youtube_onboarding_url',
      )
      .eq('id', 1)
      .maybeSingle();
  final popupEnabled = row?['youtube_onboarding_enabled'] as bool? ?? false;
  final drawerEnabled = row?['youtube_drawer_enabled'] as bool? ?? false;
  final url = (row?['youtube_onboarding_url'] as String? ?? '').trim();
  return YoutubeOnboardingConfig(
    popupEnabled: popupEnabled,
    drawerEnabled: drawerEnabled,
    url: url,
  );
});

class YoutubeOnboardingConfig {
  const YoutubeOnboardingConfig({
    required this.popupEnabled,
    required this.drawerEnabled,
    required this.url,
  });

  final bool popupEnabled;
  final bool drawerEnabled;
  final String url;

  bool get isPopupActive => popupEnabled && url.isNotEmpty;

  bool get isDrawerActive => drawerEnabled && url.isNotEmpty;
}

/// True when the signed-in user has not completed first-time onboarding.
final youtubeOnboardingPendingProvider = Provider<bool>((ref) {
  final config = ref.watch(youtubeOnboardingConfigProvider).value;
  if (config == null || !config.isPopupActive) return false;
  final profile = ref.watch(pharmacyProfileProvider).value;
  if (profile == null) return false;
  return profile['youtube_onboarding_seen_at'] == null;
});

Future<void> markYoutubeOnboardingSeen(WidgetRef ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return;
  await Supabase.instance.client.from('profiles').update({
    'youtube_onboarding_seen_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', uid);
  ref.invalidate(pharmacyProfileProvider);
}

/// Clears first-time seen for the signed-in user (testing). Hot restart or
/// re-login may be needed for the popup host to show again in the same session.
Future<void> resetYoutubeOnboardingSeen(WidgetRef ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return;
  await Supabase.instance.client.from('profiles').update({
    'youtube_onboarding_seen_at': null,
  }).eq('id', uid);
  ref.invalidate(pharmacyProfileProvider);
}
