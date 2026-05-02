import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/pos/offline/pos_offline_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class PharmaApp extends ConsumerWidget {
  const PharmaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(posSyncServiceProvider);
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'Pharma Shelf',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
