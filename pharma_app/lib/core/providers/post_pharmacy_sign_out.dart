import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_persistence.dart';
import '../router/app_router.dart';
import '../../features/pos/offline/pos_offline_providers.dart';
import 'pharmacy_session_cleanup.dart';

/// Runs session cleanup, local auth markers, POS outbox clear, and navigation
/// on the **next frame** after [auth.signOut] completes.
///
/// Immediate invalidation can run while the pharmacy shell is still tearing
/// down and triggers Riverpod / framework errors ("modify provider while
/// building", defunct elements).
void schedulePharmacySignOutCleanup({
  required ProviderContainer container,
  required SharedPreferences prefs,
  String? teamId,
}) {
  final router = container.read(goRouterProvider);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void> run() async {
      await resetPharmacySessionProviders(container, teamId: teamId);
      await clearLocalAuthMarker(prefs);
      await container.read(posOutboxRepositoryProvider).clearAll();
      router.go('/login');
    }

    unawaited(run());
  });
}
