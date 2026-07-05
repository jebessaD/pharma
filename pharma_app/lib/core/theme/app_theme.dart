import 'package:flutter/material.dart';

import '../widgets/pharmacy_page_app_bar.dart';

abstract final class AppTheme {
  static const Color seedGreen = Color(0xFF2E7D32);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedGreen,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: pharmacyAppBarTheme(colorScheme),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: seedGreen,
      ),
    );
  }
}
