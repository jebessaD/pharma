import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '_agent_debug_log.dart';
import 'app.dart';
import 'core/shared_preferences_provider.dart';
import 'core/supabase_config.dart';
import 'core/widgets/app_error_fallback.dart';

// #region agent log
void _installAgentDebugErrorHooks() {
  final priorFlutter = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    unawaited(
      agentDebugLog(
        'main.dart:FlutterError.onError',
        details.exceptionAsString(),
        {
          'library': details.library ?? '',
          'summary': details.summary.toString(),
          'stack': () {
            final s = details.stack?.toString() ?? '';
            return s.length > 2500 ? '${s.substring(0, 2500)}…' : s;
          }(),
        },
        hypothesisId: 'H1',
      ),
    );
    if (priorFlutter != null) {
      priorFlutter(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  final priorZone = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    unawaited(
      agentDebugLog(
        'main.dart:PlatformDispatcher.onError',
        error.runtimeType.toString(),
        {
          'error': error.toString(),
          'stack': () {
            final s = stack.toString();
            return s.length > 2500 ? '${s.substring(0, 2500)}…' : s;
          }(),
        },
        hypothesisId: 'H2',
      ),
    );
    return priorZone?.call(error, stack) ?? false;
  };
}
// #endregion

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kDebugMode) {
      return ErrorWidget(details.exception);
    }
    return const AppErrorFallback();
  };
  // #region agent log
  _installAgentDebugErrorHooks();
  // #endregion
  try {
    final prefs = await SharedPreferences.getInstance();
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const PharmaApp(),
      ),
    );
  } catch (e, stack) {
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(
        FlutterErrorDetails(
          exception: e,
          stack: stack,
          library: 'pharma bootstrap',
        ),
      );
    }
    unawaited(
      agentDebugLog(
        'main.dart:bootstrap',
        e.runtimeType.toString(),
        {
          'error': e.toString(),
          'stack': () {
            final s = stack.toString();
            return s.length > 2500 ? '${s.substring(0, 2500)}…' : s;
          }(),
        },
        hypothesisId: 'H0',
      ),
    );
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(useMaterial3: true),
        home: const AppErrorFallback(),
      ),
    );
  }
}
