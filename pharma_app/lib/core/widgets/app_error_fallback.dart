import 'package:flutter/material.dart';

/// Shown when a widget subtree fails to build and no local error UI exists.
/// Paired with [ErrorWidget.builder] in [main.dart].
class AppErrorFallback extends StatelessWidget {
  const AppErrorFallback({super.key});

  static ThemeData _themeOrLight(BuildContext context) {
    try {
      return Theme.of(context);
    } catch (_) {
      return ThemeData.light(useMaterial3: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themeOrLight(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sentiment_dissatisfied_outlined,
                  size: 48,
                  color: colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This screen could not be displayed. Try going back or '
                  'restarting the app if the problem continues.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
