import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/branch_change_guard_provider.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/providers/sync_status_provider.dart';
import '../medicines/medicine_search_bar.dart';
import '../medicines/scan/medicine_lookup_resolver.dart';
import '../medicines/scan/medicine_scan_controller.dart';
import '../medicines/scan/scan_entry_widget.dart';
import 'offline/pos_catalog_cache_repository.dart';
import 'offline/pos_offline_providers.dart';
import 'pos_sale_expiry.dart';

class _PosCartLine {
  _PosCartLine({
    required this.medicineId,
    required this.medicineName,
    required this.manualCode,
    required num listPricePerBase,
    required this.batchesWithQty,
    required this.qtyBase,
  })  : _medicineSellPrice = listPricePerBase,
        selectedBatchId = batchesWithQty.first['id'] as String;

  final String medicineId;
  final String medicineName;
  final String manualCode;
  final num _medicineSellPrice;
  final List<Map<String, dynamic>> batchesWithQty;

  String selectedBatchId;
  num qtyBase;
  num? overridePrice;
  String? overrideReason;
  final TextEditingController priceController = TextEditingController();
  final TextEditingController reasonController = TextEditingController();

  /// Sell price from the currently selected batch, falling back to medicine default.
  num get listPricePerBase {
    for (final b in batchesWithQty) {
      if (b['id'] == selectedBatchId) {
        final sp = b['sell_price_base'];
        if (sp is num && sp > 0) return sp;
        break;
      }
    }
    return _medicineSellPrice;
  }

  void initControllers() {
    priceController.text = listPricePerBase.toStringAsFixed(2);
  }

  void dispose() {
    priceController.dispose();
    reasonController.dispose();
  }

  num maxQtyBase() {
    for (final b in batchesWithQty) {
      if (b['id'] == selectedBatchId) return (b['qty_on_hand'] as num?) ?? 0;
    }
    return (batchesWithQty.first['qty_on_hand'] as num?) ?? 0;
  }

  num get unitPrice => overridePrice ?? listPricePerBase;
}

class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  final _resolver = const MedicineLookupResolver();
  final _searchCtl = TextEditingController();
  static const _guardKey = 'pos_page';
  late final BranchChangeGuard _branchChangeGuard;
  final List<_PosCartLine> _lines = [];
  List<Map<String, dynamic>> _searchMatches = const [];
  final Map<String, List<Map<String, dynamic>>> _batchCache = {};
  int _selectedLineIndex = 0;
  bool _checkoutLoading = false;
  String? _error;
  String _paymentMethod = 'cash';
  final _referenceNo = TextEditingController();
  final _discountCtl = TextEditingController();
  String? _activeBranchId;
  Timer? _searchDebounce;
  final LayerLink _posSearchLayerLink = LayerLink();

  Future<void> _refreshSearchMatches() async {
    final raw = _searchCtl.text.trim();
    final q = raw.toLowerCase();
    if (q.isEmpty) {
      if (mounted) setState(() => _searchMatches = const []);
      return;
    }
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null) return;

    final online = ref.read(connectivityProvider).value ?? true;

    try {
      List<Map<String, dynamic>> list;
      if (!online && branchId != null) {
        final snap = await ref
            .read(posCatalogCacheRepositoryProvider)
            .load(teamId, branchId);
        if (!mounted || _searchCtl.text.trim() != raw) return;
        if (snap == null) {
          setState(() => _searchMatches = const []);
          return;
        }
        final broad = snap.medicines.where((m) {
          final s =
              '${m['manual_code']} ${m['barcode']} ${m['name']} ${m['generic_name']}'
                  .toLowerCase();
          return s.contains(q);
        }).toList();
        final ranked = rankMedicines(broad, raw);
        final qtySalable = snap.qtyByMedicineIdSalableBatches();
        final qtyAll = snap.qtyByMedicineId();
        final enriched = <Map<String, dynamic>>[];
        for (final m in ranked) {
          final mid = m['id'] as String;
          if ((qtySalable[mid] ?? 0) > 0) {
            enriched.add(Map<String, dynamic>.from(m));
          } else if ((qtyAll[mid] ?? 0) > 0) {
            enriched.add({
              ...Map<String, dynamic>.from(m),
              kPosExpiredStockOnlyKey: true,
            });
          }
        }
        list = enriched.take(10).toList();
      } else {
        if (branchId == null) {
          if (!mounted || _searchCtl.text.trim() != raw) return;
          setState(() => _searchMatches = const []);
          return;
        }
        final rows = await Supabase.instance.client
            .from('medicines')
            .select('id,name,manual_code,generic_name,selling_price,barcode')
            .eq('team_id', teamId)
            .eq('branch_id', branchId)
            .eq('is_active', true)
            .or('name.ilike.%$q%,manual_code.ilike.%$q%,barcode.ilike.%$q%')
            .limit(24);
        if (!mounted || _searchCtl.text.trim() != raw) return;

        list = List<Map<String, dynamic>>.from(rows as List);
        if (list.isNotEmpty) {
          final bal = await Supabase.instance.client
              .from('stock_balances')
              .select(
                'qty_base_unit, medicine_batches(medicine_id, expiry_date)',
              )
              .eq('team_id', teamId)
              .eq('branch_id', branchId);
          if (!mounted || _searchCtl.text.trim() != raw) return;
          final qtySalable = <String, num>{};
          final qtyExpired = <String, num>{};
          for (final r in List<Map<String, dynamic>>.from(bal as List)) {
            final mb = r['medicine_batches'] as Map<String, dynamic>?;
            final mid = mb?['medicine_id'] as String?;
            if (mid == null) continue;
            final qq = (r['qty_base_unit'] as num?) ?? 0;
            if (batchExpiryIsBeforeToday(mb?['expiry_date'])) {
              qtyExpired[mid] = (qtyExpired[mid] ?? 0) + qq;
            } else {
              qtySalable[mid] = (qtySalable[mid] ?? 0) + qq;
            }
          }
          final enriched = <Map<String, dynamic>>[];
          for (final m in list) {
            final mid = m['id'] as String;
            if ((qtySalable[mid] ?? 0) > 0) {
              enriched.add(Map<String, dynamic>.from(m));
            } else if ((qtyExpired[mid] ?? 0) > 0) {
              enriched.add({
                ...Map<String, dynamic>.from(m),
                kPosExpiredStockOnlyKey: true,
              });
            }
          }
          list = rankMedicines(enriched, raw).take(10).toList();
        } else {
          list = list.take(10).toList();
        }
      }

      if (!mounted || _searchCtl.text.trim() != raw) return;
      setState(() => _searchMatches = list);
      if (online) {
        unawaited(_snapshotCatalogToDisk());
      }
    } catch (_) {
      if (mounted && _searchCtl.text.trim() == raw) {
        setState(() => _searchMatches = const []);
      }
    }
  }

  void _onSearchCtlChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_refreshSearchMatches());
    });
  }

  @override
  void initState() {
    super.initState();
    _branchChangeGuard = ref.read(branchChangeGuardProvider.notifier);
    _searchCtl.addListener(_onSearchCtlChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _branchChangeGuard.register(_guardKey, onDiscard: _discardChanges);
      unawaited(_snapshotCatalogToDisk());
    });
  }

  Future<void> _snapshotCatalogToDisk() async {
    if (!mounted) return;
    final online = ref.read(connectivityProvider).value ?? true;
    if (!online) return;
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) return;
    try {
      final meds = await Supabase.instance.client
          .from('medicines')
          .select('id,name,manual_code,generic_name,selling_price,barcode')
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .limit(2000);
      final stock = await Supabase.instance.client
          .from('stock_balances')
          .select(
            'medicine_batch_id, qty_base_unit, medicine_batches(id, medicine_id, batch_no, expiry_date, sell_price_base)',
          )
          .eq('team_id', teamId)
          .eq('branch_id', branchId);
      if (!mounted) return;
      final snap = PosCatalogSnapshot(
        teamId: teamId,
        branchId: branchId,
        savedAt: DateTime.now().toUtc(),
        medicines: List<Map<String, dynamic>>.from(meds as List),
        stockLines: List<Map<String, dynamic>>.from(stock as List),
      );
      await ref.read(posCatalogCacheRepositoryProvider).save(snap);
    } catch (_) {
      /* cache is best-effort */
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.removeListener(_onSearchCtlChanged);
    for (final line in _lines) {
      line.dispose();
    }
    _branchChangeGuard.unregister(_guardKey);
    _searchCtl.dispose();
    _referenceNo.dispose();
    _discountCtl.dispose();
    super.dispose();
  }

  void _discardChanges() {
    if (!mounted) return;
    for (final line in _lines) {
      line.dispose();
    }
    setState(() {
      _lines.clear();
      _searchMatches = const [];
      _searchCtl.clear();
      _error = null;
      _paymentMethod = 'cash';
      _referenceNo.clear();
      _discountCtl.clear();
    });
    _branchChangeGuard.clearDirty(_guardKey);
  }

  void _syncDirtyState() {
    final dirty =
        _lines.isNotEmpty ||
        _referenceNo.text.trim().isNotEmpty ||
        _discountCtl.text.trim().isNotEmpty;
    _branchChangeGuard.setDirty(_guardKey, dirty);
  }

  void _invalidatePosOutboxCounts() {
    ref.invalidate(posPendingCountProvider);
    ref.invalidate(posFailedSalesCountProvider);
  }

  Map<String, dynamic>? _selectedBatchMap(_PosCartLine line) {
    for (final b in line.batchesWithQty) {
      if (b['id'] == line.selectedBatchId) return b;
    }
    return null;
  }

  /// Prefer a non-expired batch when the current selection is invalid.
  String _effectiveBatchIdForLine(_PosCartLine line) {
    final salable = line.batchesWithQty
        .where((b) => !batchExpiryIsBeforeToday(b['expiry_date']))
        .toList();
    final choices = salable.isNotEmpty ? salable : line.batchesWithQty;
    final sel = _selectedBatchMap(line);
    final selectedBad =
        sel == null || batchExpiryIsBeforeToday(sel['expiry_date']);
    final preferred = (selectedBad && salable.isNotEmpty)
        ? salable.first['id'] as String
        : choices.any((b) => b['id'] == line.selectedBatchId)
        ? line.selectedBatchId
        : choices.first['id'] as String;
    if (preferred != line.selectedBatchId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          line.selectedBatchId = preferred;
          if (line.overridePrice == null) {
            line.priceController.text =
                line.listPricePerBase.toStringAsFixed(2);
          }
        });
        _syncDirtyState();
      });
    }
    return preferred;
  }

  Future<void> _pickMedicine(Map<String, dynamic> medicine) async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch');
      return;
    }
    final online = ref.read(connectivityProvider).value ?? true;
    final mid = medicine['id'] as String;
    for (final line in _lines) {
      if (line.medicineId == mid) {
        setState(() {
          line.qtyBase += 1;
          _error = null;
        });
        _syncDirtyState();
        return;
      }
    }
    final sell = (medicine['selling_price'] as num?) ?? 0;
    List<Map<String, dynamic>> withQty;
    if (!online) {
      final snap = await ref
          .read(posCatalogCacheRepositoryProvider)
          .load(teamId, branchId);
      if (!mounted) return;
      if (snap == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No offline catalog yet. Connect to the internet once on this screen, then try again.',
            ),
          ),
        );
        return;
      }
      withQty = snap.batchesWithQtyForMedicine(mid);
      if (withQty.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No stock in offline cache for this medicine'),
          ),
        );
        return;
      }
    } else {
      final batches =
          _batchCache[mid] ??
          List<Map<String, dynamic>>.from(
            await Supabase.instance.client
                .from('medicine_batches')
                .select('id, batch_no, expiry_date, sell_price_base')
                .eq('medicine_id', mid)
                .eq('branch_id', branchId)
                .order('expiry_date'),
          );
      _batchCache[mid] = batches;
      final batchRows = List<Map<String, dynamic>>.from(batches as List);
      if (batchRows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No batches for this medicine at this branch'),
            ),
          );
        }
        return;
      }
      final balances = await Supabase.instance.client
          .from('stock_balances')
          .select('medicine_batch_id, qty_base_unit')
          .eq('team_id', teamId)
          .eq('branch_id', branchId);
      final balMap = <String, num>{};
      for (final b in balances as List) {
        final m = b as Map<String, dynamic>;
        balMap[m['medicine_batch_id'] as String] =
            m['qty_base_unit'] as num? ?? 0;
      }
      final eligible =
          batchRows.where((row) {
            final id = row['id'] as String;
            return (balMap[id] ?? 0) > 0 &&
                !batchExpiryIsBeforeToday(row['expiry_date']);
          }).toList()..sort((a, b) {
            final da = a['expiry_date'] as String? ?? '';
            final db = b['expiry_date'] as String? ?? '';
            return da.compareTo(db);
          });
      if (!mounted) return;
      if (eligible.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              batchRows.any((row) {
                    final id = row['id'] as String;
                    return (balMap[id] ?? 0) > 0 &&
                        batchExpiryIsBeforeToday(row['expiry_date']);
                  })
                  ? 'All stock for this medicine is from expired batches.'
                  : 'No stock on hand for this medicine',
            ),
          ),
        );
        return;
      }

      withQty = eligible
          .map(
            (row) => {...row, 'qty_on_hand': balMap[row['id'] as String] ?? 0},
          )
          .toList();
    }
    withQty = withQty
        .where((b) => !batchExpiryIsBeforeToday(b['expiry_date']))
        .toList();
    if (!mounted) return;
    if (withQty.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All stock for this medicine is from expired batches.'),
        ),
      );
      return;
    }

    final line = _PosCartLine(
      medicineId: mid,
      medicineName: medicine['name'] as String? ?? 'Medicine',
      manualCode: medicine['manual_code'] as String? ?? '',
      listPricePerBase: sell,
      batchesWithQty: withQty,
      qtyBase: 1,
    );
    line.initControllers();

    setState(() {
      _lines.add(line);
      _error = null;
      _searchCtl.clear();
      _searchMatches = const [];
    });
    _syncDirtyState();
  }

  void _removeLine(int i) {
    setState(() {
      final line = _lines.removeAt(i);
      line.dispose();
    });
    _syncDirtyState();
  }

  num get _cartSubtotal {
    num sum = 0;
    for (final line in _lines) {
      final qb = _qtyBaseForLine(line);
      if (qb != null) sum += qb * line.unitPrice;
    }
    return sum;
  }

  num? _qtyBaseForLine(_PosCartLine line) {
    final q = line.qtyBase;
    if (q <= 0) return null;
    return q;
  }

  num get _discountAmount {
    final d = num.tryParse(_discountCtl.text.trim());
    if (d == null || d < 0) return 0;
    return d;
  }

  num get _cartTotal {
    final t = _cartSubtotal - _discountAmount;
    return t < 0 ? 0 : t;
  }

  bool _showPriceReason(_PosCartLine line) {
    final pc = line.overridePrice;
    return pc != null && (pc - line.listPricePerBase).abs() > 0.0001;
  }

  String? _validateCartForCheckout() {
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final qb = _qtyBaseForLine(line);
      if (qb == null) return 'Line ${i + 1}: enter a valid quantity.';
      final maxB = line.maxQtyBase();
      if (qb > maxB) {
        return 'Line ${i + 1}: quantity exceeds on-hand ($maxB base).';
      }
      final up = line.unitPrice;
      if (up < 0) {
        return 'Line ${i + 1}: enter a valid unit price (base).';
      }
      final sel = _selectedBatchMap(line);
      if (sel != null && batchExpiryIsBeforeToday(sel['expiry_date'])) {
        return 'Line ${i + 1}: This batch is expired and cannot be sold. Change batch or remove the line.';
      }
    }
    return null;
  }

  Future<void> _checkout() async {
    final branchId = ref.read(selectedBranchIdProvider);
    if (branchId == null) {
      setState(() => _error = 'Select a branch');
      return;
    }
    if (_lines.isEmpty) return;
    final disc = _discountAmount;
    if (disc > _cartSubtotal) {
      setState(() => _error = 'Discount cannot exceed subtotal.');
      return;
    }
    final v = _validateCartForCheckout();
    if (v != null) {
      setState(() => _error = v);
      return;
    }
    setState(() {
      _checkoutLoading = true;
      _error = null;
    });
    try {
      final isOnline = ref.read(connectivityProvider).value ?? true;
      final items = <Map<String, dynamic>>[];
      for (final line in _lines) {
        final qb = _qtyBaseForLine(line)!;
        final up = line.unitPrice;
        final list = line.listPricePerBase;
        final reason = (up - list).abs() > 0.0001
            ? (line.overrideReason?.trim().isNotEmpty ?? false)
                  ? line.overrideReason!.trim()
                  : null
            : null;
        items.add({
          'medicine_batch_id': line.selectedBatchId,
          'qty': qb,
          'unit_price': up,
          'price_override_reason': reason,
        });
      }
      final needRef = _paymentMethod == 'mobile_banking';
      final queued = await ref
          .read(posOutboxRepositoryProvider)
          .enqueue(
            branchId: branchId,
            paymentMethod: _paymentMethod,
            discountTotal: disc,
            items: items,
            referenceNo: needRef && _referenceNo.text.trim().isNotEmpty
                ? _referenceNo.text.trim()
                : null,
          );
      _invalidatePosOutboxCounts();
      final id = await ref
          .read(posSyncServiceProvider)
          .syncSingleQueuedSale(queued, isOnline: isOnline);
      setState(() {
        _lines.clear();
        _paymentMethod = 'cash';
        _referenceNo.clear();
        _discountCtl.clear();
      });
      _syncDirtyState();
      if (mounted) {
        final String msg;
        if (id != null) {
          msg = 'Sale completed';
        } else if (!isOnline) {
          msg = 'Saved offline. This sale will sync when internet returns.';
        } else {
          msg =
              'Sale saved on this device. The server did not confirm yet — tap Sync now or wait for automatic retry.';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        if (id != null) {
          context.push('/pharmacy/receipt/$id');
        }
      }
    } catch (e) {
      assert(() {
        if (e is PostgrestException) {
          debugPrint(
            'POS checkout Postgrest: code=${e.code} message=${e.message}',
          );
        }
        return true;
      }());
      setState(() => _error = mapFormError(e));
    } finally {
      if (mounted) setState(() => _checkoutLoading = false);
    }
  }

  Future<void> _scanAndResolve() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null) {
      setState(() => _error = 'Sign in required');
      return;
    }
    if (branchId == null) {
      setState(() => _error = 'Select a branch first.');
      return;
    }
    String? code;
    try {
      code = await showCameraScanSheet(context);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Camera scanning is unavailable here. Use search to add items.',
      );
      return;
    }
    if (code == null || code.isEmpty) return;
    final result = await _resolver.resolve(
      teamId: teamId,
      branchId: branchId,
      query: code,
    );
    if (!mounted) return;
    switch (result.state) {
      case MedicineLookupState.foundSingle:
        await _pickMedicine(result.matches.first);
      case MedicineLookupState.multipleMatches:
        setState(() => _searchMatches = result.matches);
      case MedicineLookupState.notFound:
        setState(() => _error = 'No medicine match for scanned code.');
    }
  }

  Future<void> _resolveSearchText(String value) async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) return;
    final result = await _resolver.resolve(
      teamId: teamId,
      branchId: branchId,
      query: value,
    );
    if (!mounted) return;
    switch (result.state) {
      case MedicineLookupState.foundSingle:
        await _pickMedicine(result.matches.first);
      case MedicineLookupState.multipleMatches:
        setState(() => _searchMatches = result.matches);
      case MedicineLookupState.notFound:
        setState(() => _error = 'No medicine found for "$value".');
    }
  }

  Future<void> _adjustQty(_PosCartLine line, num delta) async {
    final next = (line.qtyBase + delta).clamp(1, line.maxQtyBase());
    setState(() => line.qtyBase = next);
    _syncDirtyState();
  }

  void _adjustSelectedQty(num delta) {
    if (_lines.isEmpty) return;
    final idx = _selectedLineIndex.clamp(0, _lines.length - 1);
    _adjustQty(_lines[idx], delta);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(selectedBranchIdProvider, (prev, next) {
      if (prev != next) unawaited(_refreshSearchMatches());
    });
    ref.listen(connectivityProvider, (prev, next) {
      final now = next.value ?? false;
      if (now) unawaited(_snapshotCatalogToDisk());
    });
    ref.watch(posSyncServiceProvider);
    final profile = ref.watch(pharmacyProfileProvider).value;
    final isOnline = ref.watch(connectivityProvider).value ?? true;
    final syncStatus = ref.watch(syncStatusProvider);
    final pendingCount =
        ref.watch(posPendingCountProvider).value ?? syncStatus.pendingCount;
    final failedSalesCount = ref.watch(posFailedSalesCountProvider).value ?? 0;
    final teamId = profile?['team_id'] as String? ?? '';
    final branchId = ref.watch(selectedBranchIdProvider);
    final t = Theme.of(context);

    if (_activeBranchId != null &&
        branchId != null &&
        _activeBranchId != branchId &&
        _lines.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _discardChanges();
      });
    }
    _activeBranchId = branchId;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter, control: true):
            const ButtonActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadAdd): const NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.numpadSubtract):
            const PreviousFocusIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              if (_searchMatches.isNotEmpty) {
                _pickMedicine(_searchMatches.first);
              }
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (intent) {
              if (!_checkoutLoading && _lines.isNotEmpty) {
                _checkout();
              }
              return null;
            },
          ),
          NextFocusIntent: CallbackAction<NextFocusIntent>(
            onInvoke: (intent) {
              _adjustSelectedQty(1);
              return null;
            },
          ),
          PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
            onInvoke: (intent) {
              _adjustSelectedQty(-1);
              return null;
            },
          ),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final searchResultsMaxHeight = (constraints.maxHeight * 0.35).clamp(
              120.0,
              280.0,
            );
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isOnline || pendingCount > 0)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.cloud_sync_outlined, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    !isOnline
                                        ? 'Offline - data will sync when internet returns.'
                                        : 'Pending sync: $pendingCount',
                                    style: t.textTheme.bodySmall,
                                  ),
                                ),
                                TextButton(
                                  onPressed: isOnline
                                      ? () async {
                                          await ref
                                              .read(posSyncServiceProvider)
                                              .syncPending(isOnline: true);
                                          _invalidatePosOutboxCounts();
                                        }
                                      : null,
                                  child: const Text('Sync now'),
                                ),
                              ],
                            ),
                            if (failedSalesCount > 0) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () async {
                                    await ref
                                        .read(posOutboxRepositoryProvider)
                                        .clearFailedSales();
                                    if (!context.mounted) return;
                                    _invalidatePosOutboxCounts();
                                  },
                                  child: Text(
                                    'Dismiss $failedSalesCount failed sale(s)',
                                  ),
                                ),
                              ),
                            ],
                            if ((syncStatus.lastError ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                syncStatus.lastError!.trim(),
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                                style: t.textTheme.bodySmall?.copyWith(
                                  color: t.colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (teamId.isEmpty)
                    const Text('Sign in required')
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CompositedTransformTarget(
                              link: _posSearchLayerLink,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ScanEntryWidget(
                                      controller: _searchCtl,
                                      onScanTap: _scanAndResolve,
                                      onSubmitted: _resolveSearchText,
                                      hintText: _lines.isNotEmpty
                                          ? 'Add more medicine'
                                          : 'Search or scan medicine',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_searchMatches.isNotEmpty)
                              CompositedTransformFollower(
                                link: _posSearchLayerLink,
                                showWhenUnlinked: false,
                                targetAnchor: Alignment.bottomLeft,
                                followerAnchor: Alignment.topLeft,
                                offset: const Offset(0, 4),
                                child: Material(
                                  elevation: 12,
                                  color: t.colorScheme.surfaceContainerHigh,
                                  surfaceTintColor: Colors.transparent,
                                  shadowColor: Colors.black38,
                                  borderRadius: BorderRadius.circular(8),
                                  clipBehavior: Clip.antiAlias,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: constraints.maxWidth,
                                      maxHeight: searchResultsMaxHeight,
                                    ),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      itemCount: _searchMatches.length,
                                      itemBuilder: (context, i) {
                                        final m = _searchMatches[i];
                                        final expiredOnly =
                                            m[kPosExpiredStockOnlyKey] == true;
                                        return ListTile(
                                          dense: true,
                                          title: Text(
                                            m['name'] as String? ?? '',
                                          ),
                                          subtitle: Text(
                                            expiredOnly
                                                ? 'Expired stock only — cannot sell'
                                                : '${m['manual_code'] ?? ''} ${m['barcode'] ?? ''}',
                                            style: expiredOnly
                                                ? t.textTheme.bodySmall
                                                      ?.copyWith(
                                                        color:
                                                            t.colorScheme.error,
                                                      )
                                                : null,
                                          ),
                                          onTap: () {
                                            if (expiredOnly) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'This medicine only has expired batches and cannot be sold.',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            _pickMedicine(m);
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_searchMatches.isEmpty &&
                            _searchCtl.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              branchId == null
                                  ? 'Select a branch to search salable stock.'
                                  : 'No search results found (no in-stock matches at this branch).',
                              style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Visibility(
                      visible: _searchMatches.isEmpty,
                      maintainState: true,
                      maintainSize: true,
                      maintainAnimation: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Quick cart', style: t.textTheme.titleMedium),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                _error!,
                                style: TextStyle(color: t.colorScheme.error),
                              ),
                            ),
                          Expanded(
                            child: _lines.isEmpty
                                ? Align(
                                    alignment: Alignment.topCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Search a medicine to add a line.\nDefault batch = nearest expiry; change below.',
                                        textAlign: TextAlign.center,
                                        style: t.textTheme.bodyMedium?.copyWith(
                                          color: t.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: EdgeInsets.zero,
                                    itemCount: _lines.length,
                                    itemBuilder: (context, i) {
                                      final line = _lines[i];
                                      final qb = _qtyBaseForLine(line);
                                      final up = line.unitPrice;
                                      final lineTotal = qb != null
                                          ? qb * up
                                          : null;
                                      final batchIdForDropdown =
                                          _effectiveBatchIdForLine(line);
                                      final salableBatches = line.batchesWithQty
                                          .where(
                                            (b) => !batchExpiryIsBeforeToday(
                                              b['expiry_date'],
                                            ),
                                          )
                                          .toList();
                                      final batchChoices =
                                          salableBatches.isNotEmpty
                                          ? salableBatches
                                          : line.batchesWithQty;
                                      final selBatch = _selectedBatchMap(line);
                                      final lineBatchExpired =
                                          selBatch != null &&
                                          batchExpiryIsBeforeToday(
                                            selBatch['expiry_date'],
                                          );
                                      return Card(
                                        margin: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                        color: t.colorScheme.surface,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          side: BorderSide(
                                            color: i == _selectedLineIndex
                                                ? t.colorScheme.outline
                                                      .withValues(alpha: 0.55)
                                                : t.colorScheme.outlineVariant
                                                      .withValues(alpha: 0.45),
                                          ),
                                        ),
                                        child: InkWell(
                                          onTap: () => setState(
                                            () => _selectedLineIndex = i,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            line.medicineName,
                                                            style: t
                                                                .textTheme
                                                                .titleSmall,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                          Text(
                                                            line.manualCode,
                                                            style: t
                                                                .textTheme
                                                                .labelSmall,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 90,
                                                      child: Text(
                                                        lineTotal == null
                                                            ? '-'
                                                            : lineTotal
                                                                  .toStringAsFixed(
                                                                    2,
                                                                  ),
                                                        textAlign:
                                                            TextAlign.end,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                      ),
                                                      onPressed: () =>
                                                          _removeLine(i),
                                                    ),
                                                  ],
                                                ),
                                                if (lineBatchExpired) ...[
                                                  const SizedBox(height: 6),
                                                  DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      color: t
                                                          .colorScheme
                                                          .errorContainer,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            8,
                                                          ),
                                                      child: Text(
                                                        'This batch is expired and cannot be sold. Change batch or remove this line.',
                                                        style: t
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: t
                                                                  .colorScheme
                                                                  .onErrorContainer,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: DecoratedBox(
                                                        decoration: BoxDecoration(
                                                          color: t
                                                              .colorScheme
                                                              .surfaceContainerHighest,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                2,
                                                              ),
                                                          border: Border.all(
                                                            color: t
                                                                .colorScheme
                                                                .outlineVariant,
                                                          ),
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 10,
                                                              ),
                                                          child: DropdownButtonHideUnderline(
                                                            child: DropdownButton<String>(
                                                              value:
                                                                  batchIdForDropdown,
                                                              isExpanded: true,
                                                              isDense: true,
                                                              items: batchChoices.map((
                                                                b,
                                                              ) {
                                                                final id =
                                                                    b['id']
                                                                        as String;
                                                                final bn =
                                                                    b['batch_no']
                                                                        as String? ??
                                                                    '';
                                                                final qh =
                                                                    b['qty_on_hand']
                                                                        as num? ??
                                                                    0;
                                                                final exp =
                                                                    batchExpiryIsBeforeToday(
                                                                      b['expiry_date'],
                                                                    );
                                                                return DropdownMenuItem<
                                                                  String
                                                                >(
                                                                  value: id,
                                                                  child: Text(
                                                                    exp
                                                                        ? '$bn ($qh, expired)'
                                                                        : '$bn ($qh)',
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                );
                                                              }).toList(),
                                                              onChanged: (v) {
                                                                if (v == null)
                                                                  return;
                                                                setState(() {
                                                                  line.selectedBatchId = v;
                                                                  if (line.overridePrice == null) {
                                                                    line.priceController.text =
                                                                        line.listPricePerBase.toStringAsFixed(2);
                                                                  }
                                                                });
                                                                _syncDirtyState();
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    IconButton(
                                                      onPressed: () =>
                                                          _adjustQty(line, -1),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      constraints:
                                                          const BoxConstraints(
                                                            minWidth: 32,
                                                            minHeight: 32,
                                                          ),
                                                      icon: const Icon(
                                                        Icons.remove,
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 22,
                                                      child: Text(
                                                        '${line.qtyBase}',
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      onPressed: () =>
                                                          _adjustQty(line, 1),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      constraints:
                                                          const BoxConstraints(
                                                            minWidth: 32,
                                                            minHeight: 32,
                                                          ),
                                                      icon: const Icon(
                                                        Icons.add,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    SizedBox(
                                                      width: 112,
                                                      child: TextField(
                                                        controller: line
                                                            .priceController,
                                                        keyboardType:
                                                            const TextInputType.numberWithOptions(
                                                              decimal: true,
                                                            ),
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText:
                                                                  'Price',
                                                              isDense: true,
                                                              contentPadding:
                                                                  EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical:
                                                                        10,
                                                                  ),
                                                            ),
                                                        onChanged: (value) {
                                                          final parsed =
                                                              num.tryParse(
                                                                value.trim(),
                                                              );
                                                          if (parsed == null)
                                                            return;
                                                          setState(() {
                                                            line.overridePrice =
                                                                (parsed -
                                                                            line.listPricePerBase)
                                                                        .abs() >
                                                                    0.0001
                                                                ? parsed
                                                                : null;
                                                            if (line.overridePrice ==
                                                                null) {
                                                              line.overrideReason =
                                                                  null;
                                                              line.reasonController
                                                                  .clear();
                                                            }
                                                          });
                                                          _syncDirtyState();
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (_showPriceReason(line))
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 8,
                                                        ),
                                                    child: TextField(
                                                      controller:
                                                          line.reasonController,
                                                      decoration: const InputDecoration(
                                                        labelText:
                                                            'Override reason (optional)',
                                                        labelStyle: TextStyle(
                                                          fontSize: 13,
                                                        ),

                                                        helperText:
                                                            'Applies only to this sale line.',
                                                        isDense: true,
                                                        contentPadding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 10,
                                                              vertical: 10,
                                                            ),
                                                      ),
                                                      onChanged: (value) {
                                                        setState(
                                                          () =>
                                                              line.overrideReason =
                                                                  value.trim(),
                                                        );
                                                        _syncDirtyState();
                                                      },
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Material(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Subtotal: ${_cartSubtotal.toStringAsFixed(2)} ETB',
                            textAlign: TextAlign.right,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _discountCtl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Discount (ETB)',
                                    isDense: true,
                                  ),
                                  onChanged: (_) {
                                    setState(() {});
                                    _syncDirtyState();
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Total: ${_cartTotal.toStringAsFixed(2)} ETB',
                                  textAlign: TextAlign.right,
                                  style: t.textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment<String>(
                                value: 'cash',
                                label: Text('Cash'),
                              ),
                              ButtonSegment<String>(
                                value: 'mobile_banking',
                                label: Text('Mobile'),
                              ),
                            ],
                            selected: {_paymentMethod},
                            onSelectionChanged: (selection) {
                              setState(() => _paymentMethod = selection.first);
                              _syncDirtyState();
                            },
                          ),
                          if (_paymentMethod == 'mobile_banking') ...[
                            const SizedBox(height: 6),
                            TextField(
                              controller: _referenceNo,
                              decoration: const InputDecoration(
                                labelText: 'Mobile payment ref (optional)',
                                isDense: true,
                              ),
                              onChanged: (_) => _syncDirtyState(),
                            ),
                          ],
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: (_checkoutLoading || _lines.isEmpty)
                                ? null
                                : _checkout,
                            child: _checkoutLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Finish sale'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
