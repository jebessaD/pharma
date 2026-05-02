import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/post_pharmacy_sign_out.dart';
import '../../core/shared_preferences_provider.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';
import 'contact_us_page.dart'
    show kSupportEmail, kSupportTelegramHandle, kSupportTelegramUrl;

Future<void> _launchSupportUri(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open the link. Try copying it from Contact us.'),
      ),
    );
  }
}

/// Shown when [PharmacyGateData] billing state blocks access (non-trial reasons).
class BillingBlockedPage extends ConsumerWidget {
  const BillingBlockedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: pharmacyHubAppBar(context, title: 'Account'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.payments_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'This pharmacy account cannot be used right now.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Billing or subscription needs attention. Contact your account owner to restore access, or reach Dadu Dev Studio on Telegram or email.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SelectableText(
                  kSupportTelegramHandle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  kSupportEmail,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _launchSupportUri(
                        context,
                        Uri.parse(kSupportTelegramUrl),
                      ),
                      icon: const Icon(Icons.chat_outlined, size: 20),
                      label: const Text('Telegram'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _launchSupportUri(
                        context,
                        Uri.parse('mailto:$kSupportEmail'),
                      ),
                      icon: const Icon(Icons.email_outlined, size: 20),
                      label: const Text('Email'),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () async {
                    if (!context.mounted) return;
                    final container =
                        ProviderScope.containerOf(context, listen: false);
                    final prevTeam = container
                            .read(pharmacyProfileProvider)
                            .value?['team_id']
                        as String?;
                    final prefs = container.read(sharedPreferencesProvider);
                    await Supabase.instance.client.auth.signOut();
                    schedulePharmacySignOutCleanup(
                      container: container,
                      prefs: prefs,
                      teamId: prevTeam,
                    );
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
