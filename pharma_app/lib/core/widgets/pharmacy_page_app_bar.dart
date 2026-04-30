import 'package:flutter/material.dart';

/// Consistent app bar title styling for pharmacy hub pages.
PreferredSizeWidget pharmacyHubAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  bool automaticallyImplyLeading = true,
  Widget? leading,
}) {
  final t = Theme.of(context);
  return AppBar(
    title: Text(
      title,
      style: t.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
    ),
    centerTitle: false,
    automaticallyImplyLeading: automaticallyImplyLeading,
    leading: leading,
    actions: actions,
  );
}
