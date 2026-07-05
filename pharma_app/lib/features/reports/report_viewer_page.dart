import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/utils/csv_export.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/review/app_review_prompter.dart';
import '../../core/utils/date_formatters.dart';
import '../../core/widgets/form_error_banner.dart';
import 'report_date_range.dart';
import 'report_display.dart';
import 'report_filter_bar.dart';

enum _DatePreset { today, last7, thisMonth, last30, thisYear, lifetime, custom }

enum _TrendPreset { day, month, year }

class ReportViewerPage extends ConsumerStatefulWidget {
  const ReportViewerPage({super.key, required this.reportType});

  final String reportType;

  @override
  ConsumerState<ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends ConsumerState<ReportViewerPage> {
  static final DateTime _lifetimeFrom = DateTime(2020, 1, 1);

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _filter = '';
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
      case _DatePreset.thisMonth:
        _to = today;
        _from = DateTime(today.year, today.month, 1);
      case _DatePreset.last30:
        _to = today;
        _from = today.subtract(const Duration(days: 29));
      case _DatePreset.thisYear:
        _to = today;
        _from = DateTime(today.year, 1, 1);
      case _DatePreset.lifetime:
        _to = today;
        _from = _dateOnly(_lifetimeFrom);
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
      _applyDatePreset(_DatePreset.thisMonth);
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
    if (_datePreset != _DatePreset.today &&
        _datePreset != _DatePreset.last7 &&
        _datePreset != _DatePreset.last30) {
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
            'p_search': null,
            'p_limit': 500,
            'p_offset': 0,
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
                'p_search': null,
                'p_limit': 500,
                'p_offset': 0,
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
                'p_search': null,
                'p_limit': 500,
                'p_offset': 0,
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
        unawaited(
          ref
              .read(appReviewPrompterProvider)
              .maybeRequestReview(AppReviewMoment.reportExported),
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
    return _appendUnifiedSummaryRow(rows);
  }

  String get _pageTitle => switch (widget.reportType) {
    'sales_unified' => 'Sales',
    'sales_summary' => 'Sales',
    'sales_by_staff' => 'Sales by staff',
    'stock_balance' => 'Stock',
    'expiry_status' => 'Expiry',
    'profit_summary' => 'Profit',
    'sales_trend' => 'Sales trend',
    'sales_trend_daily' => 'Daily trend',
    'sales_trend_monthly' => 'Monthly trend',
    'sales_trend_yearly' => 'Yearly trend',
    _ => 'Report',
  };

  ReportDatePreset? get _visibleDatePreset {
    return switch (_datePreset) {
      _DatePreset.today => ReportDatePreset.today,
      _DatePreset.last7 => ReportDatePreset.last7,
      _DatePreset.thisMonth => ReportDatePreset.thisMonth,
      _DatePreset.last30 => ReportDatePreset.last30,
      _ => null,
    };
  }

  String? get _dateRangeLabel {
    if (!_isSalesRangeReport) return null;
    return switch (_datePreset) {
      _DatePreset.custom ||
      _DatePreset.thisYear ||
      _DatePreset.lifetime ||
      _DatePreset.last30 =>
        '${formatDdMmYyyy(_from)} – ${formatDdMmYyyy(_to)}',
      _ => null,
    };
  }

  int get _advancedFilterCount {
    var count = 0;
    if (_isSalesRangeReport) {
      if (_narrowPharmacistSalesDates) {
        if (_datePreset != _DatePreset.today &&
            _datePreset != _DatePreset.last7 &&
            _datePreset != _DatePreset.last30) {
          count++;
        }
      } else if (_datePreset != _DatePreset.today &&
          _datePreset != _DatePreset.last7 &&
          _datePreset != _DatePreset.thisMonth) {
        count++;
      }
    }
    if (_selectedSellerId != null) count++;
    if (_selectedPaymentMethod != null) count++;
    if (_overridesOnly) count++;
    if (_selectedCategoryKeys.isNotEmpty) count++;
    if (widget.reportType == 'expiry_status' &&
        (_thresholdCtl.text.trim().isNotEmpty &&
            _thresholdCtl.text.trim() != '90')) {
      count++;
    }
    return count;
  }

  void _applyVisibleDatePreset(ReportDatePreset preset) {
    _applyDatePreset(switch (preset) {
      ReportDatePreset.today => _DatePreset.today,
      ReportDatePreset.last7 => _DatePreset.last7,
      ReportDatePreset.thisMonth => _DatePreset.thisMonth,
      ReportDatePreset.last30 => _DatePreset.last30,
      ReportDatePreset.thisYear => _DatePreset.thisYear,
      ReportDatePreset.lifetime => _DatePreset.lifetime,
      ReportDatePreset.custom => _DatePreset.custom,
    });
  }

  Widget _reportSearchBarRow(ThemeData t, ColorScheme cs, int displayCount) {
    return ReportSearchField(
      controller: _searchCtl,
      hintText: 'Search this report…',
      resultCount: displayCount,
      onChanged: (v) => setState(() => _filter = v),
      onClear: () {
        _searchCtl.clear();
        setState(() => _filter = '');
      },
    );
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

  Future<void> _showMoreFilters(
    BuildContext context,
    List<Map<String, String>> categoryOptions,
  ) async {
    final t = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Filters',
                        style: t.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isSalesRangeReport && !_narrowPharmacistSalesDates) ...[
                        Text(
                          'Date range',
                          style: t.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Material(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(14),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: const Icon(Icons.date_range_rounded),
                            title: Text(
                              '${formatDdMmYyyy(_from)} – ${formatDdMmYyyy(_to)}',
                            ),
                            subtitle: const Text('Pick custom dates'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () async {
                              Navigator.pop(ctx);
                              await _pickDateRangeQuick();
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilterChip(
                              label: const Text('Last 30 days'),
                              selected: _datePreset == _DatePreset.last30,
                              onSelected: (_) {
                                setState(() => _applyDatePreset(_DatePreset.last30));
                                Navigator.pop(ctx);
                                _runSoon();
                              },
                            ),
                            FilterChip(
                              label: const Text('This year'),
                              selected: _datePreset == _DatePreset.thisYear,
                              onSelected: (_) {
                                setState(() => _applyDatePreset(_DatePreset.thisYear));
                                Navigator.pop(ctx);
                                _runSoon();
                              },
                            ),
                            FilterChip(
                              label: const Text('Lifetime'),
                              selected: _datePreset == _DatePreset.lifetime,
                              onSelected: (_) {
                                setState(() => _applyDatePreset(_DatePreset.lifetime));
                                Navigator.pop(ctx);
                                _runSoon();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (_isUnifiedSalesReport) ...[
                        Text(
                          'Sales details',
                          style: t.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!_isPharmacist)
                          DropdownButtonFormField<String>(
                            initialValue: _selectedSellerId,
                            decoration: const InputDecoration(
                              labelText: 'Staff member',
                              border: OutlineInputBorder(),
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
                              setModal(() => _selectedSellerId = value);
                            },
                          ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedPaymentMethod,
                          decoration: const InputDecoration(
                            labelText: 'Payment method',
                            border: OutlineInputBorder(),
                          ),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text('All methods'),
                            ),
                            DropdownMenuItem(
                              value: 'cash',
                              child: Text('Cash'),
                            ),
                            DropdownMenuItem(
                              value: 'mobile_banking',
                              child: Text('Mobile banking'),
                            ),
                          ],
                          onChanged: (value) {
                            setModal(() => _selectedPaymentMethod = value);
                          },
                        ),
                        const SizedBox(height: 6),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Price overrides only'),
                          value: _overridesOnly,
                          onChanged: (v) => setModal(() => _overridesOnly = v),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_supportsCategoryFilter && categoryOptions.isNotEmpty) ...[
                        Text(
                          'Categories',
                          style: t.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Material(
                          borderRadius: BorderRadius.circular(14),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            title: const Text('Medicine categories'),
                            subtitle: Text(
                              _selectedCategoryKeys.isEmpty
                                  ? 'All categories'
                                  : '${_selectedCategoryKeys.length} selected',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () async {
                              final selected = await _pickCategoryIds(
                                categoryOptions,
                                _selectedCategoryKeys,
                              );
                              if (selected == null) return;
                              setModal(() {
                                _selectedCategoryKeys
                                  ..clear()
                                  ..addAll(selected);
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.reportType == 'expiry_status') ...[
                        TextField(
                          controller: _thresholdCtl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Days ahead for expiry warning',
                            hintText: '90',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _runSoon();
                        },
                        child: const Text('Apply filters'),
                      ),
                      if (_advancedFilterCount > 0) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (_isSalesRangeReport) {
                                _applyDatePreset(
                                  _narrowPharmacistSalesDates
                                      ? _DatePreset.today
                                      : _DatePreset.thisMonth,
                                );
                              }
                              _selectedSellerId = null;
                              _selectedPaymentMethod = null;
                              _overridesOnly = false;
                              _selectedCategoryKeys.clear();
                              _thresholdCtl.text = '90';
                            });
                            Navigator.pop(ctx);
                            _runSoon();
                          },
                          child: const Text('Clear all filters'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_pharmacistProfitBlocked) {
      return Scaffold(
        appBar: pharmacyPageAppBar(context, title: 'Profit summary'),
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
        ? visibleReportKeys(widget.reportType, _rows.first.keys)
        : <String>[];
    final display = _displayRows;
    final hasData = _rows.isNotEmpty;
    final filterTrim = _filter.trim();
    final showInitialEmpty =
        display.isEmpty && !hasData && filterTrim.isEmpty;
    final showEmptyWithSearch =
        display.isEmpty && (hasData || filterTrim.isNotEmpty);
    final isProfitSummary =
        widget.reportType == 'profit_summary' && _rows.length == 1;
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
      appBar: pharmacyPageAppBar(
        context,
        title: _pageTitle,
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isSalesRangeReport) ...[
                    if (widget.reportType == 'sales_trend') ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final (preset, label) in [
                              (_TrendPreset.day, 'Day'),
                              (_TrendPreset.month, 'Month'),
                              (_TrendPreset.year, 'Year'),
                            ]) ...[
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(label),
                                  selected: _trendPreset == preset,
                                  showCheckmark: false,
                                  onSelected: (_) {
                                    setState(() => _trendPreset = preset);
                                    _runSoon();
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ReportDateFilterBar(
                      selected: _visibleDatePreset,
                      pharmacistMode: _narrowPharmacistSalesDates,
                      filterCount: _advancedFilterCount,
                      rangeLabel: _dateRangeLabel,
                      onSelected: (preset) {
                        setState(() => _applyVisibleDatePreset(preset));
                        _runSoon();
                      },
                      onOpenFilters: () =>
                          _showMoreFilters(context, categoryOptions),
                    ),
                  ] else if (_supportsCategoryFilter || widget.reportType == 'expiry_status')
                    ReportDateFilterBar(
                      showDatePresets: false,
                      filterCount: _advancedFilterCount,
                      onOpenFilters: () =>
                          _showMoreFilters(context, categoryOptions),
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
            child: ColoredBox(
              color: cs.surfaceContainerLowest,
              child: ClipRRect(
                child: _loading && !hasData
                    ? const Center(child: CircularProgressIndicator())
                    : showInitialEmpty
                    ? const _EmptyReportState(
                        hasRun: false,
                        message: 'Loading report…',
                      )
                    : showEmptyWithSearch
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _reportSearchBarRow(t, cs, display.length),
                          Expanded(
                            child: _EmptyReportState(
                              hasRun: hasData,
                              message: hasData
                                  ? 'No rows match your search.'
                                  : 'Nothing to show for these filters.',
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isProfitSummary)
                            _reportSearchBarRow(t, cs, display.length),
                          Expanded(
                            child: isProfitSummary
                                ? ProfitSummaryCard(row: _rows.first)
                                : ReportSimpleList(
                                    reportType: widget.reportType,
                                    keys: keys,
                                    rows: display,
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
  });

  final bool hasRun;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final effectiveIcon =
        hasRun ? Icons.search_off_rounded : Icons.table_rows_rounded;
    final effectiveTitle = hasRun ? 'No matches' : 'No rows yet';
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
