import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/youtube_onboarding_provider.dart';

Future<bool> openYoutubeOnboardingUrl(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> openYoutubeOnboardingFromApp(
  BuildContext context,
  WidgetRef ref, {
  required String url,
  bool markFirstTimeSeen = false,
}) async {
  final ok = await openYoutubeOnboardingUrl(url);
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open the tutorial link. Try again later.'),
      ),
    );
    return;
  }
  if (markFirstTimeSeen) {
    await markYoutubeOnboardingSeen(ref);
  }
}

Future<void> dismissYoutubeOnboarding(WidgetRef ref) async {
  await markYoutubeOnboardingSeen(ref);
}
