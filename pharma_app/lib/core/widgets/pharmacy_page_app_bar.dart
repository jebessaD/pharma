import 'package:flutter/material.dart';

import '../layout/layout_density.dart';

/// Modern flat app bar defaults for pharmacy screens.
AppBarTheme pharmacyAppBarTheme(ColorScheme cs) {
  return AppBarTheme(
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    backgroundColor: cs.surface,
    foregroundColor: cs.onSurface,
    titleSpacing: 0,
    toolbarHeight: 52,
  );
}

Widget pharmacyAppBarTitle(
  BuildContext context,
  String title, {
  String? subtitle,
}) {
  final t = Theme.of(context);
  final cs = t.colorScheme;
  final titleStyle = t.textTheme.titleMedium?.copyWith(
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    height: 1.15,
  );
  if (subtitle == null || subtitle.trim().isEmpty) {
    return Text(
      title,
      style: titleStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        title,
        style: titleStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      Text(
        subtitle,
        style: t.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          height: 1.2,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}

/// Standard pharmacy screen bar: back + **left-aligned title** (always visible).
PreferredSizeWidget pharmacyPageAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
  bool automaticallyImplyLeading = true,
  Widget? leading,
}) {
  final t = Theme.of(context);
  final hasSubtitle = subtitle != null && subtitle.trim().isNotEmpty;
  return AppBar(
    title: pharmacyAppBarTitle(context, title, subtitle: subtitle),
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    backgroundColor: t.colorScheme.surface,
    toolbarHeight: hasSubtitle ? 60 : 52,
    automaticallyImplyLeading: automaticallyImplyLeading,
    leading: leading,
    actions: actions,
    bottom: bottom,
  );
}

/// @deprecated Use [pharmacyPageAppBar] with a [title] instead.
PreferredSizeWidget pharmacyBackAppBar(
  BuildContext context, {
  String title = '',
  String? subtitle,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
  bool automaticallyImplyLeading = true,
  Widget? leading,
}) {
  return pharmacyPageAppBar(
    context,
    title: title,
    subtitle: subtitle,
    actions: actions,
    bottom: bottom,
    automaticallyImplyLeading: automaticallyImplyLeading,
    leading: leading,
  );
}

/// Standalone pages (auth, landing) — same title style as in-app routes.
PreferredSizeWidget pharmacyHubAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget>? actions,
  bool automaticallyImplyLeading = true,
  Widget? leading,
}) {
  return pharmacyPageAppBar(
    context,
    title: title,
    subtitle: subtitle,
    actions: actions,
    automaticallyImplyLeading: automaticallyImplyLeading,
    leading: leading,
  );
}

/// Compact hub title (Stock, Expiry, Stock history).
class HubPageHeader extends StatelessWidget {
  const HubPageHeader({
    super.key,
    required this.title,
    this.padding,
    this.actions = const [],
  });

  final String title;
  final EdgeInsetsGeometry? padding;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final density = context.layoutDensity;
    return Padding(
      padding: padding ?? density.hubHeaderPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              style: density.hubTitleStyle(t.textTheme),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// In-content title for shell root screens (no nested app bar / no back).
class PharmacyPageHeader extends StatelessWidget {
  const PharmacyPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: t.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.35,
              height: 1.15,
            ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: t.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
