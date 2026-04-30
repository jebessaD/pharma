import 'package:flutter/material.dart';

/// Shared shell for pharmacy hub screens: one [AppBar], primary [TabBar], [TabBarView].
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
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final hasHeaderText = title.trim().isNotEmpty || (subtitle?.trim().isNotEmpty ?? false);
    return Scaffold(
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      appBar: AppBar(
        toolbarHeight: hasHeaderText ? null : 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: t.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(
                subtitle!,
                style: t.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
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
