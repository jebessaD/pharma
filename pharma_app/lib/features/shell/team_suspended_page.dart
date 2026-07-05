import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/pharmacy_redirect_cache_provider.dart';
import '../../core/providers/post_pharmacy_sign_out.dart';
import '../../core/shared_preferences_provider.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

class TeamSuspendedPage extends ConsumerWidget {
  const TeamSuspendedPage({super.key});

  Future<void> _signOutAndGoLogin(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final profileTeam =
        container.read(pharmacyProfileProvider).value?['team_id'] as String?;
    final gateTeam = container.read(pharmacyRedirectCacheProvider)?.teamId;
    final prevTeam = (profileTeam != null && profileTeam.isNotEmpty)
        ? profileTeam
        : gateTeam;
    final prefs = container.read(sharedPreferencesProvider);
    await Supabase.instance.client.auth.signOut();
    schedulePharmacySignOutCleanup(
      container: container,
      prefs: prefs,
      teamId: prevTeam,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: pharmacyHubAppBar(context, title: 'Suspended'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 64),
              const SizedBox(height: 16),
              Text(
                'This pharmacy team is suspended.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _signOutAndGoLogin(context, ref),
                child: const Text('Sign out'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _signOutAndGoLogin(context, ref),
                child: const Text('Retry with another account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
