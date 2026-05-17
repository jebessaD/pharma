import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/youtube_onboarding_provider.dart';
import 'youtube_onboarding_dialog.dart';

/// Shows the first-time onboarding dialog once per session when DB config allows.
class YoutubeOnboardingHost extends ConsumerStatefulWidget {
  const YoutubeOnboardingHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<YoutubeOnboardingHost> createState() =>
      _YoutubeOnboardingHostState();
}

class _YoutubeOnboardingHostState extends ConsumerState<YoutubeOnboardingHost> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPopup());
  }

  void _maybeShowPopup() {
    if (_scheduled) return;
    final pending = ref.read(youtubeOnboardingPendingProvider);
    if (!pending) return;

    final config = ref.read(youtubeOnboardingConfigProvider).value;
    if (config == null || !config.isPopupActive) return;

    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showYoutubeOnboardingDialog(context, ref, url: config.url);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(youtubeOnboardingConfigProvider, (_, next) {
      next.whenData((_) => _maybeShowPopup());
    });
    ref.listen(pharmacyProfileProvider, (previous, next) => _maybeShowPopup());
    ref.listen(youtubeOnboardingPendingProvider, (previous, next) {
      if (next && previous != true) {
        _scheduled = false;
        _maybeShowPopup();
      }
    });

    ref.watch(youtubeOnboardingConfigProvider);
    ref.watch(pharmacyProfileProvider);

    return widget.child;
  }
}
