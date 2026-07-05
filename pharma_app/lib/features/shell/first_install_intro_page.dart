import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_assets.dart';
import '../../core/onboarding/first_install_intro.dart';
import '../../core/shared_preferences_provider.dart';

class FirstInstallIntroPage extends ConsumerStatefulWidget {
  const FirstInstallIntroPage({super.key});

  @override
  ConsumerState<FirstInstallIntroPage> createState() =>
      _FirstInstallIntroPageState();
}

class _FirstInstallIntroPageState extends ConsumerState<FirstInstallIntroPage> {
  bool _finishing = false;

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final prefs = ref.read(sharedPreferencesProvider);
    await markFirstInstallIntroSeen(prefs);
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _finishing ? null : _finish,
                      child: const Text('Skip'),
                    ),
                  ),
                  const Spacer(flex: 2),
                  Center(
                    child: Image.asset(
                      AppAssets.logo,
                      height: 96,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to Pharma Shelf',
                    textAlign: TextAlign.center,
                    style: t.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sell, track stock, and run your pharmacy from one app.',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const Spacer(flex: 3),
                  FilledButton(
                    onPressed: _finishing ? null : _finish,
                    child: _finishing
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Get started'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
