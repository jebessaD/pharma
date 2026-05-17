import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/utils/csv_export.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/utils/date_formatters.dart';
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
  final k = key.toLowerCase();
  if (k.contains('date') || k.endsWith('_at')) {
    return formatDdMmYyyy(value);
  }
  return s;
}

enum _DatePreset { today, last7, last30, thisYear, custom }

enum _TrendPreset { day, month, year }

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
  Timer? _autoRunDebounce;
  late _TrendPreset _trendPreset;
  final TextEditingController _minAmountCtl = TextEditingController();
  final TextEditingController _maxAmountCtl = TextEditingController();
  String? _selectedSellerId;
  String? _selectedPaymentMethod;
  final Set<String> _selectedCategoryKeys = <String>{};
  bool _overridesOnly = false;
  bool _filtersExpanded = false;
  List<Map<String, String>> _sellerOptions = const [];

  bool get _isUnifiedSalesReport => widget.reportType == 'sales_unified';

  /// Pharmacists: sales tables only — Today / 7d / 30d (no annual or custom).
  bool get _narrowPharmacistSalesDates {
    final role =
        (ref.watch(pharmacyProfileProvider).asData?.value?['role'] as String? ??
                '')
            .trim()
            .toLowerCase();
    if (role != 'pharmacist') return false;
    return widget.reportType == 'sales_unified' ||
        widget.reportType == 'sales_summary' ||
        widget.reportType == 'sales_by_staff';
  }

  bool get _isPharmacist {
    final role =
        (ref.watch(pharmacyProfileProvider).asData?.value?['role'] as String? ??
                '')
            .trim()
            .toLowerCase();
    return role == 'pharmacist';
  }

  bool get _pharmacistProfitBlocked =>
      _isPharmacist && widget.reportType == 'profit_summary';

  bool _readIsPharmacist() {
    final role =
        (ref.read(pharmacyProfileProvider).asData?.value?['role'] as String? ??
                '')
            .trim()
            .toLowerCase();
    return role == 'pharmacist';
  }

  String? get _effectiveSoldByForRpc {
    if (!_isPharmacist) return _selectedSellerId;
    if (widget.reportType == 'sales_unified' ||
        widget.reportType == 'sales_summary') {
      return Supabase.instance.client.auth.currentUser?.id;
    }
    return _selectedSellerId;
  }

  bool get _supportsCategoryFilter =>
      widget.reportType == 'sales_unified' ||
      widget.reportType == 'stock_balance' ||
      widget.reportType == 'expiry_status';

  bool get _isSalesRangeReport =>
      widget.reportType == 'sales_unified' ||
      widget.reportType == 'sales_summary' ||
      widget.reportType == 'sales_by_staff' ||
      widget.reportType == 'profit_summary' ||
      widget.reportType == 'sales_trend' ||
      widget.reportType == 'sales_trend_daily' ||
      widget.reportType == 'sales_trend_monthly' ||
      widget.reportType == 'sales_trend_yearly';

  String? get _trendGranularity {
    if (widget.reportType == 'sales_trend') {
      return switch (_trendPreset) {
        _TrendPreset.day => 'day',
        _TrendPreset.month => 'month',
        _TrendPreset.year => 'year',
      };
    }
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
      case _DatePreset.thisYear:
        _to = today;
        _from = DateTime(today.year, 1, 1);
      case _DatePreset.custom:
        break;
    }
    _datePreset = p;
  }

  @override
  void initState() {
    super.initState();
    _trendPreset = _TrendPreset.day;
    if (_isSalesRangeReport) {
      _applyDatePreset(_DatePreset.today);
    } else {
      final today = _dateOnly(DateTime.now());
      _from = today;
      _to = today;
      _datePreset = _DatePreset.today;
    }
  }

  bool _pharmacistNarrowSalesDatePresets() {
    final role =
        (ref.read(pharmacyProfileProvider).asData?.value?['role'] as String? ??
                '')
            .trim()
            .toLowerCase();
    if (role != 'pharmacist') return false;
    return widget.reportType == 'sales_unified' ||
        widget.reportType == 'sales_summary' ||
        widget.reportType == 'sales_by_staff';
  }

  static List<Map<String, dynamic>> _unifiedRowsToSalesSummary(
    List<Map<String, dynamic>> unified,
  ) {
    final bySale = <String, Map<String, dynamic>>{};
    for (final r in unified) {
      final id = '${r['sale_id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      bySale[id] = {
        'sale_id': r['sale_id'],
        'sold_at': r['sold_at'],
        'grand_total': r['grand_total'],
      };
    }
    final out = bySale.values.toList();
    out.sort((a, b) {
      final ta = a['sold_at'];
      final tb = b['sold_at'];
      if (ta is String && tb is String) return tb.compareTo(ta);
      return 0;
    });
    return out;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pharmacistNarrowSalesDatePresets()) return;
    if (_datePreset == _DatePreset.thisYear || _datePreset == _DatePreset.custom) {
      _applyDatePreset(_DatePreset.today);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runSoon();
      });
    }
  }

  @override
  void dispose() {
    _autoRunDebounce?.cancel();
    _thresholdCtl.dispose();
    _searchCtl.dispose();
    _minAmountCtl.dispose();
    _maxAmountCtl.dispose();
    super.dispose();
  }

  void _runSoon([Duration delay = const Duration(milliseconds: 250)]) {
    _autoRunDebounce?.cancel();
    _autoRunDebounce = Timer(delay, () {
      if (!mounted || _loading) return;
      _run();
    });
  }

  void _scheduleInitialLoad() {
    if (_autoRunScheduled) return;
    _autoRunScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _run();
    });
  }

  Future<void> _ensureSellerOptions(String teamId) async {
    if (!_isUnifiedSalesReport) return;
    if (_sellerOptions.isNotEmpty) return;
    final rows = await Supabase.instance.client
        .from('profiles')
        .select('id, full_name, username')
        .eq('team_id', teamId)
        .eq('is_active', true)
        .order('full_name');
    final options = <Map<String, String>>[];
    for (final raw in rows as List) {
      final p = Map<String, dynamic>.from(raw as Map);
      final id = (p['id'] as String? ?? '').trim();
      if (id.isEmpty) continue;
      final fullName = (p['full_name'] as String? ?? '').trim();
      final username = (p['username'] as String? ?? '').trim();
      final name = fullName.isNotEmpty
          ? fullName
          : (username.isNotEmpty ? username : 'Team member');
      options.add({'id': id, 'name': name});
    }
    _sellerOptions = options;
    if (_selectedSellerId != null &&
        !_sellerOptions.any((e) => e['id'] == _selectedSellerId)) {
      _selectedSellerId = null;
    }
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
      await _ensureSellerOptions(teamId);
      final minAmount = num.tryParse(_minAmountCtl.text.trim());
      final maxAmount = num.tryParse(_maxAmountCtl.text.trim());
      if (_isUnifiedSalesReport) {
        if (minAmount != null && minAmount < 0) {
          setState(() => _error = 'Min amount cannot be negative.');
          return;
        }
        if (maxAmount != null && maxAmount < 0) {
          setState(() => _error = 'Max amount cannot be negative.');
          return;
        }
        if (minAmount != null && maxAmount != null && minAmount > maxAmount) {
          setState(() => _error = 'Min amount cannot exceed max amount.');
          return;
        }
      }
      final fmt = DateFormat('yyyy-MM-dd');
      final t = widget.reportType;
      if (t == 'sales_unified') {
        final data = await _rpcWithOptionalCategory(
          'rpc_report_sales_unified',
          {
            'p_team_id': teamId,
            'p_branch_id': branchId,
            'p_from': fmt.format(_from),
            'p_to': fmt.format(_to),
            'p_sold_by': _effectiveSoldByForRpc,
            'p_min_amount': minAmount,
            'p_max_amount': maxAmount,
            'p_payment_method': _selectedPaymentMethod,
            'p_overrides_only': _overridesOnly,
            'p_category_keys': _selectedCategoryKeys.isEmpty
                ? null
                : _selectedCategoryKeys.toList(growable: false),
          },
        );
        _rows = List<Map<String, dynamic>>.from(data as List);
      } else if (t == 'sales_summary') {
        if (_readIsPharmacist()) {
          final uid = Supabase.instance.client.auth.currentUser?.id;
          if (uid == null) {
            _rows = [];
          } else {
            final data = await _rpcWithOptionalCategory(
              'rpc_report_sales_unified',
              {
                'p_team_id': teamId,
                'p_branch_id': branchId,
                'p_from': fmt.format(_from),
                'p_to': fmt.format(_to),
                'p_sold_by': uid,
                'p_min_amount': null,
                'p_max_amount': null,
                'p_payment_method': null,
                'p_overrides_only': false,
                'p_category_keys': _selectedCategoryKeys.isEmpty
                    ? null
                    : _selectedCategoryKeys.toList(growable: false),
              },
            );
            final raw =
                List<Map<String, dynamic>>.from(data as List? ?? const []);
            _rows = _unifiedRowsToSalesSummary(raw);
          }
        } else {
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
        }
      } else if (t == 'sales_by_staff') {
        if (_readIsPharmacist()) {
          final uid = Supabase.instance.client.auth.currentUser?.id;
          if (uid == null) {
            _rows = [];
          } else {
            final data = await _rpcWithOptionalCategory(
              'rpc_report_sales_unified',
              {
                'p_team_id': teamId,
                'p_branch_id': branchId,
                'p_from': fmt.format(_from),
                'p_to': fmt.format(_to),
                'p_sold_by': uid,
                'p_min_amount': null,
                'p_max_amount': null,
                'p_payment_method': null,
                'p_overrides_only': false,
                'p_category_keys': _selectedCategoryKeys.isEmpty
                    ? null
                    : _selectedCategoryKeys.toList(growable: false),
              },
            );
            final raw =
                List<Map<String, dynamic>>.from(data as List? ?? const []);
            final seen = <String>{};
            num total = 0;
            for (final r in raw) {
              final sid = '${r['sale_id'] ?? ''}'.trim();
              if (sid.isEmpty || !seen.add(sid)) continue;
              total += (r['grand_total'] as num?) ?? 0;
            }
            _rows = [
              {
                'seller_name': 'My sales',
                'sale_count': seen.length,
                'total_sales': total,
              },
            ];
          }
        } else {
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
        }
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
        final data = await _rpcWithOptionalCategory('rpc_report_stock_balance', {
          'p_team_id': teamId,
          'p_branch_id': branchId,
          'p_category_keys': _selectedCategoryKeys.isEmpty
              ? null
              : _selectedCategoryKeys.toList(growable: false),
        });
        _rows = List<Map<String, dynamic>>.from(data as List);
      } else if (t == 'expiry_status') {
        final thresholdDays = int.tryParse(_thresholdCtl.text) ?? 90;
        final data = await _rpcWithOptionalCategory('rpc_report_expiry_status', {
          'p_team_id': teamId,
          'p_branch_id': branchId,
          'p_threshold_days': thresholdDays,
          'p_category_keys': _selectedCategoryKeys.isEmpty
              ? null
              : _selectedCategoryKeys.toList(growable: false),
        });
        _rows = List<Map<String, dynamic>>.from(data as List);
      } else {
        _error = 'Unknown report type.';
      }
    } catch (e) {
      _error = userFacingError(e);
    } finally {
      if (mounted) {
        setState(() {
          if (_sortKey != null &&
              _rows.isNotEmpty &&
              !_rows.first.containsKey(_sortKey!)) {
            _sortKey = null;
          }
          _loading = false;
        });
      }
    }
  }

  Future<dynamic> _rpcWithOptionalCategory(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    return Supabase.instance.client.rpc(functionName, params: params);
  }

  Future<void> _exportCsv() async {
    if (_rows.isEmpty) return;
    final keys = _rows.first.keys.where((k) => k != 'sale_id').toList();
    final header = keys.map(csvEscapeField).join(',');
    final lines = _rows
        .map((row) => keys.map((k) => csvEscapeField(row[k])).join(','))
        .toList();
    final text = [header, ...lines].join('\n');
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV copied to clipboard')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not copy CSV to clipboard.')),
        );
      }
    }
  }

  List<Map<String, dynamic>> _appendUnifiedSummaryRow(
    List<Map<String, dynamic>> rows,
  ) {
    if (!_isUnifiedSalesReport || rows.isEmpty) return rows;
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
    return _appendUnifiedSummaryRow(rows);
  }

  String _label(String key) {
    final words = key.split('_').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return key;
    return words.map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  String get _pageTitle => switch (widget.reportType) {
    'sales_unified' => 'Sales report',
    'sales_summary' => 'Sales summary',
    'sales_by_staff' => 'Sales by staff',
    'stock_balance' => 'Stock balance',
    'expiry_status' => 'Expiry status',
    'profit_summary' => 'Profit summary',
    'sales_trend' => 'Sales trend',
    'sales_trend_daily' => 'Daily trend',
    'sales_trend_monthly' => 'Monthly trend',
    'sales_trend_yearly' => 'Yearly trend',
    _ => 'Report',
  };

  Widget _reportSearchBarRow(ThemeData t, ColorScheme cs, int displayCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SearchBar(
              controller: _searchCtl,
              hintText: 'Search in table…',
              leading: Icon(
                Icons.search_rounded,
                color: cs.onSurfaceVariant,
              ),
              trailing: [
                if (_filter.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    icon: Icon(
                      Icons.close_rounded,
                      color: cs.onSurfaceVariant,
                    ),
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
                BorderSide(
                  color: cs.outline.withValues(
                    alpha: 0.22,
                  ),
                ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(
                  alpha: 0.65,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$displayCount',
                style: t.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
      _runSoon();
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
      _runSoon();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pharmacistProfitBlocked) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                context.pop();
              } else {
                context.go('/pharmacy/reports');
              }
            },
          ),
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: const Text('Profit summary'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('This report is not available for your role.'),
          ),
        ),
      );
    }

    _scheduleInitialLoad();

    final t = Theme.of(context);
    final cs = t.colorScheme;
    final keys = _rows.isNotEmpty
        ? _rows.first.keys.where((k) => k != 'sale_id').toList()
        : <String>[];
    final display = _displayRows;
    final hasData = _rows.isNotEmpty;
    final filterTrim = _filter.trim();
    final showInitialTableEmpty =
        display.isEmpty && !hasData && filterTrim.isEmpty;
    final showEmptyTableWithSearch =
        display.isEmpty && (hasData || filterTrim.isNotEmpty);
    final categoriesAsync = ref.watch(activeBranchMedicineCategoriesProvider);
    final categoryOptions =
        categoriesAsync.value
            ?.map((row) {
              final id = (row['id'] as String? ?? '').trim();
              final name = (row['name'] as String? ?? '').trim();
              if (id.isEmpty || name.isEmpty) return null;
              return {'id': id, 'name': name};
            })
            .whereType<Map<String, String>>()
            .toList() ??
        const <Map<String, String>>[];

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          _pageTitle,
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/pharmacy/reports');
            }
          },
        ),
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
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isSalesRangeReport) ...[
                    if (widget.reportType == 'sales_trend') ...[
                      SegmentedButton<_TrendPreset>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: _TrendPreset.day,
                            label: Text('Day'),
                          ),
                          ButtonSegment(
                            value: _TrendPreset.month,
                            label: Text('Month'),
                          ),
                          ButtonSegment(
                            value: _TrendPreset.year,
                            label: Text('Year'),
                          ),
                        ],
                        selected: {_trendPreset},
                        onSelectionChanged: (next) {
                          setState(() => _trendPreset = next.first);
                          _runSoon();
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    SegmentedButton<_DatePreset>(
                      showSelectedIcon: false,
                      segments: [
                        const ButtonSegment(
                          value: _DatePreset.today,
                          label: Text('Today'),
                          icon: Icon(Icons.today_rounded, size: 16),
                        ),
                        const ButtonSegment(
                          value: _DatePreset.last7,
                          label: Text('7d'),
                          icon: Icon(Icons.view_week_rounded, size: 16),
                        ),
                        const ButtonSegment(
                          value: _DatePreset.last30,
                          label: Text('30d'),
                          icon: Icon(Icons.date_range_rounded, size: 16),
                        ),
                        if (!_narrowPharmacistSalesDates) ...[
                          const ButtonSegment(
                            value: _DatePreset.thisYear,
                            label: Text('Annual'),
                            icon: Icon(Icons.calendar_today_rounded, size: 16),
                          ),
                          const ButtonSegment(
                            value: _DatePreset.custom,
                            label: Text('Custom'),
                            icon: Icon(Icons.edit_calendar_rounded, size: 16),
                          ),
                        ],
                      ],
                      selected: {_datePreset},
                      onSelectionChanged: (next) {
                        setState(() => _applyDatePreset(next.first));
                        _runSoon();
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  Theme(
                    data: t.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      maintainState: true,
                      initiallyExpanded: _filtersExpanded,
                      onExpansionChanged: (v) =>
                          setState(() => _filtersExpanded = v),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      title: const Text('More filters'),
                      subtitle: Text(
                        _isUnifiedSalesReport
                            ? 'Staff, payment, amount, overrides'
                            : 'Extra report options',
                        style: t.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      children: [
                        if (_isSalesRangeReport && !_narrowPharmacistSalesDates)
                          InkWell(
                            onTap: _pickDateRangeQuick,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(
                                  alpha: 0.35,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: cs.outline.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    size: 22,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${formatDdMmYyyy(_from)} → ${formatDdMmYyyy(_to)}',
                                      style: t.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface,
                                      ),
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
                        if (_isUnifiedSalesReport) ...[
                          const SizedBox(height: 10),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              const spacing = 10.0;
                              final fieldWidth =
                                  (constraints.maxWidth - spacing) / 2;
                              final cellWidth = fieldWidth < 180
                                  ? constraints.maxWidth
                                  : fieldWidth;
                              return Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: [
                                  if (!_isPharmacist)
                                    SizedBox(
                                      width: cellWidth,
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _selectedSellerId,
                                        decoration: const InputDecoration(
                                          labelText: 'Staff',
                                          isDense: true,
                                        ),
                                        isExpanded: true,
                                        items: [
                                          const DropdownMenuItem<String>(
                                            value: null,
                                            child: Text('All staff'),
                                          ),
                                          ..._sellerOptions.map(
                                            (s) => DropdownMenuItem<String>(
                                              value: s['id'],
                                              child: Text(
                                                s['name'] ?? '',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          setState(
                                            () => _selectedSellerId = value,
                                          );
                                          _runSoon();
                                        },
                                      ),
                                    ),
                                  SizedBox(
                                    width: cellWidth,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _selectedPaymentMethod,
                                      decoration: const InputDecoration(
                                        labelText: 'Payment',
                                        isDense: true,
                                      ),
                                      isExpanded: true,
                                      items: const [
                                        DropdownMenuItem<String>(
                                          value: null,
                                          child: Text('All methods'),
                                        ),
                                        DropdownMenuItem<String>(
                                          value: 'cash',
                                          child: Text('Cash'),
                                        ),
                                        DropdownMenuItem<String>(
                                          value: 'mobile_banking',
                                          child: Text('Mobile banking'),
                                        ),
                                      ],
                                      onChanged: (value) {
                                        setState(
                                          () => _selectedPaymentMethod = value,
                                        );
                                        _runSoon();
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: cellWidth,
                                    child: TextField(
                                      controller: _minAmountCtl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Min amount',
                                        isDense: true,
                                      ),
                                      onChanged: (_) => _runSoon(),
                                    ),
                                  ),
                                  SizedBox(
                                    width: cellWidth,
                                    child: TextField(
                                      controller: _maxAmountCtl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Max amount',
                                        isDense: true,
                                      ),
                                      onChanged: (_) => _runSoon(),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Only price overrides'),
                            subtitle: const Text(
                              'Show rows with override reasons only',
                            ),
                            value: _overridesOnly,
                            onChanged: (v) {
                              setState(() => _overridesOnly = v);
                              _runSoon();
                            },
                          ),
                        ],
                        if (_supportsCategoryFilter && categoryOptions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Medicine categories'),
                            subtitle: Text(
                              _selectedCategoryKeys.isEmpty
                                  ? 'All categories'
                                  : '${_selectedCategoryKeys.length} selected',
                            ),
                            trailing: const Icon(Icons.checklist_rounded),
                            onTap: () async {
                              final selected = await _pickCategoryIds(
                                categoryOptions,
                                _selectedCategoryKeys,
                              );
                              if (selected == null) return;
                              setState(() {
                                _selectedCategoryKeys
                                  ..clear()
                                  ..addAll(selected);
                              });
                              _runSoon();
                            },
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
                              fillColor: cs.surfaceContainerHighest.withValues(
                                alpha: 0.35,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: cs.outline.withValues(alpha: 0.28),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: cs.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            controller: _thresholdCtl,
                            onChanged: (_) => _runSoon(),
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
                      ],
                    ),
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: _loading && !hasData
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: cs.primary),
                            const SizedBox(height: 16),
                            Text(
                              'Fetching rows…',
                              style: t.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : showInitialTableEmpty
                    ? _EmptyReportState(
                        hasRun: false,
                        message:
                            'Data loads automatically. Adjust filters above, or use refresh from the app bar.',
                      )
                    : showEmptyTableWithSearch
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _reportSearchBarRow(t, cs, display.length),
                          Expanded(
                            child: !hasData && filterTrim.isNotEmpty
                                ? _EmptyReportState(
                                    hasRun: false,
                                    title: 'Nothing to show',
                                    icon: Icons.search_off_rounded,
                                    message:
                                        'There is no data for the current filters. Clear the table search or adjust filters above.',
                                  )
                                : _EmptyReportState(
                                    hasRun: true,
                                    message:
                                        'No rows match your search. Clear the search box.',
                                  ),
                          ),
                        ],
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
                                    leading: Icon(
                                      Icons.search_rounded,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    trailing: [
                                      if (_filter.isNotEmpty)
                                        IconButton(
                                          tooltip: 'Clear',
                                          icon: Icon(
                                            Icons.close_rounded,
                                            color: cs.onSurfaceVariant,
                                          ),
                                          onPressed: () {
                                            _searchCtl.clear();
                                            setState(() => _filter = '');
                                          },
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _filter = v),
                                    elevation: WidgetStateProperty.all(0),
                                    backgroundColor: WidgetStateProperty.all(
                                      cs.surface.withValues(alpha: 0.95),
                                    ),
                                    side: WidgetStateProperty.all(
                                      BorderSide(
                                        color: cs.outline.withValues(
                                          alpha: 0.22,
                                        ),
                                      ),
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer.withValues(
                                        alpha: 0.65,
                                      ),
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
                                Icon(
                                  Icons.swap_vert_rounded,
                                  size: 18,
                                  color: cs.onSurfaceVariant,
                                ),
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
                            child: SingleChildScrollView(
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

  Future<Set<String>?> _pickCategoryIds(
    List<Map<String, String>> options,
    Set<String> selected,
  ) async {
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final temp = Set<String>.from(selected);
        return StatefulBuilder(
          builder: (context, setModalState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Select categories'),
                  trailing: TextButton(
                    onPressed: () => setModalState(temp.clear),
                    child: const Text('Clear'),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final option in options)
                        CheckboxListTile(
                          value: temp.contains(option['id']),
                          title: Text(option['name'] ?? ''),
                          onChanged: (checked) {
                            setModalState(() {
                              final id = option['id'];
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
                  padding: const EdgeInsets.all(12),
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
                          onPressed: () => Navigator.pop(ctx, temp),
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyReportState extends StatelessWidget {
  const _EmptyReportState({
    required this.hasRun,
    required this.message,
    this.title,
    this.icon,
  });

  final bool hasRun;
  final String message;
  final String? title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final effectiveIcon =
        icon ?? (hasRun ? Icons.search_off_rounded : Icons.table_rows_rounded);
    final effectiveTitle = title ?? (hasRun ? 'No matches' : 'No rows yet');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                effectiveIcon,
                size: 48,
                color: cs.primary.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 14),
              Text(
                effectiveTitle,
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
                        onSort: (columnIndex, asc) =>
                            onSort(keys[columnIndex], asc),
                      ),
                  ],
                  rows: [
                    for (var i = 0; i < rows.length; i++)
                      DataRow(
                        color: WidgetStatePropertyAll(
                          i.isEven
                              ? null
                              : cs.surfaceContainerHighest.withValues(
                                  alpha: 0.22,
                                ),
                        ),
                        cells: [
                          for (final k in keys)
                            DataCell(
                              SelectableText(
                                _reportTableCellDisplayText(k, rows[i][k]),
                                style: t.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface,
                                ),
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
