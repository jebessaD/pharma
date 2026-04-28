import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color seedGreen = Color(0xFF2E7D32);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedGreen,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(centerTitle: true),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: seedGreen,
      ),
    );
  }
}
