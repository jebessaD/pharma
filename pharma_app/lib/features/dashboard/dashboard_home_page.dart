import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Legacy `/pharmacy/dashboard` route — redirects to unified Reports hub.
class DashboardHomePage extends StatelessWidget {
  const DashboardHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go('/pharmacy/reports');
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
