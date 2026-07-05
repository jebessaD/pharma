import 'package:flutter/material.dart';

/// Forest green accents on clean white cards.
abstract final class ReportPalette {
  static const forest = Color(0xFF1B4332);
  static const green = Color(0xFF40916C);
  static const pageBg = Color(0xFFF5F5F5);
  static const label = Color(0xFF6B7280);
  static const alert = Color(0xFFDC2626);
  static const amber = Color(0xFFD97706);
  static const blue = Color(0xFF2563EB);
  static const cardWhite = Colors.white;
  static const iconWell = Colors.white;
}

abstract final class ReportUi {
  static Color pageBackground(ColorScheme cs) => cs.surface;

  static Color cardFill(ColorScheme cs) => ReportPalette.cardWhite;

  static Color hairline(ColorScheme cs) =>
      cs.outlineVariant.withValues(alpha: 0.2);

  static Color mutedText(ColorScheme cs) => ReportPalette.label;

  static BorderRadius get radiusLg => BorderRadius.circular(18);

  static BorderRadius get radiusMd => BorderRadius.circular(14);

  static BorderRadius get radiusSm => BorderRadius.circular(12);

  static BoxDecoration surfaceCard(
    ColorScheme cs, {
    Color? fill,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: fill ?? cardFill(cs),
      borderRadius: radiusLg,
      border: Border.all(color: borderColor ?? hairline(cs)),
    );
  }

  static BoxDecoration insetPanel(ColorScheme cs) {
    return BoxDecoration(
      color: ReportPalette.cardWhite,
      borderRadius: radiusMd,
      border: Border.all(color: hairline(cs)),
    );
  }

  static BoxDecoration iconWellBorder(ColorScheme cs) {
    return BoxDecoration(
      color: ReportPalette.iconWell,
      borderRadius: radiusSm,
      border: Border.all(color: hairline(cs)),
    );
  }

  static TextStyle captionLabel(TextTheme t, {Color? color}) {
    return t.labelSmall!.copyWith(
      color: color ?? ReportPalette.label,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );
  }

  static ButtonStyle segmentedStyle(ColorScheme cs, TextTheme textTheme) {
    return SegmentedButton.styleFrom(
      backgroundColor: ReportPalette.cardWhite,
      selectedBackgroundColor: ReportPalette.cardWhite,
      selectedForegroundColor: ReportPalette.forest,
      foregroundColor: ReportPalette.label,
      side: BorderSide(color: hairline(cs)),
      elevation: 0,
      shadowColor: Colors.transparent,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  static Widget liveStatsHeader(
    BuildContext context, {
    String trailing = 'Report active',
  }) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(Icons.monitor_heart_outlined, size: 18, color: ReportPalette.green),
          const SizedBox(width: 8),
          Text(
            'LIVE STATS',
            style: captionLabel(t.textTheme, color: ReportPalette.label),
          ),
          const Spacer(),
          Text(
            trailing,
            style: t.textTheme.labelSmall?.copyWith(
              color: ReportPalette.label.withValues(alpha: 0.75),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static Widget sectionTitle(BuildContext context, String title) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: ReportPalette.forest,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: t.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: ReportPalette.forest,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  static Widget heroMetricCard({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    final t = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: surfaceCard(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: captionLabel(t.textTheme)),
          const SizedBox(height: 8),
          Text(
            value,
            style: t.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }

  static Widget metricGrid({
    required BuildContext context,
    required List<ReportMetricTileData> tiles,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: surfaceCard(cs),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var row = 0; row < tiles.length; row += 2) ...[
            if (row > 0) Divider(height: 1, color: hairline(cs)),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _metricTile(context, tiles[row])),
                  if (row + 1 < tiles.length) ...[
                    VerticalDivider(width: 1, color: hairline(cs)),
                    Expanded(child: _metricTile(context, tiles[row + 1])),
                  ] else
                    const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _metricTile(BuildContext context, ReportMetricTileData tile) {
    final t = Theme.of(context);
    final valueColor = tile.valueColor ?? Colors.black;
    return Material(
      color: tile.background ?? Colors.transparent,
      child: InkWell(
        onTap: tile.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tile.label, style: captionLabel(t.textTheme)),
              const SizedBox(height: 8),
              Text(
                tile.value,
                style: t.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportMetricTileData {
  const ReportMetricTileData({
    required this.label,
    required this.value,
    this.valueColor,
    this.background,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Color? background;
  final VoidCallback? onTap;
}

class ReportDateChip extends StatelessWidget {
  const ReportDateChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: ReportUi.radiusMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: ReportUi.radiusMd,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: ReportUi.radiusMd,
            color: Colors.white,
            border: Border.all(
              color: selected
                  ? ReportPalette.green
                  : ReportUi.hairline(Theme.of(context).colorScheme),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              label,
              style: t.textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? ReportPalette.forest : ReportPalette.label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
