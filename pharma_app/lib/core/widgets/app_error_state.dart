import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'form_error_banner.dart';

/// Full-page load failure with optional retry. Use [kDebugMode] to show details.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.debugDetails,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? debugDetails;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              FormErrorBanner(message: message),
              if (kDebugMode && debugDetails != null && debugDetails!.isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(
                  debugDetails!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
