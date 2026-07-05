import 'package:flutter/material.dart';

import '../../core/utils/date_formatters.dart';
import 'report_date_range.dart';
import 'report_ui.dart';

/// Bottom sheet for advanced report filters — drag to dismiss, explicit close.
class ReportFilterSheet extends StatefulWidget {
  const ReportFilterSheet({
    super.key,
    required this.dateRange,
    required this.isPharmacist,
    required this.sellerOptions,
    required this.categoryOptions,
    required this.initialSellerId,
    required this.initialPaymentMethod,
    required this.initialOverridesOnly,
    required this.initialCategoryKeys,
  });

  final ReportDateRange dateRange;
  final bool isPharmacist;
  final List<Map<String, String>> sellerOptions;
  final List<Map<String, String>> categoryOptions;
  final String? initialSellerId;
  final String? initialPaymentMethod;
  final bool initialOverridesOnly;
  final Set<String> initialCategoryKeys;

  static Future<ReportFilterSheetResult?> show(
    BuildContext context, {
    required ReportDateRange dateRange,
    required bool isPharmacist,
    required List<Map<String, String>> sellerOptions,
    required List<Map<String, String>> categoryOptions,
    required String? initialSellerId,
    required String? initialPaymentMethod,
    required bool initialOverridesOnly,
    required Set<String> initialCategoryKeys,
  }) {
    return showModalBottomSheet<ReportFilterSheetResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReportFilterSheet(
        dateRange: dateRange,
        isPharmacist: isPharmacist,
        sellerOptions: sellerOptions,
        categoryOptions: categoryOptions,
        initialSellerId: initialSellerId,
        initialPaymentMethod: initialPaymentMethod,
        initialOverridesOnly: initialOverridesOnly,
        initialCategoryKeys: initialCategoryKeys,
      ),
    );
  }

  @override
  State<ReportFilterSheet> createState() => _ReportFilterSheetState();
}

class ReportFilterSheetResult {
  const ReportFilterSheetResult({
    required this.apply,
    required this.dateRange,
    this.sellerId,
    this.paymentMethod,
    this.overridesOnly = false,
    this.categoryKeys = const {},
    this.clearAll = false,
  });

  final bool apply;
  final ReportDateRange dateRange;
  final String? sellerId;
  final String? paymentMethod;
  final bool overridesOnly;
  final Set<String> categoryKeys;
  final bool clearAll;
}

class _ReportFilterSheetState extends State<ReportFilterSheet> {
  late ReportDateRange _range;
  String? _sellerId;
  String? _paymentMethod;
  late bool _overridesOnly;
  late Set<String> _categoryKeys;

  @override
  void initState() {
    super.initState();
    _range = ReportDateRange(
      preset: widget.dateRange.preset,
      from: widget.dateRange.from,
      to: widget.dateRange.to,
    );
    _sellerId = widget.initialSellerId;
    _paymentMethod = widget.initialPaymentMethod;
    _overridesOnly = widget.initialOverridesOnly;
    _categoryKeys = Set<String>.from(widget.initialCategoryKeys);
  }

  void _close() => Navigator.pop(context);

  void _apply() {
    Navigator.pop(
      context,
      ReportFilterSheetResult(
        apply: true,
        dateRange: _range,
        sellerId: _sellerId,
        paymentMethod: _paymentMethod,
        overridesOnly: _overridesOnly,
        categoryKeys: Set<String>.from(_categoryKeys),
      ),
    );
  }

  void _clearAll() {
    Navigator.pop(
      context,
      ReportFilterSheetResult(
        apply: true,
        clearAll: true,
        dateRange: ReportDateRange.initial(
          preset: widget.isPharmacist
              ? ReportDatePreset.today
              : ReportDatePreset.thisMonth,
        ),
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _range.from, end: _range.to),
    );
    if (picked == null) return;
    setState(() {
      _range.preset = ReportDatePreset.custom;
      _range.from = ReportDateRange.dateOnly(picked.start);
      _range.to = ReportDateRange.dateOnly(picked.end);
    });
  }

  Future<void> _pickCategories() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final temp = Set<String>.from(_categoryKeys);
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return _SheetShell(
              title: 'Categories',
              onClose: () => Navigator.pop(ctx),
              scrollController: scrollController,
              bottomActions: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, temp),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  return Column(
                    children: [
                      for (final opt in widget.categoryOptions)
                        CheckboxListTile(
                          value: temp.contains(opt['id']),
                          title: Text(opt['name'] ?? ''),
                          onChanged: (v) {
                            setModalState(() {
                              if (v == true) {
                                temp.add(opt['id']!);
                              } else {
                                temp.remove(opt['id']);
                              }
                            });
                          },
                        ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
    if (selected == null) return;
    setState(() {
      _categoryKeys
        ..clear()
        ..addAll(selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return _SheetShell(
          title: 'Filters',
          onClose: _close,
          scrollController: scrollController,
          bottomActions: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _close,
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _apply,
                  style: FilledButton.styleFrom(
                    backgroundColor: ReportPalette.forest,
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FilterSection(
                title: 'Date range',
                child: Material(
                  color: Colors.white,
                  borderRadius: ReportUi.radiusMd,
                  child: InkWell(
                    borderRadius: ReportUi.radiusMd,
                    onTap: _pickCustomRange,
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: ReportUi.radiusMd,
                        border: Border.all(color: ReportUi.hairline(cs)),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.date_range_rounded,
                          color: ReportPalette.green,
                        ),
                        title: Text(
                          '${formatDdMmYyyy(_range.from)} – ${formatDdMmYyyy(_range.to)}',
                          style: t.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text('Pick custom dates'),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: ReportUi.mutedText(cs),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _FilterSection(
                title: 'Sales details',
                child: Column(
                  children: [
                    if (!widget.isPharmacist) ...[
                      _whiteField(
                        cs: cs,
                        child: DropdownButtonFormField<String>(
                          initialValue: _sellerId,
                          decoration: _fieldDecoration('Staff member'),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('All staff'),
                            ),
                            ...widget.sellerOptions.map(
                              (s) => DropdownMenuItem<String>(
                                value: s['id'],
                                child: Text(
                                  s['name'] ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _sellerId = v),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _whiteField(
                      cs: cs,
                      child: DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        decoration: _fieldDecoration('Payment method'),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem<String>(
                            value: null,
                            child: Text('All methods'),
                          ),
                          DropdownMenuItem(value: 'cash', child: Text('Cash')),
                          DropdownMenuItem(
                            value: 'mobile_banking',
                            child: Text('Mobile banking'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _paymentMethod = v),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: ReportUi.radiusMd,
                        border: Border.all(color: ReportUi.hairline(cs)),
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        title: const Text('Price overrides only'),
                        value: _overridesOnly,
                        activeThumbColor: ReportPalette.green,
                        onChanged: (v) => setState(() => _overridesOnly = v),
                      ),
                    ),
                    if (widget.categoryOptions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Material(
                        color: Colors.white,
                        borderRadius: ReportUi.radiusMd,
                        child: InkWell(
                          borderRadius: ReportUi.radiusMd,
                          onTap: _pickCategories,
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: ReportUi.radiusMd,
                              border: Border.all(color: ReportUi.hairline(cs)),
                            ),
                            child: ListTile(
                              leading: Icon(
                                Icons.category_outlined,
                                color: ReportPalette.blue,
                              ),
                              title: const Text('Medicine categories'),
                              subtitle: Text(
                                _categoryKeys.isEmpty
                                    ? 'All categories'
                                    : '${_categoryKeys.length} selected',
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: ReportUi.mutedText(cs),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _clearAll,
                child: const Text('Clear all filters'),
              ),
            ],
          ),
        );
      },
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: ReportUi.radiusMd),
      enabledBorder: OutlineInputBorder(
        borderRadius: ReportUi.radiusMd,
        borderSide: BorderSide(color: ReportUi.hairline(Theme.of(context).colorScheme)),
      ),
    );
  }

  Widget _whiteField({required ColorScheme cs, required Widget child}) {
    return child;
  }
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    required this.onClose,
    required this.scrollController,
    required this.child,
    required this.bottomActions,
  });

  final String title;
  final VoidCallback onClose;
  final ScrollController scrollController;
  final Widget child;
  final Widget bottomActions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ReportPalette.forest,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [child],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: ReportUi.hairline(cs))),
            ),
            child: bottomActions,
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: ReportPalette.forest,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}
