import 'package:flutter/material.dart';

/// Screen + accessibility tier for spacing and typography.
enum LayoutDensity { compact, standard, comfortable }

/// Resolved density from **display zoom** (logical size) + system font scale.
///
/// Uses [Size.shortestSide] so Galaxy S8+ (~360dp) and S20+ (~400dp) land in
/// different tiers when display zoom differs.
class LayoutDensityData {
  const LayoutDensityData(this.tier);

  final LayoutDensity tier;

  bool get isCompact => tier == LayoutDensity.compact;

  bool get isStandard => tier == LayoutDensity.standard;

  bool get isComfortable => tier == LayoutDensity.comfortable;

  static LayoutDensityData of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return resolve(size: mq.size, textScaler: mq.textScaler);
  }

  /// Typical portrait logical shortest side (dp):
  /// - Large display zoom / S8+ class: ~360
  /// - Default S20+: ~392–412
  static LayoutDensityData resolve({
    required Size size,
    required TextScaler textScaler,
  }) {
    final textScale = textScaler.scale(1.0);
    final shortest = size.shortestSide;

    if (textScale >= 1.35 || shortest < 358) {
      return const LayoutDensityData(LayoutDensity.compact);
    }

    if (textScale >= 1.18 && shortest < 380) {
      return const LayoutDensityData(LayoutDensity.compact);
    }

    if (shortest >= 392 && textScale <= 1.05) {
      return const LayoutDensityData(LayoutDensity.comfortable);
    }

    return const LayoutDensityData(LayoutDensity.standard);
  }

  double v({
    required double compact,
    required double standard,
    required double comfortable,
  }) {
    switch (tier) {
      case LayoutDensity.compact:
        return compact;
      case LayoutDensity.standard:
        return standard;
      case LayoutDensity.comfortable:
        return comfortable;
    }
  }

  TextStyle? hubTitleStyle(TextTheme t) {
    switch (tier) {
      case LayoutDensity.compact:
        return t.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.25,
          height: 1.15,
        );
      case LayoutDensity.standard:
        return t.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          height: 1.15,
        );
      case LayoutDensity.comfortable:
        return t.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
          height: 1.15,
        );
    }
  }

  TextStyle? listTitleStyle(TextTheme t) {
    switch (tier) {
      case LayoutDensity.compact:
        return t.titleSmall?.copyWith(fontWeight: FontWeight.w600);
      case LayoutDensity.standard:
        return t.titleSmall?.copyWith(fontWeight: FontWeight.w600);
      case LayoutDensity.comfortable:
        return t.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    }
  }

  TextStyle? listSubtitleStyle(TextTheme t, ColorScheme cs) {
    switch (tier) {
      case LayoutDensity.compact:
        return t.labelSmall?.copyWith(color: cs.onSurfaceVariant);
      case LayoutDensity.standard:
        return t.labelSmall?.copyWith(color: cs.onSurfaceVariant);
      case LayoutDensity.comfortable:
        return t.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    }
  }

  EdgeInsets get hubHeaderPadding => EdgeInsets.fromLTRB(
    v(compact: 12, standard: 16, comfortable: 20),
    v(compact: 6, standard: 8, comfortable: 12),
    v(compact: 4, standard: 4, comfortable: 8),
    v(compact: 4, standard: 4, comfortable: 8),
  );

  EdgeInsets get pageHorizontalPadding => EdgeInsets.symmetric(
    horizontal: v(compact: 12, standard: 14, comfortable: 16),
  );

  double get listCardPaddingH =>
      v(compact: 10, standard: 12, comfortable: 14);

  double get listCardPaddingV =>
      v(compact: 8, standard: 10, comfortable: 12);

  double get listRowRadius => v(compact: 10, standard: 10, comfortable: 12);

  double get listRowGap => v(compact: 6, standard: 6, comfortable: 8);

  double get listLineGap => v(compact: 2, standard: 2, comfortable: 3);

  double get listIconSize => v(compact: 20, standard: 20, comfortable: 22);

  double get listIconGap => v(compact: 10, standard: 10, comfortable: 12);

  double get avatarRadius =>
      v(compact: 16, standard: 18, comfortable: 22);

  double get iconBoxSize =>
      v(compact: 36, standard: 40, comfortable: 48);

  double get drawerIconBoxSize =>
      v(compact: 40, standard: 42, comfortable: 44);

  double get drawerIconSize =>
      v(compact: 22, standard: 23, comfortable: 24);

  double get searchFieldVerticalPadding =>
      v(compact: 10, standard: 12, comfortable: 14);

  bool posLikeCompact(Size size) => isCompact;

  String get debugLabel => switch (tier) {
    LayoutDensity.compact => 'compact',
    LayoutDensity.standard => 'standard',
    LayoutDensity.comfortable => 'comfortable',
  };
}

extension LayoutDensityContext on BuildContext {
  LayoutDensityData get layoutDensity => LayoutDensityData.of(this);
}

/// Soft text-scale cap on zoomed-in displays so large system fonts do not
/// overflow list rows. Tall / wide logical layouts keep full accessibility.
Widget adaptiveTextScaleScope(BuildContext context, Widget child) {
  final mq = MediaQuery.of(context);
  final shortest = mq.size.shortestSide;
  final scale = mq.textScaler.scale(1.0);

  double capped = scale;
  if (shortest < 372 && scale > 1.12) {
    capped = 1.12;
  } else if (shortest < 392 && scale > 1.22) {
    capped = 1.18;
  }

  if ((capped - scale).abs() < 0.001) return child;

  return MediaQuery(
    data: mq.copyWith(textScaler: TextScaler.linear(capped)),
    child: child,
  );
}
