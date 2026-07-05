import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/medicine_category_catalog.dart';
import '../../core/layout/layout_density.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/pharmacy_redirect_cache_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/pharmacy_hub_list.dart';

class MedicineListPage extends ConsumerStatefulWidget {
  const MedicineListPage({super.key});

  @override
  ConsumerState<MedicineListPage> createState() => _MedicineListPageState();
}

class _MedicineListPageState extends ConsumerState<MedicineListPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _query = '';

  final Set<String> _selectedCategoryKeys = <String>{};
  String? _lastBranchId;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _openNewMedicine() async {
    final branchId = ref.read(selectedBranchIdProvider);
    if (branchId == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Select a branch first.')));
      }
      return;
    }
    await context.push('/pharmacy/medicines/new');
    if (mounted) _load();
  }

  Future<void> _openMedicineDetail(String id) async {
    await context.push('/pharmacy/medicines/$id');
    if (mounted) _load();
  }

  Future<void> _load() async {
    final profile = await ref.read(pharmacyProfileProvider.future);
    final teamId = profile?['team_id'] as String?;
    if (!mounted) return;
    if (teamId == null) {
      setState(() {
        _loading = false;
        _error = 'No team';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branchId = ref.read(selectedBranchIdProvider);
      if (branchId == null) {
        setState(() {
          _rows = const [];
        });
        return;
      }
      final data = await Supabase.instance.client
          .from('medicines')
          .select(
            'id, name, generic_name, manual_code, category_key',
          )
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .order('name');
      final rows = List<Map<String, dynamic>>.from(data as List);
      setState(() {
        _rows = rows;
      });
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCategoryFilterSheet(
    List<Map<String, dynamic>> categories,
  ) async {
    final result = await showPharmacyCategoryFilterSheet(
      context,
      selected: _selectedCategoryKeys,
      categories: categories,
    );
    if (result != null && mounted) {
      setState(() {
        _selectedCategoryKeys
          ..clear()
          ..addAll(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(activeBranchMedicineCategoriesProvider);
    final gate = ref.watch(pharmacyRedirectCacheProvider);
    final isPharmacist = gate?.role == 'pharmacist';
    final cs = Theme.of(context).colorScheme;
    final branchId = ref.watch(selectedBranchIdProvider);
    if (_lastBranchId != branchId) {
      _lastBranchId = branchId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(_selectedCategoryKeys.clear);
        _load();
      });
    }
    return Scaffold(
      floatingActionButton: isPharmacist
          ? null
          : FloatingActionButton.extended(
              onPressed: _openNewMedicine,
              icon: const Icon(Icons.add),
              label: const Text('Medicine'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? AppErrorState(
              message: _error!,
              onRetry: () {
                _load();
              },
            )
          : _rows.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.medication_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  const Text('No medicines yet'),
                  const SizedBox(height: 8),
                  Text(
                    isPharmacist
                        ? 'Ask a team owner or admin to add medicines to this branch.'
                        : 'Add your first medicine with the + button below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: Builder(
                builder: (context) {
                  final filtered = _rows
                      .where((m) {
                        if (_query.trim().isEmpty) return true;
                        final q = _query.trim().toLowerCase();
                        final category = medicineCategoryLabel(
                          m['category_key'] as String?,
                        );
                        return ('${m['name'] ?? ''} ${m['manual_code'] ?? ''} ${m['generic_name'] ?? ''} $category')
                            .toLowerCase()
                            .contains(q);
                      })
                      .where((m) {
                        if (_selectedCategoryKeys.isEmpty) return true;
                        final key = m['category_key'] as String?;
                        return key != null && _selectedCategoryKeys.contains(key);
                      })
                      .toList();
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (branchId == null)
                              Padding(
                                padding: pharmacyHubFilterPadding(context)
                                    .copyWith(bottom: 0),
                                child: Text(
                                  'Select a branch in the menu to load medicines.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            PharmacyHubFilterSection(
                              searchHint: 'Search medicine',
                              onSearchChanged: (value) =>
                                  setState(() => _query = value),
                              countLabel:
                                  'Showing ${filtered.length} of ${_rows.length}',
                              categorySelectedCount:
                                  _selectedCategoryKeys.length,
                              onPickCategories: categoriesAsync.maybeWhen(
                                data: (categories) {
                                  final list = categories
                                      .map((c) => Map<String, dynamic>.from(c))
                                      .toList();
                                  return () =>
                                      _openCategoryFilterSheet(list);
                                },
                                orElse: () => null,
                              ),
                              beforeCount: categoriesAsync.maybeWhen(
                                loading: () => const LinearProgressIndicator(),
                                error: (_, __) =>
                                    const Text('Category filter unavailable'),
                                orElse: () => null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _query.trim().isNotEmpty
                                    ? 'No search results found'
                                    : 'No medicines match',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: pharmacyHubListPadding(context),
                          sliver: SliverList.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final m = filtered[i];
                              final id = m['id'] as String;
                              final category = medicineCategoryLabel(
                                m['category_key'] as String?,
                              );
                              return PharmacyHubListRow(
                                icon: Icons.medication_outlined,
                                title: m['name'] as String? ?? '',
                                subtitle: [
                                  if ((m['manual_code'] as String? ?? '')
                                      .isNotEmpty)
                                    m['manual_code'],
                                  if ((m['generic_name'] as String? ?? '')
                                      .isNotEmpty)
                                    m['generic_name'],
                                  if (category.isNotEmpty) category,
                                ].join(' · '),
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  size: context.layoutDensity.listIconSize,
                                  color: cs.onSurfaceVariant,
                                ),
                                onTap: () => _openMedicineDetail(id),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}
