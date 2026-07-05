import 'package:flutter/material.dart';

import '../layout/layout_density.dart';

/// Standard filter block padding for hub list pages (Medicines, Stock, etc.).
EdgeInsets pharmacyHubFilterPadding(BuildContext context) {
  final h = context.layoutDensity.pageHorizontalPadding.horizontal / 2;
  return EdgeInsets.all(h);
}

/// Horizontal padding for hub list slivers.
EdgeInsets pharmacyHubListPadding(BuildContext context, {double bottom = 8}) {
  final h = context.layoutDensity.pageHorizontalPadding.horizontal / 2;
  return EdgeInsets.fromLTRB(h, 0, h, bottom);
}

class PharmacyHubSearchField extends StatelessWidget {
  const PharmacyHubSearchField({
    super.key,
    this.controller,
    required this.hintText,
    this.onChanged,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final density = context.layoutDensity;
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: density.listIconSize,
        ),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: density.searchFieldVerticalPadding,
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class PharmacyHubCategoryTile extends StatelessWidget {
  const PharmacyHubCategoryTile({
    super.key,
    required this.selectedCount,
    required this.onTap,
  });

  final int selectedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      title: const Text('Medicine categories'),
      subtitle: Text(
        selectedCount == 0 ? 'All categories' : '$selectedCount selected',
      ),
      trailing: const Icon(Icons.checklist_rounded),
      onTap: onTap,
    );
  }
}

class PharmacyHubCountRow extends StatelessWidget {
  const PharmacyHubCountRow({
    super.key,
    required this.label,
    this.trailing,
  });

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class PharmacyHubSortChip extends StatelessWidget {
  const PharmacyHubSortChip({
    super.key,
    required this.descending,
    required this.onTap,
  });

  final bool descending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Material(
      color: cs.primaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                descending ? Icons.south_rounded : Icons.north_rounded,
                size: 16,
                color: cs.primary,
              ),
              const SizedBox(width: 4),
              Text(
                descending ? 'Qty high' : 'Qty low',
                style: t.textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared filter header: search, optional category, count + optional trailing.
class PharmacyHubFilterSection extends StatelessWidget {
  const PharmacyHubFilterSection({
    super.key,
    required this.searchHint,
    this.searchController,
    required this.onSearchChanged,
    required this.countLabel,
    this.categorySelectedCount,
    this.onPickCategories,
    this.sortDescending,
    this.onToggleSort,
    this.countTrailing,
    this.beforeCount,
    this.afterSearch,
  });

  final String searchHint;
  final TextEditingController? searchController;
  final ValueChanged<String> onSearchChanged;
  final String countLabel;
  final int? categorySelectedCount;
  final VoidCallback? onPickCategories;
  final bool? sortDescending;
  final VoidCallback? onToggleSort;
  final Widget? countTrailing;
  final Widget? beforeCount;
  final Widget? afterSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: pharmacyHubFilterPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PharmacyHubSearchField(
            controller: searchController,
            hintText: searchHint,
            onChanged: onSearchChanged,
          ),
          if (afterSearch != null) ...[
            const SizedBox(height: 8),
            afterSearch!,
          ],
          if (onPickCategories != null && categorySelectedCount != null) ...[
            const SizedBox(height: 8),
            PharmacyHubCategoryTile(
              selectedCount: categorySelectedCount!,
              onTap: onPickCategories!,
            ),
          ],
          if (beforeCount != null) ...[
            const SizedBox(height: 8),
            beforeCount!,
          ],
          const SizedBox(height: 8),
          PharmacyHubCountRow(
            label: countLabel,
            trailing: countTrailing ??
                (sortDescending != null && onToggleSort != null
                    ? PharmacyHubSortChip(
                        descending: sortDescending!,
                        onTap: onToggleSort!,
                      )
                    : null),
          ),
        ],
      ),
    );
  }
}

class PharmacyHubListRow extends StatelessWidget {
  const PharmacyHubListRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.borderColor,
    this.trailing,
    this.onTap,
    this.subtitleMaxLines = 1,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final Color? borderColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final density = context.layoutDensity;
    final radius = density.listRowRadius;
    final border = borderColor ?? cs.outlineVariant.withValues(alpha: 0.45);
    final glyph = iconColor ?? cs.primary.withValues(alpha: 0.85);

    final row = Container(
      margin: EdgeInsets.only(bottom: density.listRowGap),
      padding: EdgeInsets.symmetric(
        horizontal: density.listCardPaddingH,
        vertical: density.listCardPaddingV,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: density.listIconSize, color: glyph),
          SizedBox(width: density.listIconGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: density.listTitleStyle(t.textTheme),
                ),
                SizedBox(height: density.listLineGap),
                Text(
                  subtitle,
                  maxLines: subtitleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: density.listSubtitleStyle(t.textTheme, cs),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(radius),
      child: onTap == null
          ? row
          : InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              child: row,
            ),
    );
  }
}

/// Category multi-select bottom sheet used by Medicines and Stock.
Future<Set<String>?> showPharmacyCategoryFilterSheet(
  BuildContext context, {
  required Set<String> selected,
  required List<Map<String, dynamic>> categories,
  String title = 'Medicine categories',
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final temp = Set<String>.from(selected);
      return StatefulBuilder(
        builder: (context, setModalState) {
          final maxH = MediaQuery.sizeOf(context).height * 0.55;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(title),
                  trailing: TextButton(
                    onPressed: () => setModalState(temp.clear),
                    child: const Text('Clear'),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in categories)
                        CheckboxListTile(
                          value: temp.contains(c['id']),
                          title: Text(c['name'] as String? ?? ''),
                          onChanged: (checked) {
                            setModalState(() {
                              final id = c['id'] as String?;
                              if (id == null) return;
                              if (checked == true) {
                                temp.add(id);
                              } else {
                                temp.remove(id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: pharmacyHubFilterPadding(context),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.pop(ctx, Set<String>.from(temp)),
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
