import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/form_error_banner.dart';

bool _reportCellLooksLikeUuid(String s) {
  final t = s.trim();
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(t);
}

bool _reportColumnKeyIsId(String key) {
  final k = key.toLowerCase();
  return k == 'id' || k.endsWith('_id');
}

/// On-screen report tables only; CSV export still emits raw values.
String _reportTableCellDisplayText(String key, Object? value) {
  final raw = value ?? '';
  final s = '$raw'.trim();
  if (s.isEmpty) return '';
  if (_reportColumnKeyIsId(key) && _reportCellLooksLikeUuid(s)) {
    return '—';
  }
  return s;
}

enum _DatePreset { today, last7, last30, custom }

class ReportViewerPage extends ConsumerStatefulWidget {
  const ReportViewerPage({super.key, required this.reportType});

  final String reportType;

  @override
  ConsumerState<ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends ConsumerState<ReportViewerPage> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _filter = '';
  String? _sortKey;
  bool _sortAsc = true;
  late DateTime _from;
  late DateTime _to;
  late _DatePreset _datePreset;
  final TextEditingController _thresholdCtl = TextEditingController(text: '90');
  bool _autoRunScheduled = false;
  final TextEditingController _searchCtl = TextEditingController();

  bool get _isSalesRangeReport =>
      widget.reportType == 'sales_summary' ||
      widget.reportType == 'sales_by_staff' ||
      widget.reportType == 'profit_summary' ||
      widget.reportType == 'sales_trend_daily' ||
      widget.reportType == 'sales_trend_monthly' ||
      widget.reportType == 'sales_trend_yearly';

  String? get _trendGranularity {
    return switch (widget.reportType) {
      'sales_trend_daily' => 'day',
      'sales_trend_monthly' => 'month',
      'sales_trend_yearly' => 'year',
      _ => null,
    };
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _applyDatePreset(_DatePreset p) {
    final today = _dateOnly(DateTime.now());
    switch (p) {
      case _DatePreset.today:
        _from = today;
        _to = today;
      case _DatePreset.last7:
        _to = today;
        _from = today.subtract(const Duration(days: 6));
      case _DatePreset.last30:
        _to = today;
        _from = today.subtract(const Duration(days: 29));
      case _DatePreset.custom:
        break;
    }
    _datePreset = p;
  }

  @override
  void initState() {
    super.initState();
    if (_isSalesRangeReport) {
      _applyDatePreset(_DatePreset.today);
    } else {
      final today = _dateOnly(DateTime.now());
      _from = today;
      _to = today;
      _datePreset = _DatePreset.today;
    }
  }

  @override
  void dispose() {
    _thresholdCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  void _scheduleInitialLoad() {
    if (_autoRunScheduled) return;
    _autoRunScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _run();
    });
  }

  Future<void> _run() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch');
      return;
    }
    if (_isSalesRangeReport && _from.isAfter(_to)) {
      setState(() => _error = 'From date cannot be after To date.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final t = widget.reportType;
      if (t == 'sales_summary') {
        final data = await Supabase.instance.client.rpc(
          'rpc_report_sales_summary',
          params: {
            'p_team_id': teamId,
            'p_branch_id': branchId,
            'p_from': fmt.format(_from),
            'p_to': fmt.format(_to),
          },
        );
        _rows = List<Map<String, dynamic>>.from(data as List);
      } else if (t == 'sales_by_staff') {
        final data = await Supabase.instance.client.rpc(
          'rpc_report_sales_by_staff',
          params: {
            'p_team_id': teamId,
            'p_branch_id': branchId,
            'p_from': fmt.format(_from),
            'p_to': fmt.format(_to),
          },
        );
        _rows = List<Map<String, dynamic>>.from(data as List);
      } else if (t == 'profit_summary') {
        final data = await Supabase.instance.client.rpc(
          'rpc_report_profit_summary',
          params: {
            'p_team_id': teamId,
            'p_branch_id': branchId,
            'p_from': fmt.format(_from),
            'p_to': fmt.format(_to),
          },
        );
        _rows = List<Map<String, dynamic>>.from(data as List);
      } else if (_trendGranularity != null) {
        final data = await Supabase.instance.client.rpc(
          'rpc_report_sales_trend',
          params: {
            'p_team_id': teamId,
            'p_branch_id': branchId,
            'p_from': fmt.format(_from),
            'p_to': fmt.format(_to),
            'p_granularity': _trendGranularity,
          },
        );
        _rows = List<Map<String, dynamic>>.from(data as List);
      } else if (t == 'stock_balance') {
        final data = await Supabase.instance.client.rpc(
          'rpc_report_stock_balance',
          params: {
            'p_team_id': teamId,
            'p_branch_id': branchId,
          },
        );
        _rows = List<Map<String, dynamic>>.from(data as List);
      } else if (t == 'expiry_status') {
        final thresholdDays = int.tryParse(_thresholdCtl.text) ?? 90;
        final data = await Supabase.instance.client.rpc(
          'rpc_report_expiry_status',
          params: {
            'p_team_id': teamId,
            'p_branch_id': branchId,
            'p_threshold_days': thresholdDays,
          },
        );
        _rows = List<Map<String, dynamic>>.from(data as List);
      } else {
        _error = 'Unknown report type.';
      }
    } catch (e) {
      _error = userFacingError(e);
    } finally {
      if (mounted) {
        setState(() {
          if (_sortKey != null && _rows.isNotEmpty && !_rows.first.containsKey(_sortKey!)) {
            _sortKey = null;
          }
          _loading = false;
        });
      }
    }
  }

  Future<void> _exportCsv() async {
    if (_rows.isEmpty) return;
    final keys = _rows.first.keys.toList();
    final header = keys.join(',');
    final lines = _rows.map((row) => keys.map((k) => '${row[k] ?? ''}').join(',')).toList();
    await Clipboard.setData(ClipboardData(text: ([header, ...lines]).join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV copied to clipboard')),
      );
    }
  }

  List<Map<String, dynamic>> get _displayRows {
    var rows = List<Map<String, dynamic>>.from(_rows);
    if (_filter.trim().isNotEmpty) {
      final q = _filter.trim().toLowerCase();
      rows = rows
          .where((row) => row.values.any((v) => '$v'.toLowerCase().contains(q)))
          .toList();
    }
    if (_sortKey != null) {
      rows.sort((a, b) {
        final av = '${a[_sortKey] ?? ''}';
        final bv = '${b[_sortKey] ?? ''}';
        final cmp = av.compareTo(bv);
        return _sortAsc ? cmp : -cmp;
      });
    }
    return rows;
  }

  String _label(String key) {
    final words = key.split('_').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return key;
    return words.map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  String get _pageTitle => switch (widget.reportType) {
        'sales_summary' => 'Sales summary',
        'sales_by_staff' => 'Sales by staff',
        'stock_balance' => 'Stock balance',
        'expiry_status' => 'Expiry status',
        'profit_summary' => 'Profit summary',
        'sales_trend_daily' => 'Daily trend',
        'sales_trend_monthly' => 'Monthly trend',
        'sales_trend_yearly' => 'Yearly trend',
        _ => 'Report',
      };

  Future<void> _pickDate(bool isFrom) async {
    setState(() => _datePreset = _DatePreset.custom);
    final initial = isFrom ? _from : _to;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        if (isFrom) {
          _from = _dateOnly(d);
        } else {
          _to = _dateOnly(d);
        }
      });
    }
  }

  Future<void> _pickDateRangeQuick() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() {
        _datePreset = _DatePreset.custom;
        _from = _dateOnly(picked.start);
        _to = _dateOnly(picked.end);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleInitialLoad();

    final t = Theme.of(context);
    final cs = t.colorScheme;
    final keys = _rows.isNotEmpty ? _rows.first.keys.toList() : <String>[];
    final display = _displayRows;
    final hasData = _rows.isNotEmpty;
    final fmtShort = DateFormat.MMMd();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          _pageTitle,
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
        ),
        leading: const BackButton(),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _run,
            icon: _loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onSurfaceVariant,
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: cs.onSurface),
          ),
          IconButton(
            tooltip: 'Copy as CSV',
            onPressed: _rows.isEmpty ? null : _exportCsv,
            icon: Icon(Icons.copy_all_rounded, color: cs.onSurface),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: cs.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isSalesRangeReport) ...[
                    SegmentedButton<_DatePreset>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: _DatePreset.today,
                          label: Text('Today'),
                          icon: Icon(Icons.today_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: _DatePreset.last7,
                          label: Text('7d'),
                          icon: Icon(Icons.view_week_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: _DatePreset.last30,
                          label: Text('30d'),
                          icon: Icon(Icons.date_range_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: _DatePreset.custom,
                          label: Text('Custom'),
                          icon: Icon(Icons.edit_calendar_rounded, size: 16),
                        ),
                      ],
                      selected: {_datePreset},
                      onSelectionChanged: (next) {
                        setState(() => _applyDatePreset(next.first));
                      },
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                        foregroundColor: cs.onSurface,
                        selectedBackgroundColor: cs.primaryContainer,
                        selectedForegroundColor: cs.onPrimaryContainer,
                        side: BorderSide(color: cs.outline.withValues(alpha: 0.28)),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _pickDateRangeQuick,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_rounded, size: 22, color: cs.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Date range',
                                    style: t.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${fmtShort.format(_from)} → ${fmtShort.format(_to)}',
                                    style: t.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _pickDate(true),
                              child: const Text('From'),
                            ),
                            TextButton(
                              onPressed: () => _pickDate(false),
                              child: const Text('To'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (widget.reportType == 'expiry_status') ...[
                    TextField(
                      style: TextStyle(color: cs.onSurface, fontSize: 15),
                      decoration: InputDecoration(
                        labelText: 'Days ahead for expiry warning',
                        hintText: '90',
                        isDense: true,
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.28)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.primary, width: 1.5),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      controller: _thresholdCtl,
                    ),
                  ],
                  if (widget.reportType == 'stock_balance')
                    Text(
                      'Snapshot of this branch (no date filter).',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loading ? null : _run,
                    icon: _loading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onPrimary,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 22),
                    label: Text(_loading ? 'Loading…' : (hasData ? 'Apply filters' : 'Load data')),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FormErrorBanner(message: _error!),
            ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow.withValues(alpha: 0.85),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                child: _loading && !hasData
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: cs.primary),
                            const SizedBox(height: 16),
                            Text(
                              'Fetching rows…',
                              style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : display.isEmpty
                        ? _EmptyReportState(
                            hasRun: _rows.isNotEmpty,
                            message: _rows.isEmpty
                                ? 'Data loads automatically. Adjust filters above and tap Apply, or pull to refresh from the app bar.'
                                : 'No rows match your search. Clear the search box.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: SearchBar(
                                        controller: _searchCtl,
                                        hintText: 'Search in table…',
                                        leading: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                                        trailing: [
                                          if (_filter.isNotEmpty)
                                            IconButton(
                                              tooltip: 'Clear',
                                              icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                                              onPressed: () {
                                                _searchCtl.clear();
                                                setState(() => _filter = '');
                                              },
                                            ),
                                        ],
                                        onChanged: (v) => setState(() => _filter = v),
                                        elevation: WidgetStateProperty.all(0),
                                        backgroundColor: WidgetStateProperty.all(
                                          cs.surface.withValues(alpha: 0.95),
                                        ),
                                        side: WidgetStateProperty.all(
                                          BorderSide(color: cs.outline.withValues(alpha: 0.22)),
                                        ),
                                        shape: WidgetStateProperty.all(
                                          RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer.withValues(alpha: 0.65),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '${display.length}',
                                          style: t.textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: cs.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                                child: Row(
                                  children: [
                                    Icon(Icons.swap_vert_rounded, size: 18, color: cs.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Tap a column header to sort',
                                        style: t.textTheme.labelMedium?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Scrollbar(
                                  thumbVisibility: true,
                                  radius: const Radius.circular(8),
                                  child: _ReportDataTable(
                                    keys: keys,
                                    rows: display,
                                    sortColumnId: _sortKey,
                                    sortAscending: _sortAsc,
                                    labelForKey: _label,
                                    onSort: (key, asc) {
                                      setState(() {
                                        _sortKey = key;
                                        _sortAsc = asc;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyReportState extends StatelessWidget {
  const _EmptyReportState({required this.hasRun, required this.message});

  final bool hasRun;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasRun ? Icons.search_off_rounded : Icons.table_rows_rounded,
                size: 48,
                color: cs.primary.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 14),
              Text(
                hasRun ? 'No matches' : 'No rows yet',
                textAlign: TextAlign.center,
                style: t.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.76),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportDataTable extends StatelessWidget {
  const _ReportDataTable({
    required this.keys,
    required this.rows,
    required this.sortColumnId,
    required this.sortAscending,
    required this.labelForKey,
    required this.onSort,
  });

  final List<String> keys;
  final List<Map<String, dynamic>> rows;
  final String? sortColumnId;
  final bool sortAscending;
  final String Function(String) labelForKey;
  final void Function(String key, bool ascending) onSort;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final sortIndex = sortColumnId != null ? keys.indexOf(sortColumnId!) : null;
    final validIndex = sortIndex != null && sortIndex >= 0 ? sortIndex : null;

    return LayoutBuilder(
      builder: (context, c) {
        final minTableWidth = math.max(c.maxWidth - 24, keys.length * 100.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minTableWidth),
            child: Material(
              color: cs.surface.withValues(alpha: 0.98),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: cs.outline.withValues(alpha: 0.18)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: t.copyWith(
                  dataTableTheme: DataTableThemeData(
                    headingTextStyle: t.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      letterSpacing: 0.1,
                    ),
                    dataTextStyle: t.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      height: 1.3,
                    ),
                    dividerThickness: 0,
                  ),
                ),
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    cs.surfaceContainerHigh.withValues(alpha: 0.7),
                  ),
                  dataRowMinHeight: 46,
                  horizontalMargin: 14,
                  columnSpacing: 18,
                  sortColumnIndex: validIndex,
                  sortAscending: sortAscending,
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  columns: [
                    for (var i = 0; i < keys.length; i++)
                      DataColumn(
                        numeric: _columnLooksNumeric(rows, keys[i]),
                        label: Text(labelForKey(keys[i])),
                        onSort: (columnIndex, asc) => onSort(keys[columnIndex], asc),
                      ),
                  ],
                  rows: [
                    for (var i = 0; i < rows.length; i++)
                      DataRow(
                        color: WidgetStatePropertyAll(
                          i.isEven
                              ? null
                              : cs.surfaceContainerHighest.withValues(alpha: 0.22),
                        ),
                        cells: [
                          for (final k in keys)
                            DataCell(
                              SelectableText(
                                _reportTableCellDisplayText(k, rows[i][k]),
                                style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _columnLooksNumeric(List<Map<String, dynamic>> rows, String key) {
    var n = 0;
    for (final r in rows) {
      if (n >= 8) break;
      final v = r[key];
      if (v == null) continue;
      if (v is num) return true;
      if (num.tryParse(v.toString().trim()) != null) return true;
      n++;
    }
    return false;
  }
}
