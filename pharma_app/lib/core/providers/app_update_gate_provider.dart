import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_version_compare.dart';

/// Triggers [GoRouter] refresh after app-update gate hydration (with [auth](supabaseAuthRefreshProvider)).
final appUpdateRefreshProvider = Provider<AppUpdateRefresh>((ref) {
  final n = AppUpdateRefresh();
  ref.onDispose(n.dispose);
  return n;
});

final class AppUpdateRefresh extends ChangeNotifier {
  void bump() => notifyListeners();
}

class AppUpdateGateState {
  const AppUpdateGateState({
    required this.blocked,
    this.message,
    this.storeUrlIos,
    this.storeUrlAndroid,
    this.storeUrlWeb,
  });

  final bool blocked;
  final String? message;
  final String? storeUrlIos;
  final String? storeUrlAndroid;
  final String? storeUrlWeb;
}

class AppUpdateGateNotifier extends Notifier<AppUpdateGateState?> {
  Future<void>? _inFlight;

  @override
  AppUpdateGateState? build() => null;

  Future<void> ensureHydrated() async {
    if (state != null) return;
    _inFlight ??= _load();
    await _inFlight;
  }

  Future<void> refresh() async {
    state = null;
    _inFlight = null;
    await _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final row = await Supabase.instance.client
          .from('app_client_config')
          .select(
            'min_supported_version, update_message, store_url_ios, store_url_android, store_url_web, force_update',
          )
          .eq('id', 1)
          .maybeSingle();

      if (row == null) {
        state = const AppUpdateGateState(blocked: false);
        ref.read(appUpdateRefreshProvider).bump();
        return;
      }

      final force = row['force_update'] == true;
      final min = row['min_supported_version'] as String? ?? '1.0.0';
      final below = isBelowMinimumSupported(info.version, min);

      state = AppUpdateGateState(
        blocked: force && below,
        message: row['update_message'] as String?,
        storeUrlIos: row['store_url_ios'] as String?,
        storeUrlAndroid: row['store_url_android'] as String?,
        storeUrlWeb: row['store_url_web'] as String?,
      );
    } catch (_) {
      state = const AppUpdateGateState(blocked: false);
    } finally {
      _inFlight = null;
      ref.read(appUpdateRefreshProvider).bump();
    }
  }
}

final appUpdateGateNotifierProvider =
    NotifierProvider<AppUpdateGateNotifier, AppUpdateGateState?>(
  AppUpdateGateNotifier.new,
);
