import 'package:flutter/material.dart';

import 'report_date_range.dart';
import 'report_ui.dart';

class ReportDateFilterBar extends StatelessWidget {
  const ReportDateFilterBar({
    super.key,
    required this.onOpenFilters,
    this.selected,
    this.onSelected,
    this.pharmacistMode = false,
    this.filterCount = 0,
    this.rangeLabel,
    this.showDatePresets = true,
  });

  final ReportDatePreset? selected;
  final ValueChanged<ReportDatePreset>? onSelected;
  final VoidCallback onOpenFilters;
  final bool pharmacistMode;
  final int filterCount;
  final String? rangeLabel;
  final bool showDatePresets;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final presets = pharmacistMode
        ? const [
            (ReportDatePreset.today, 'Today'),
            (ReportDatePreset.last7, '7 days'),
            (ReportDatePreset.last30, '30 days'),
          ]
        : const [
            (ReportDatePreset.today, 'Today'),
            (ReportDatePreset.last7, '7 days'),
            (ReportDatePreset.thisMonth, 'Month'),
            (ReportDatePreset.thisYear, 'Year'),
            (ReportDatePreset.lifetime, 'Lifetime'),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (showDatePresets)
              Expanded(
                child: _ScrollableDatePresets(
                  presets: presets,
                  selected: selected,
                  onSelected: onSelected,
                ),
              )
            else
              Expanded(
                child: Text(
                  'Filters',
                  style: t.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            _FilterIconButton(
              count: filterCount,
              onPressed: onOpenFilters,
            ),
          ],
        ),
        if (rangeLabel != null && rangeLabel!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            rangeLabel!,
            style: t.textTheme.bodySmall?.copyWith(
              color: ReportUi.mutedText(cs),
            ),
          ),
        ],
      ],
    );
  }
}

class _ScrollableDatePresets extends StatefulWidget {
  const _ScrollableDatePresets({
    required this.presets,
    this.selected,
    this.onSelected,
  });

  final List<(ReportDatePreset, String)> presets;
  final ReportDatePreset? selected;
  final ValueChanged<ReportDatePreset>? onSelected;

  @override
  State<_ScrollableDatePresets> createState() => _ScrollableDatePresetsState();
}

class _ScrollableDatePresetsState extends State<_ScrollableDatePresets> {
  final _controller = ScrollController();
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateScrollHints);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedChip();
      _updateScrollHints();
    });
  }

  @override
  void didUpdateWidget(covariant _ScrollableDatePresets oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelectedChip();
        _updateScrollHints();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateScrollHints);
    _controller.dispose();
    super.dispose();
  }

  void _scrollToSelectedChip() {
    if (!_controller.hasClients || widget.selected == null) return;
    final idx = widget.presets.indexWhere((e) => e.$1 == widget.selected);
    if (idx <= 0) return;
    const chipStride = 96.0;
    final target = (idx * chipStride).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.jumpTo(target);
  }

  void _updateScrollHints() {
    if (!_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    final offset = _controller.offset;
    final back = offset > 4;
    final forward = max > 4 && offset < max - 4;
    if (back != _canScrollBack || forward != _canScrollForward) {
      setState(() {
        _canScrollBack = back;
        _canScrollForward = forward;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + delta).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        if (_canScrollBack)
          _ScrollHintButton(
            icon: Icons.chevron_left_rounded,
            onPressed: () => _scrollBy(-120),
          ),
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (preset, label) in widget.presets) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ReportDateChip(
                          label: label,
                          selected: widget.selected == preset,
                          onTap: widget.onSelected == null
                              ? null
                              : () => widget.onSelected!(preset),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_canScrollForward)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            cs.surface.withValues(alpha: 0),
                            cs.surface.withValues(alpha: 0.92),
                          ],
                        ),
                      ),
                      child: const SizedBox(width: 28),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_canScrollForward)
          _ScrollHintButton(
            icon: Icons.chevron_right_rounded,
            onPressed: () => _scrollBy(120),
          ),
      ],
    );
  }
}

class _ScrollHintButton extends StatelessWidget {
  const _ScrollHintButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: ReportPalette.cardWhite,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: ReportUi.hairline(cs)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SizedBox(
            width: 28,
            height: 36,
            child: Icon(icon, size: 20, color: ReportPalette.forest),
          ),
        ),
      ),
    );
  }
}

class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = count > 0;
    return Material(
      color: active ? ReportPalette.cardWhite : ReportPalette.cardWhite,
      borderRadius: ReportUi.radiusMd,
      child: InkWell(
        borderRadius: ReportUi.radiusMd,
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: ReportUi.radiusMd,
            color: Colors.white,
            border: Border.all(
              color: active ? ReportPalette.green : ReportUi.hairline(cs),
              width: active ? 1.5 : 1,
            ),
          ),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: active ? cs.primary : ReportUi.mutedText(cs),
                ),
                if (count > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 15,
                      height: 15,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$count',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReportSearchField extends StatelessWidget {
  const ReportSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
    required this.resultCount,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: t.textTheme.bodyMedium?.copyWith(
                  color: ReportUi.mutedText(cs),
                ),
                isDense: true,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: ReportUi.mutedText(cs),
                ),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: ReportUi.mutedText(cs),
                        ),
                        onPressed: onClear,
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: ReportUi.radiusMd,
                  borderSide: BorderSide(color: ReportUi.hairline(cs)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: ReportUi.radiusMd,
                  borderSide: BorderSide(color: ReportUi.hairline(cs)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: ReportUi.radiusMd,
                  borderSide: BorderSide(
                    color: cs.primary.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: ReportUi.radiusMd,
              border: Border.all(color: ReportUi.hairline(cs)),
            ),
            child: Text(
              '$resultCount',
              style: t.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: ReportPalette.forest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
