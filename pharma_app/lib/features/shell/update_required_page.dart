import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/app_update_gate_provider.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

String _pickStoreUrl(AppUpdateGateState s) {
  if (kIsWeb) {
    return (s.storeUrlWeb ?? '').trim();
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return (s.storeUrlIos ?? s.storeUrlWeb ?? '').trim();
    default:
      return (s.storeUrlAndroid ?? s.storeUrlWeb ?? '').trim();
  }
}

/// Non-dismissible when [AppUpdateGateState.blocked]; opens store / web install URL.
class UpdateRequiredPage extends ConsumerWidget {
  const UpdateRequiredPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(appUpdateGateNotifierProvider);
    final message = gate?.message?.trim();
    final url = gate != null ? _pickStoreUrl(gate) : '';

    return Scaffold(
      appBar: pharmacyHubAppBar(context, title: 'Update required'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.system_update_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'A newer version of Pharma Shelf is required to continue.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (message != null && message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: url.isEmpty
                      ? null
                      : () async {
                          final uri = Uri.tryParse(url);
                          if (uri == null) return;
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                  child: const Text('Get update'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    await ref.read(appUpdateGateNotifierProvider.notifier).refresh();
                  },
                  child: const Text('Check again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
