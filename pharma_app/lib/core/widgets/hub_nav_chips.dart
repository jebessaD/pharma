import 'package:flutter/material.dart';

/// Compact cross-links between stock / expiry hub tabs and related routes.
class HubNavChip {
  const HubNavChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
}

class HubNavChips extends StatelessWidget {
  const HubNavChips({super.key, required this.chips});

  final List<HubNavChip> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final chip in chips)
            FilterChip(
              label: Text(chip.label),
              avatar: chip.icon == null ? null : Icon(chip.icon, size: 16),
              selected: chip.selected,
              showCheckmark: chip.selected,
              onSelected: (_) => chip.onTap(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selectedColor: cs.primaryContainer.withValues(alpha: 0.55),
              side: BorderSide(
                color: chip.selected
                    ? cs.primary.withValues(alpha: 0.45)
                    : cs.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );
  }
}

/// White search + optional trailing filter row for hub list pages.
class HubListFilterBar extends StatelessWidget {
  const HubListFilterBar({
    super.key,
    required this.searchHint,
    required this.onSearchChanged,
    this.footer,
  });

  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: searchHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.25),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: onSearchChanged,
              ),
              if (footer != null) ...[
                const SizedBox(height: 8),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
