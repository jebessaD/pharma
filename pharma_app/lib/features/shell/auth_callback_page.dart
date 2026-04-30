import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shown while the OS opens `pharmaapp://auth/callback?...` after email links.
/// [supabase_flutter] exchanges the PKCE `code` via its deep-link observer; this
/// route only prevents [GoRouter] from treating the link as an unknown location.
class AuthCallbackPage extends StatelessWidget {
  const AuthCallbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Completing sign-in...'),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Back to login'),
            ),
          ],
        ),
      ),
    );
  }
}
