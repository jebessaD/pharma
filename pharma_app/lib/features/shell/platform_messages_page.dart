import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/platform_messages_provider.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

class PlatformMessagesPage extends ConsumerWidget {
  const PlatformMessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(platformOpsProvider);

    return Scaffold(
      appBar: pharmacyHubAppBar(context, title: 'Announcements'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          message: userFacingError(e),
          debugDetails: e.toString(),
          onRetry: () => ref.invalidate(platformOpsProvider),
        ),
        data: (snap) {
          if (snap.messages.isEmpty) {
            return const Center(child: Text('No announcements right now.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: snap.messages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final m = snap.messages[i];
              final id = m['id'] as String? ?? '';
              final read = snap.readIds.contains(id);
              final title = m['title'] as String? ?? '';
              final body = m['body'] as String? ?? '';
              final sev = m['severity'] as String? ?? 'info';
              final icon = switch (sev) {
                'critical' => Icons.error_outline_rounded,
                'warning' => Icons.warning_amber_rounded,
                _ => Icons.info_outline_rounded,
              };
              final color = switch (sev) {
                'critical' => Theme.of(context).colorScheme.error,
                'warning' => Theme.of(context).colorScheme.tertiary,
                _ => Theme.of(context).colorScheme.primary,
              };
              return Card(
                elevation: read ? 0 : 0.5,
                child: InkWell(
                  onTap: id.isEmpty || read
                      ? null
                      : () => markPlatformMessageRead(ref, id),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: color, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (body.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  body,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(height: 1.35),
                                ),
                              ],
                              if (!read) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to dismiss',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
