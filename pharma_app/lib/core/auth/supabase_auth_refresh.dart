import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseAuthRefresh extends ChangeNotifier {
  SupabaseAuthRefresh() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        _passwordRecoveryPending = true;
      } else if (event == AuthChangeEvent.signedOut) {
        _passwordRecoveryPending = false;
      }
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _sub;

  bool _passwordRecoveryPending = false;

  /// True after the user opens a password recovery deep link until they finish
  /// setting a new password or sign out.
  bool get passwordRecoveryPending => _passwordRecoveryPending;

  void consumePasswordRecovery() {
    if (!_passwordRecoveryPending) return;
    _passwordRecoveryPending = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
