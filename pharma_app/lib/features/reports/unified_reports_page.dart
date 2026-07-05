import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/shared_preferences_provider.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';
import 'report_date_range.dart';
import 'report_display.dart';
import '../../core/utils/date_formatters.dart';
import 'report_filter_bar.dart';
import 'report_filter_sheet.dart';
import 'report_preferences.dart';
import 'report_skeleton.dart';
import 'report_ui.dart';

enum _ResultsView { cards, table }

class UnifiedReportsPage extends ConsumerStatefulWidget {
  const UnifiedReportsPage({super.key});

  @override
  ConsumerState<UnifiedReportsPage> createState() => _UnifiedReportsPageState();
}

class _UnifiedReportsPageState extends ConsumerState<UnifiedReportsPage> {
  bool _loading = false;
  String? _error;
  late ReportDateRange _dateRange;
  _ResultsView _view = _ResultsView.cards;

  List<Map<String, dynamic>> _itemRows = [];
  Map<String, dynamic>? _salesStats;
  Map<String, dynamic>? _profitRow;
  Map<String, dynamic>? _metrics;
  DateTime? _lastUpdated;

  String _filter = '';
  final TextEditingController _searchCtl = TextEditingController();
  Timer? _autoRunDebounce;
  Timer? _searchDebounce;
  bool _autoRunScheduled = false;
  bool _prefsRestored = false;
  bool _loadingSales = false;
  bool _loadingMoreSales = false;

  String? _selectedSellerId;
  String? _selectedPaymentMethod;
  bool _overridesOnly = false;
  final Set<String> _selectedCategoryKeys = <String>{};
  List<Map<String, String>> _sellerOptions = const [];

  bool get _isPharmacist {
    final role =
        (ref.watch(pharmacyProfileProvider).asData?.value?['role'] as String? ??
                '')
            .trim()
            .toLowerCase();
    return role == 'pharmacist';
  }

  String? get _effectiveSoldByForRpc {
    if (!_isPharmacist) return _selectedSellerId;
    return Supabase.instance.client.auth.currentUser?.id;
  }

  String get _activeReportType => 'sales_unified';

  List<Map<String, dynamic>> get _activeRows => _itemRows;

  int get _salesFetchLimit =>
      _view == _ResultsView.cards ? kReportSalesCardsLimit : kReportSalesTablePageSize;

  int get _salesTotalCount =>
      (_salesStats?['line_count'] as num?)?.toInt() ?? _itemRows.length;

  bool get _hasMoreSales => _salesTotalCount > _itemRows.length;

  bool get _showSeeAll =>
      _view == _ResultsView.cards && _salesTotalCount > kReportSalesCardsLimit;

  @override
  void initState() {
    super.initState();
    _dateRange = ReportDateRange.initial();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isPharmacist) return;
    final before = _dateRange.preset;
    _dateRange.clampForPharmacist();
    if (before != _dateRange.preset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runSoon();
      });
    }
  }

  @override
  void dispose() {
    _autoRunDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _runSoon([Duration delay = const Duration(milliseconds: 250)]) {
    _autoRunDebounce?.cancel();
    _autoRunDebounce = Timer(delay, () {
      if (!mounted || _loading) return;
      _loadAll();
    });
  }

  void _scheduleInitialLoad() {
    if (_autoRunScheduled) return;
    _autoRunScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_prefsRestored) {
        _prefsRestored = true;
        final prefs = ref.read(sharedPreferencesProvider);
        setState(() {
          _dateRange = ReportPreferences.loadDateRange(
            prefs,
            pharmacistMode: _isPharmacist,
          );
          _view = ReportPreferences.loadCardsView(prefs)
              ? _ResultsView.cards
              : _ResultsView.table;
        });
      }
      _loadAll();
    });
  }

  Future<void> _persistDateRange() =>
      ReportPreferences.saveDateRange(
        ref.read(sharedPreferencesProvider),
        _dateRange,
      );

  Future<void> _persistView() => ReportPreferences.saveCardsView(
        ref.read(sharedPreferencesProvider),
        cards: _view == _ResultsView.cards,
      );

  ReportDatePreset? get _visibleDatePreset => _dateRange.quickChipPreset;

  int get _advancedFilterCount {
    var count = 0;
    if (_isPharmacist) {
      if (_dateRange.preset != ReportDatePreset.today &&
          _dateRange.preset != ReportDatePreset.last7 &&
          _dateRange.preset != ReportDatePreset.last30) {
        count++;
      }
    } else if (_dateRange.preset != ReportDatePreset.today &&
        _dateRange.preset != ReportDatePreset.last7 &&
        _dateRange.preset != ReportDatePreset.last30) {
      count++;
    }
    if (_selectedSellerId != null) count++;
    if (_selectedPaymentMethod != null) count++;
    if (_overridesOnly) count++;
    if (_selectedCategoryKeys.isNotEmpty) count++;
    return count;
  }

  Future<void> _ensureSellerOptions(String teamId) async {
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

  Future<void> _loadAll() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch');
      return;
    }
    if (_dateRange.from.isAfter(_dateRange.to)) {
      setState(() => _error = 'From date cannot be after To date.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _ensureSellerOptions(teamId);
      final fmt = DateFormat('yyyy-MM-dd');
      final from = fmt.format(_dateRange.from);
      final to = fmt.format(_dateRange.to);

      final futures = <Future<void>>[
        _loadSalesItem(teamId, branchId, from, to),
        _loadAttentionMetrics(teamId, branchId),
      ];
      if (!_isPharmacist) {
        futures.add(_loadProfit(teamId, branchId, from, to));
      }

      await Future.wait(futures);

      if (mounted) {
        setState(() => _lastUpdated = DateTime.now());
      }
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfit(String teamId, String branchId, String from, String to) async {
    final data = await Supabase.instance.client.rpc(
      'rpc_report_profit_summary',
      params: {
        'p_team_id': teamId,
        'p_branch_id': branchId,
        'p_from': from,
        'p_to': to,
      },
    );
    final rows = List<Map<String, dynamic>>.from(data as List);
    _profitRow = rows.isEmpty ? null : rows.first;
  }

  Future<void> _loadAttentionMetrics(String teamId, String branchId) async {
    final m = await Supabase.instance.client.rpc(
      'dashboard_metrics',
      params: {
        'p_team_id': teamId,
        'p_branch_id': branchId,
        'p_category_keys': null,
      },
    );
    _metrics = Map<String, dynamic>.from(m as Map);
  }

  Future<void> _loadSalesItem(
    String teamId,
    String branchId,
    String from,
    String to, {
    bool append = false,
  }) async {
    final baseParams = _salesRpcParams(teamId, branchId, from, to);
    final limit = _salesFetchLimit;
    final offset = append ? _itemRows.length : 0;

    if (!append) {
      final statsData = await Supabase.instance.client.rpc(
        'rpc_report_sales_unified_stats',
        params: baseParams,
      );
      final statsRows = List<Map<String, dynamic>>.from(statsData as List);
      _salesStats = statsRows.isEmpty ? null : statsRows.first;
    }

    final data = await Supabase.instance.client.rpc(
      'rpc_report_sales_unified',
      params: {
        ...baseParams,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    final newRows = List<Map<String, dynamic>>.from(data as List);
    if (append) {
      _itemRows = [..._itemRows, ...newRows];
    } else {
      _itemRows = newRows;
    }
  }

  Map<String, dynamic> _salesRpcParams(
    String teamId,
    String branchId,
    String from,
    String to,
  ) {
    final search = _filter.trim();
    return {
      'p_team_id': teamId,
      'p_branch_id': branchId,
      'p_from': from,
      'p_to': to,
      'p_sold_by': _effectiveSoldByForRpc,
      'p_min_amount': null,
      'p_max_amount': null,
      'p_payment_method': _selectedPaymentMethod,
      'p_overrides_only': _overridesOnly,
      'p_category_keys': _selectedCategoryKeys.isEmpty
          ? null
          : _selectedCategoryKeys.toList(growable: false),
      'p_search': search.isEmpty ? null : search,
    };
  }

  Future<void> _reloadSales() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) return;

    setState(() {
      _loadingSales = true;
      _error = null;
    });

    try {
      final fmt = DateFormat('yyyy-MM-dd');
      await _loadSalesItem(
        teamId,
        branchId,
        fmt.format(_dateRange.from),
        fmt.format(_dateRange.to),
      );
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loadingSales = false);
    }
  }

  Future<void> _loadMoreSales() async {
    if (_loadingMoreSales || !_hasMoreSales) return;
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) return;

    setState(() => _loadingMoreSales = true);
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      await _loadSalesItem(
        teamId,
        branchId,
        fmt.format(_dateRange.from),
        fmt.format(_dateRange.to),
        append: true,
      );
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loadingMoreSales = false);
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _filter = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _reloadSales();
    });
  }

  List<Map<String, dynamic>> get _displayRows {
    if (_view == _ResultsView.table) {
      if (_itemRows.isEmpty) return const [];
      final summary = unifiedSummaryRowFromStats(_salesStats);
      if (summary != null) return [..._itemRows, summary];
    }
    return _itemRows;
  }

  void _applyVisibleDatePreset(ReportDatePreset preset) {
    setState(() => _dateRange.applyPreset(preset));
    unawaited(_persistDateRange());
    _runSoon();
  }

  Future<void> _showMoreFilters(
    BuildContext context,
    List<Map<String, String>> categoryOptions,
  ) async {
    final result = await ReportFilterSheet.show(
      context,
      dateRange: _dateRange,
      isPharmacist: _isPharmacist,
      sellerOptions: _sellerOptions,
      categoryOptions: categoryOptions,
      initialSellerId: _selectedSellerId,
      initialPaymentMethod: _selectedPaymentMethod,
      initialOverridesOnly: _overridesOnly,
      initialCategoryKeys: _selectedCategoryKeys,
    );
    if (result == null || !result.apply) return;

    setState(() {
      if (result.clearAll) {
        _dateRange.applyPreset(
          _isPharmacist ? ReportDatePreset.today : ReportDatePreset.last30,
        );
        _selectedSellerId = null;
        _selectedPaymentMethod = null;
        _overridesOnly = false;
        _selectedCategoryKeys.clear();
      } else {
        _dateRange.preset = result.dateRange.preset;
        _dateRange.from = result.dateRange.from;
        _dateRange.to = result.dateRange.to;
        _selectedSellerId = result.sellerId;
        _selectedPaymentMethod = result.paymentMethod;
        _overridesOnly = result.overridesOnly;
        _selectedCategoryKeys
          ..clear()
          ..addAll(result.categoryKeys);
      }
    });
    unawaited(_persistDateRange());
    _runSoon();
  }

  String _formatMetric(Object? v, {required int decimals}) {
    if (v == null) return '0';
    if (v is num) {
      if (decimals == 0) {
        return NumberFormat.decimalPattern().format(v);
      }
      return NumberFormat('#,##0.${'0' * decimals}').format(v);
    }
    return '$v';
  }

  String _money(Object? v) => '${_formatMetric(v, decimals: 2)} ETB';

  Widget _compactHeader(BuildContext context, String branchLabel) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                branchLabel,
                style: t.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _lastUpdated == null
                    ? 'Not updated yet'
                    : 'Updated ${formatDdMmYyyyHm(_lastUpdated)}',
                style: t.textTheme.labelSmall?.copyWith(
                  color: ReportUi.mutedText(cs),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _loadAll,
          icon: Icon(Icons.refresh_rounded, color: cs.primary),
        ),
      ],
    );
  }

  Widget _inventoryHealthSection(BuildContext context) {
    if (_metrics == null) return const SizedBox.shrink();
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final lowCount = (_metrics!['low_stock_count'] as num?)?.toInt() ?? 0;
    final nearCount = (_metrics!['near_expiry_count'] as num?)?.toInt() ?? 0;
    final expiredCount = (_metrics!['expired_count'] as num?)?.toInt() ?? 0;
    final low = _formatMetric(_metrics!['low_stock_count'], decimals: 0);
    final near = _formatMetric(_metrics!['near_expiry_count'], decimals: 0);
    final expired = _formatMetric(_metrics!['expired_count'], decimals: 0);
    final stockValue = _money(_metrics!['stock_value_at_cost']);

    Widget attentionTile(
      String title,
      String value,
      String route,
      IconData icon,
      Color iconColor, {
      Color? valueColor,
    }) {
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minVerticalPadding: 0,
        leading: Container(
          width: 32,
          height: 32,
          decoration: ReportUi.iconWellBorder(cs),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        title: Text(
          title,
          style: t.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: ReportUi.mutedText(cs),
          ),
        ),
        trailing: Text(
          value,
          style: t.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor ?? cs.onSurface,
          ),
        ),
        onTap: () => context.push(route),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            'Inventory',
            style: t.textTheme.labelMedium?.copyWith(
              color: ReportUi.mutedText(cs),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: ReportUi.surfaceCard(cs),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              attentionTile(
                'Stock value',
                stockValue,
                '/pharmacy/stock',
                Icons.inventory_2_outlined,
                cs.primary,
              ),
              Divider(height: 1, indent: 56, color: ReportUi.hairline(cs)),
              attentionTile(
                'Low stock',
                '$low items',
                '/pharmacy/stock?tab=low',
                Icons.warning_amber_rounded,
                ReportPalette.amber(cs),
                valueColor: lowCount > 0 ? ReportPalette.alert(cs) : null,
              ),
              Divider(height: 1, indent: 56, color: ReportUi.hairline(cs)),
              attentionTile(
                'Near expiry',
                '$near batches',
                '/pharmacy/expiry?tab=near',
                Icons.event_note_rounded,
                ReportPalette.blue(cs),
                valueColor: nearCount > 0 ? cs.primary : null,
              ),
              Divider(height: 1, indent: 56, color: ReportUi.hairline(cs)),
              attentionTile(
                'Expired',
                '$expired batches',
                '/pharmacy/expiry?tab=expired',
                Icons.event_busy_rounded,
                ReportPalette.alert(cs),
                valueColor: expiredCount > 0
                    ? ReportPalette.alert(cs)
                    : ReportUi.mutedText(cs),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controlsRow(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: SegmentedButton<_ResultsView>(
          segments: const [
            ButtonSegment(
              value: _ResultsView.cards,
              label: Text('Cards'),
            ),
            ButtonSegment(
              value: _ResultsView.table,
              label: Text('Table'),
            ),
          ],
          selected: {_view},
          onSelectionChanged: (s) {
            final next = s.first;
            if (next == _view) return;
            setState(() => _view = next);
            unawaited(_persistView());
            _reloadSales();
          },
          style: ReportUi.segmentedStyle(cs, t.textTheme),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleInitialLoad();
    ref.listen(selectedBranchIdProvider, (previous, next) => _loadAll());

    final teamId =
        ref.watch(pharmacyProfileProvider).asData?.value?['team_id'] as String?;
    final branchId = ref.watch(selectedBranchIdProvider);
    final branchesAsync = ref.watch(branchesListProvider(teamId ?? ''));

    final branchLabel = teamId == null || teamId.isEmpty
        ? '—'
        : branchesAsync.when(
            loading: () => '…',
            error: (_, _) => '—',
            data: (branches) {
              if (branchId == null) return 'No branch selected';
              for (final b in branches) {
                if (b['id'] == branchId) {
                  return b['name'] as String? ?? 'Branch';
                }
              }
              return 'Unknown branch';
            },
          );

    final t = Theme.of(context);
    final cs = t.colorScheme;
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

    final display = _displayRows;
    final hasData = _itemRows.isNotEmpty;
    final filterTrim = _filter.trim();
    final keys = _activeRows.isNotEmpty
        ? visibleReportKeys(_activeReportType, _activeRows.first.keys)
        : <String>[];

    if (branchId == null && !_loading && _error == null) {
      return Scaffold(
        body: AppErrorState(message: 'Select a branch', onRetry: _loadAll),
      );
    }

    return Scaffold(
      backgroundColor: ReportUi.pageBackground(cs),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PharmacyPageHeader(
                    title: 'Reports',
                    padding: EdgeInsets.fromLTRB(2, 0, 2, 10),
                  ),
                  _compactHeader(context, branchLabel),
                  const SizedBox(height: 10),
                  ReportDateFilterBar(
                    selected: _visibleDatePreset ?? _dateRange.preset,
                    pharmacistMode: _isPharmacist,
                    filterCount: _advancedFilterCount,
                    rangeLabel: _dateRange.rangeLabel,
                    onSelected: _applyVisibleDatePreset,
                    onOpenFilters: () =>
                        _showMoreFilters(context, categoryOptions),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: FormErrorBanner(message: _error!),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAll,
              color: cs.primary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_isPharmacist) ...[
                            Padding(
                              padding: const EdgeInsets.only(left: 2, bottom: 8),
                              child: Text(
                                'Performance',
                                style: t.textTheme.labelMedium?.copyWith(
                                  color: ReportUi.mutedText(cs),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_profitRow != null)
                              ProfitSummaryGrid(row: _profitRow!)
                            else if (_loading)
                              const ReportMoneySummarySkeleton(),
                            if (_profitRow != null || _loading)
                              const SizedBox(height: 12),
                          ],
                          if (_metrics != null)
                            _inventoryHealthSection(context)
                          else if (_loading)
                            const ReportInventorySkeleton(),
                        ],
                      ),
                    ),
                  ),
                    SliverToBoxAdapter(child: _controlsRow(context)),
                    SliverToBoxAdapter(
                      child: ReportSearchField(
                        controller: _searchCtl,
                        hintText: 'Search sales…',
                        resultCount: _salesTotalCount,
                        onChanged: _onSearchChanged,
                        onClear: () {
                          _searchCtl.clear();
                          _onSearchChanged('');
                        },
                      ),
                    ),
                    if ((_loading || _loadingSales) && !hasData)
                      const SliverToBoxAdapter(child: ReportResultsSkeleton())
                    else if (display.isEmpty && !_loading && !_loadingSales)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              filterTrim.isNotEmpty
                                  ? 'No rows match your search.'
                                  : 'Nothing to show for these filters.',
                              textAlign: TextAlign.center,
                              style: t.textTheme.bodyLarge?.copyWith(
                                color: ReportUi.mutedText(cs),
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (_view == _ResultsView.cards)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => ReportRowCard(
                              reportType: _activeReportType,
                              keys: keys,
                              row: display[index],
                              compact: true,
                            ),
                            childCount: display.length,
                          ),
                        ),
                      )
                    else
                      SliverToBoxAdapter(
                        child: ReportDataTable(
                          reportType: _activeReportType,
                          keys: keys,
                          rows: display,
                        ),
                      ),
                    if (_showSeeAll)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() => _view = _ResultsView.table);
                              unawaited(_persistView());
                              _reloadSales();
                            },
                            child: Text('See all ($_salesTotalCount)'),
                          ),
                        ),
                      )
                    else if (_view == _ResultsView.table && _hasMoreSales)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: TextButton(
                            onPressed: _loadingMoreSales ? null : _loadMoreSales,
                            child: Text(
                              _loadingMoreSales
                                  ? 'Loading…'
                                  : 'Load more (${_itemRows.length} of $_salesTotalCount)',
                            ),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Factory for route query params (legacy `?view=staff` ignored).
UnifiedReportsPage unifiedReportsPageFromState(GoRouterState state) {
  return const UnifiedReportsPage();
}
