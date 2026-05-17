import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/youtube_brand_icon.dart';

/// Static YouTube thumbnail preview (no WebView — safe inside dialogs).
class YoutubeTutorialPreview extends StatelessWidget {
  const YoutubeTutorialPreview({
    super.key,
    required this.videoId,
    this.onTap,
  });

  final String videoId;
  final VoidCallback? onTap;

  static String thumbnailUrl(String videoId) =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final glow = cs.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: glow.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.seedGreen.withValues(alpha: 0.32),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: glow.withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Material(
            color: const Color(0xFF121212),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: InkWell(
                onTap: onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      thumbnailUrl(videoId),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: cs.onSurfaceVariant,
                          size: 40,
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            glow.withValues(alpha: 0.06),
                            Colors.black.withValues(alpha: 0.52),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Material(
                        elevation: 5,
                        shadowColor: glow.withValues(alpha: 0.55),
                        surfaceTintColor: Colors.transparent,
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(14),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 40,
                            color: YoutubeBrandIcon.brandRed,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
