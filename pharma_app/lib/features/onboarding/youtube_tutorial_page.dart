import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/widgets/youtube_brand_icon.dart';
import 'youtube_onboarding_actions.dart';

/// Full-screen YouTube tutorial (WebView works here; not inside a dialog).
class YoutubeTutorialPage extends ConsumerStatefulWidget {
  const YoutubeTutorialPage({
    super.key,
    required this.videoId,
    required this.fallbackUrl,
  });

  final String videoId;
  final String fallbackUrl;

  @override
  ConsumerState<YoutubeTutorialPage> createState() =>
      _YoutubeTutorialPageState();
}

class _YoutubeTutorialPageState extends ConsumerState<YoutubeTutorialPage> {
  late final YoutubePlayerController _controller;
  late final StreamSubscription<YoutubePlayerValue> _sub;
  bool _embedFailed = false;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        privacyEnhancedMode: false,
        enableCaption: true,
      ),
    );
    _controller.cueVideoById(videoId: widget.videoId);
    _sub = _controller.listen((value) {
      if (!mounted) return;
      if (value.hasError && !_embedFailed) {
        setState(() => _embedFailed = true);
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _controller.close();
    super.dispose();
  }

  Future<void> _openExternal() async {
    final ok = await openYoutubeOnboardingUrl(widget.fallbackUrl);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open YouTube.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('How to use'),
        actions: [
          TextButton(
            onPressed: _openExternal,
            child: const Text('YouTube app'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_embedFailed)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const YoutubeBrandIcon(size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'This video cannot play inside the app.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The owner may have disabled embedding. Open it in the YouTube app instead.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _openExternal,
                        child: const Text('Open in YouTube'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            YoutubePlayer(
              controller: _controller,
              aspectRatio: 16 / 9,
              backgroundColor: Colors.black,
              autoFullScreen: true,
            ),
          if (!_embedFailed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Use fullscreen for a larger view. Captions are available in the player controls.',
                style: t.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
