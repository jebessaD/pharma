import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/medicine/medicine_display.dart';
import '../../core/utils/date_formatters.dart';
import 'report_ui.dart';

const _moneyKeys = {
  'grand_total',
  'line_total',
  'net_line_total',
  'unit_price',
  'discount_total',
  'revenue',
  'cogs',
  'gross_profit',
  'total_sales',
};

const _preferredColumns = <String, List<String>>{
  'sales_unified': [
    'sold_at',
    'medicine_name',
    'qty',
    'unit_price',
    'line_total',
    'discount_total',
    'grand_total',
    'seller_name',
    'payment_method',
  ],
  'sales_summary': ['sold_at', 'grand_total'],
  'sales_by_staff': ['seller_name', 'sale_count', 'total_sales'],
  'stock_balance': ['medicine_name', 'batch_no', 'qty', 'expiry_date'],
  'expiry_status': ['medicine_name', 'batch_no', 'expiry_date', 'days_left'],
  'profit_summary': ['revenue', 'cogs', 'gross_profit', 'sale_count'],
  'sales_trend': ['period_label', 'sale_count', 'revenue', 'gross_profit'],
  'sales_trend_daily': ['period_label', 'sale_count', 'revenue', 'gross_profit'],
  'sales_trend_monthly': ['period_label', 'sale_count', 'revenue', 'gross_profit'],
  'sales_trend_yearly': ['period_label', 'sale_count', 'revenue', 'gross_profit'],
};

String friendlyReportLabel(String key) {
  return switch (key) {
    'sold_at' => 'Date',
    'medicine_name' => 'Medicine',
    'qty' => 'Qty',
    'grand_total' => 'Total',
    'seller_name' => 'Staff',
    'payment_method' => 'Payment',
    'unit_price' => 'Unit price',
    'line_total' => 'Subtotal',
    'net_line_total' => 'Sold',
    'discount_total' => 'Discount',
    'revenue' => 'Gain',
    'cogs' => 'Spent',
    'gross_profit' => 'Profit',
    'sale_count' => 'Sales',
    'total_sales' => 'Total',
    'batch_no' => 'Batch',
    'expiry_date' => 'Expiry',
    'days_left' => 'Days left',
    'period_label' => 'Period',
    _ => key
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' '),
  };
}

String formatReportCell(String key, Object? value) {
  final raw = value ?? '';
  final s = '$raw'.trim();
  if (s.isEmpty) return '';
  final k = key.toLowerCase();
  if (k.contains('date') || k.endsWith('_at')) {
    return formatDdMmYyyy(value);
  }
  if (value is num && _moneyKeys.contains(k)) {
    return '${NumberFormat('#,##0.00').format(value)} ETB';
  }
  if (value is num && k == 'qty') {
    return NumberFormat('#,##0.##').format(value);
  }
  if (value is num && (k == 'sale_count' || k == 'days_left')) {
    return NumberFormat.decimalPattern().format(value);
  }
  if (value is num && k == 'gross_margin_pct') {
    return '${NumberFormat('#,##0.##').format(value)}%';
  }
  return s;
}

List<String> visibleReportKeys(String reportType, Iterable<String> allKeys) {
  final available = allKeys.where((k) => k != 'sale_id').toSet();
  final preferred = _preferredColumns[reportType];
  if (preferred == null) return available.toList();
  return preferred.where(available.contains).toList();
}

String? _trailingAmountKey(String reportType) {
  return switch (reportType) {
    'sales_unified' || 'sales_summary' => 'grand_total',
    'sales_by_staff' => 'total_sales',
    'sales_trend' ||
    'sales_trend_daily' ||
    'sales_trend_monthly' ||
    'sales_trend_yearly' =>
      'revenue',
    _ => null,
  };
}

String? _titleKey(String reportType) {
  return switch (reportType) {
    'sales_unified' => 'medicine_name',
    'sales_summary' => 'sold_at',
    'sales_by_staff' => 'seller_name',
    'stock_balance' || 'expiry_status' => 'medicine_name',
    'sales_trend' ||
    'sales_trend_daily' ||
    'sales_trend_monthly' ||
    'sales_trend_yearly' =>
      'period_label',
    _ => null,
  };
}

class ProfitSummaryCard extends StatelessWidget {
  const ProfitSummaryCard({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [ProfitSummaryGrid(row: row)],
    );
  }
}

class ProfitSummaryGrid extends StatelessWidget {
  const ProfitSummaryGrid({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    Widget stat(
      String label,
      String value,
      IconData icon,
      Color iconColor,
    ) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: ReportUi.surfaceCard(cs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: ReportUi.iconWellBorder(cs),
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: t.textTheme.labelMedium?.copyWith(
                        color: ReportUi.mutedText(cs),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value.isEmpty ? '—' : value,
                    style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.25,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            stat(
              'Gain',
              formatReportCell('revenue', row['revenue']),
              Icons.trending_up_rounded,
              cs.primary,
            ),
            const SizedBox(width: 10),
            stat(
              'Spent',
              formatReportCell('cogs', row['cogs']),
              Icons.payments_outlined,
              ReportPalette.alert(cs),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            stat(
              'Profit',
              formatReportCell('gross_profit', row['gross_profit']),
              Icons.savings_outlined,
              cs.primary,
            ),
            const SizedBox(width: 10),
            stat(
              'Sales',
              formatReportCell('sale_count', row['sale_count']),
              Icons.receipt_long_outlined,
              ReportPalette.blue(cs),
            ),
          ],
        ),
      ],
    );
  }
}

const kReportSalesCardsLimit = 20;
const kReportSalesTablePageSize = 100;

num reportNetLineSold(Map<String, dynamic> row) {
  final net = row['net_line_total'];
  if (net is num) return net;
  final line = (row['line_total'] as num?) ?? 0;
  final alloc = (row['discount_alloc'] as num?) ?? 0;
  if (alloc > 0) return line - alloc;
  final discount = (row['discount_total'] as num?) ?? 0;
  final grand = (row['grand_total'] as num?) ?? 0;
  if (discount > 0 && grand > 0 && grand < line) return grand;
  return line;
}

Map<String, dynamic>? unifiedSummaryRowFromStats(Map<String, dynamic>? stats) {
  if (stats == null) return null;
  return {
    'sold_at': null,
    'sale_id': null,
    'seller_name': '',
    'medicine_name': 'TOTAL',
    'medicine_code': '',
    'qty': stats['qty_sum'],
    'unit_price': null,
    'line_total': stats['line_total_sum'],
    'discount_total': stats['discount_total_sum'],
    'grand_total': stats['grand_total_sum'],
    'payment_method': '',
    'payment_reference': '',
    'override_reason': '',
  };
}

List<Map<String, dynamic>> appendUnifiedSummaryRow(
  List<Map<String, dynamic>> rows,
) {
  if (rows.isEmpty) return rows;
  num qtySum = 0;
  num lineSum = 0;
  num discountSum = 0;
  num grandSum = 0;
  final seenSaleIds = <String>{};
  for (final r in rows) {
    qtySum += (r['qty'] as num?) ?? 0;
    lineSum += (r['line_total'] as num?) ?? 0;
    final saleId = '${r['sale_id'] ?? ''}';
    if (saleId.isNotEmpty && seenSaleIds.add(saleId)) {
      discountSum += (r['discount_total'] as num?) ?? 0;
      grandSum += (r['grand_total'] as num?) ?? 0;
    }
  }
  return [
    ...rows,
    {
      'sold_at': null,
      'sale_id': null,
      'seller_name': '',
      'medicine_name': 'TOTAL',
      'medicine_code': '',
      'qty': qtySum,
      'unit_price': null,
      'line_total': lineSum,
      'discount_total': discountSum,
      'grand_total': grandSum,
      'payment_method': '',
      'payment_reference': '',
      'override_reason': '',
    },
  ];
}

List<Map<String, dynamic>> filterReportRows(
  List<Map<String, dynamic>> rows,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return rows
      .where((row) => row.values.any((v) => '$v'.toLowerCase().contains(q)))
      .toList();
}

class ReportDataTable extends StatefulWidget {
  const ReportDataTable({
    super.key,
    required this.reportType,
    required this.keys,
    required this.rows,
  });

  final String reportType;
  final List<String> keys;
  final List<Map<String, dynamic>> rows;

  @override
  State<ReportDataTable> createState() => _ReportDataTableState();
}

class _ReportDataTableState extends State<ReportDataTable> {
  int? _sortColumnIndex;
  bool _sortAscending = true;

  void _onSort(int columnIndex, String key) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _sortAscending = true;
      }
    });
  }

  List<Map<String, dynamic>> get _sortedRows {
    if (_sortColumnIndex == null) return widget.rows;
    final key = widget.keys[_sortColumnIndex!];
    final sorted = List<Map<String, dynamic>>.from(widget.rows);
    sorted.sort((a, b) {
      final av = a[key];
      final bv = b[key];
      int cmp;
      if (av is num && bv is num) {
        cmp = av.compareTo(bv);
      } else {
        cmp = '$av'.compareTo('$bv');
      }
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final sorted = _sortedRows;

    if (widget.keys.isEmpty || sorted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: ReportUi.surfaceCard(cs),
          child: Text(
            'No rows to show.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium?.copyWith(
              color: ReportUi.mutedText(cs),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Container(
        decoration: ReportUi.surfaceCard(cs),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 56,
            headingRowColor: WidgetStatePropertyAll(
              cs.surfaceContainerHighest.withValues(alpha: 0.25),
            ),
            columnSpacing: 24,
            horizontalMargin: 16,
            dividerThickness: 0.6,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            columns: [
              for (var i = 0; i < widget.keys.length; i++)
                DataColumn(
                  label: Text(
                    friendlyReportLabel(widget.keys[i]),
                    style: t.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ReportUi.mutedText(cs),
                    ),
                  ),
                  onSort: (columnIndex, _) =>
                      _onSort(columnIndex, widget.keys[columnIndex]),
                ),
            ],
            rows: [
              for (final row in sorted)
                DataRow(
                  cells: [
                    for (final key in widget.keys)
                      DataCell(
                        Text(
                          formatReportCell(key, row[key]),
                          style: t.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                '${row['medicine_name'] ?? ''}'.trim().toUpperCase() ==
                                        'TOTAL' &&
                                    widget.reportType == 'sales_unified'
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
class ReportSimpleList extends StatelessWidget {
  const ReportSimpleList({
    super.key,
    required this.reportType,
    required this.keys,
    required this.rows,
  });

  final String reportType;
  final List<String> keys;
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return ReportRowCard(
          reportType: reportType,
          keys: keys,
          row: rows[index],
        );
      },
    );
  }
}

class ReportRowCard extends StatelessWidget {
  const ReportRowCard({
    super.key,
    required this.reportType,
    required this.keys,
    required this.row,
    this.compact = false,
  });

  final String reportType;
  final List<String> keys;
  final Map<String, dynamic> row;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isTotal =
        reportType == 'sales_unified' &&
        '${row['medicine_name'] ?? ''}'.trim().toUpperCase() == 'TOTAL';

    if (compact && reportType == 'sales_unified' && !isTotal) {
      return _SalesLineCard(
        row: row,
        theme: t,
        colorScheme: cs,
        showStaff: keys.contains('seller_name'),
      );
    }

    final titleKey = _titleKey(reportType) ?? keys.first;
    final amountKey = _trailingAmountKey(reportType);
    final title = isTotal ? 'Total' : formatReportCell(titleKey, row[titleKey]);
    final amount = amountKey == null
        ? null
        : formatReportCell(amountKey, row[amountKey]);

    final meta = <String>[];
    for (final key in keys) {
      if (key == titleKey || key == amountKey) continue;
      final text = formatReportCell(key, row[key]);
      if (text.isEmpty) continue;
      meta.add('${friendlyReportLabel(key)} · $text');
    }

    final rank = row['_rank'] as int?;
    final showRank =
        !compact &&
        rank != null &&
        reportType == 'sales_unified' &&
        !isTotal;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: ReportUi.radiusLg,
        border: Border.all(
          color: isTotal
              ? cs.primary.withValues(alpha: 0.35)
              : ReportUi.hairline(cs),
          width: isTotal ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showRank) ...[
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: rank == 1 ? cs.primary : ReportUi.hairline(cs),
                        width: rank == 1 ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      '$rank',
                      style: t.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: rank == 1 ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    title.isEmpty ? '—' : title,
                    style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (amount != null && amount.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Text(
                    amount,
                    style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isTotal || reportType == 'sales_by_staff'
                          ? cs.primary
                          : cs.onSurface,
                    ),
                  ),
                ],
              ],
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                meta.join('  ·  '),
                style: t.textTheme.bodySmall?.copyWith(
                  color: ReportUi.mutedText(cs),
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SalesLineCard extends StatelessWidget {
  const _SalesLineCard({
    required this.row,
    required this.theme,
    required this.colorScheme,
    this.showStaff = false,
  });

  final Map<String, dynamic> row;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final bool showStaff;

  static String _paymentLabel(Object? method) {
    final m = '$method'.trim().toLowerCase();
    return switch (m) {
      'cash' => 'Cash',
      'mobile_banking' => 'Mobile',
      _ => m.isEmpty ? '' : m,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final cs = colorScheme;
    final combined = formatReportCell('medicine_name', row['medicine_name']);
    final (title, brand) = splitMedicineDisplayLabel(combined);
    final soldAmount = formatReportCell(
      'net_line_total',
      reportNetLineSold(row),
    );
    final qty = formatReportCell('qty', row['qty']);
    final unitPrice = formatReportCell('unit_price', row['unit_price']);
    final date = formatReportCell('sold_at', row['sold_at']);
    final payment = _paymentLabel(row['payment_method']);
    final seller = (row['seller_name'] as String? ?? '').trim();

    final detailParts = <String>[
      if (qty.isNotEmpty && unitPrice.isNotEmpty) '$qty × $unitPrice',
      if (date.isNotEmpty) date,
      if (payment.isNotEmpty) payment,
      if (showStaff && seller.isNotEmpty) seller,
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: ReportUi.radiusMd,
        border: Border.all(color: ReportUi.hairline(cs)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? '—' : title,
                        style: t.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (brand != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          brand,
                          style: t.textTheme.labelSmall?.copyWith(
                            color: ReportUi.mutedText(cs),
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (soldAmount.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topRight,
                        child: Text(
                          soldAmount,
                          style: t.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (detailParts.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                detailParts.join(' · '),
                style: t.textTheme.labelSmall?.copyWith(
                  color: ReportUi.mutedText(cs),
                  height: 1.25,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
