import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamSuspendedPage extends StatelessWidget {
  const TeamSuspendedPage({super.key});

  Future<void> _signOutAndGoLogin(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suspended')),
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
                onPressed: () => _signOutAndGoLogin(context),
                child: const Text('Sign out'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _signOutAndGoLogin(context),
                child: const Text('Retry with another account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
