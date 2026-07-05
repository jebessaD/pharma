import 'package:flutter/material.dart';

import 'pharmacy_page_app_bar.dart';

/// Shared shell for pharmacy hub screens: title + [TabBar], flat bar.
class PharmacyHubScaffold extends StatelessWidget {
  const PharmacyHubScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.tabController,
    required this.tabs,
    required this.tabBarViewChildren,
    this.actions,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  final String title;
  final String? subtitle;
  final TabController tabController;
  final List<Tab> tabs;
  final List<Widget> tabBarViewChildren;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: pharmacyAppBarTitle(context, title, subtitle: subtitle),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: cs.surface,
        toolbarHeight: (subtitle != null && subtitle!.trim().isNotEmpty)
            ? 60
            : 52,
        actions: actions,
        bottom: TabBar(
          controller: tabController,
          tabs: tabs,
          dividerColor: cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: tabBarViewChildren,
      ),
    );
  }
}
