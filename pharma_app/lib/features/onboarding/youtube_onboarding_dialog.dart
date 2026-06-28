import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/youtube_onboarding_provider.dart';
import '../../core/youtube_video_id.dart';
import 'youtube_onboarding_actions.dart';
import 'youtube_tutorial_preview.dart';

Future<void> showYoutubeOnboardingDialog(
  BuildContext context,
  WidgetRef ref, {
  required String url,
  bool markSeenOnClose = true,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (dialogContext) => _YoutubeOnboardingDialog(
      url: url,
      onDismiss: () => Navigator.of(dialogContext).pop(),
    ),
  );
  if (!context.mounted) return;
  if (markSeenOnClose && ref.read(youtubeOnboardingPendingProvider)) {
    await dismissYoutubeOnboarding(ref);
  }
}

Future<void> openYoutubeTutorial(
  BuildContext context, {
  required String url,
}) async {
  final ok = await openYoutubeOnboardingUrl(url);
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open YouTube.')),
    );
  }
}

class _YoutubeOnboardingDialog extends StatelessWidget {
  const _YoutubeOnboardingDialog({
    required this.url,
    required this.onDismiss,
  });

  final String url;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final videoId = youtubeVideoIdFromUrl(url);
    final width = MediaQuery.sizeOf(context).width;
    final dialogWidth = width > 480 ? 420.0 : width - 32;

    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.none,
      child: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (videoId != null)
                  YoutubeTutorialPreview(
                    videoId: videoId,
                    onTap: () {
                      onDismiss();
                      openYoutubeTutorial(context, url: url);
                    },
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.videocam_off_outlined,
                          size: 40,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 24,
                  right: 24,
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.92),
                      foregroundColor: cs.onSurface,
                    ),
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to Pharma Shelf',
                    style: t.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    videoId != null
                        ? 'Tap the preview to open the tutorial in YouTube.'
                        : 'Tutorial link is invalid. Try opening it externally.',
                    style: t.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (videoId != null)
                    FilledButton(
                      onPressed: () {
                        onDismiss();
                        openYoutubeTutorial(context, url: url);
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Watch tutorial'),
                    ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                    child: const Text('Maybe later'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
