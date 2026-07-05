import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/pos/offline/pos_offline_providers.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/layout/layout_density.dart';

class PharmaApp extends ConsumerWidget {
  const PharmaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(posSyncServiceProvider);
    final isOnline = ref.watch(connectivityProvider).value ?? true;
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'Pharma Shelf',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      builder: (context, child) {
        final content = adaptiveTextScaleScope(
          context,
          child ?? const SizedBox.shrink(),
        );
        if (isOnline) return content;
        return Column(
          children: [
            const _OfflineConnectionBanner(),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

class _OfflineConnectionBanner extends StatelessWidget {
  const _OfflineConnectionBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      label: 'No internet connection. Check your network, then try again.',
      child: Material(
        color: cs.errorContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: cs.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No internet connection. Check your network, then try again.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
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
