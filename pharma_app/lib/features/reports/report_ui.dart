import 'package:flutter/material.dart';

/// Accent helpers; prefer [ColorScheme] via [ReportUi] for surfaces and text.
abstract final class ReportPalette {
  static Color primary(ColorScheme cs) => cs.primary;

  static Color onSurface(ColorScheme cs) => cs.onSurface;

  static Color alert(ColorScheme cs) => cs.error;

  static Color amber(ColorScheme cs) => const Color(0xFFD97706);

  static Color blue(ColorScheme cs) => cs.tertiary;
}

abstract final class ReportUi {
  static Color pageBackground(ColorScheme cs) => cs.surface;

  static Color cardFill(ColorScheme cs) => cs.surface;

  static Color hairline(ColorScheme cs) =>
      cs.outlineVariant.withValues(alpha: 0.45);

  static Color mutedText(ColorScheme cs) => cs.onSurfaceVariant;

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
      color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
      borderRadius: radiusMd,
      border: Border.all(color: hairline(cs)),
    );
  }

  static BoxDecoration iconWellBorder(ColorScheme cs) {
    return BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: radiusSm,
      border: Border.all(color: hairline(cs)),
    );
  }

  static TextStyle captionLabel(TextTheme t, ColorScheme cs, {Color? color}) {
    return t.labelSmall!.copyWith(
      color: color ?? cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );
  }

  static ButtonStyle segmentedStyle(ColorScheme cs, TextTheme textTheme) {
    return SegmentedButton.styleFrom(
      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.25),
      selectedBackgroundColor: cs.primaryContainer.withValues(alpha: 0.55),
      selectedForegroundColor: cs.primary,
      foregroundColor: cs.onSurfaceVariant,
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
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(Icons.monitor_heart_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            'LIVE STATS',
            style: captionLabel(t.textTheme, cs, color: mutedText(cs)),
          ),
          const Spacer(),
          Text(
            trailing,
            style: t.textTheme.labelSmall?.copyWith(
              color: mutedText(cs).withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static Widget sectionTitle(BuildContext context, String title) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: t.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
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
          Text(label, style: captionLabel(t.textTheme, cs)),
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
    final cs = t.colorScheme;
    final valueColor = tile.valueColor ?? cs.onSurface;
    return Material(
      color: tile.background ?? Colors.transparent,
      child: InkWell(
        onTap: tile.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tile.label, style: captionLabel(t.textTheme, cs)),
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
    final cs = t.colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: ReportUi.radiusMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: ReportUi.radiusMd,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: ReportUi.radiusMd,
            color: selected
                ? cs.primaryContainer.withValues(alpha: 0.45)
                : cs.surfaceContainerHighest.withValues(alpha: 0.2),
            border: Border.all(
              color: selected ? cs.primary : ReportUi.hairline(cs),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              label,
              style: t.textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
