import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/medicine_categories_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/widgets/app_error_state.dart';

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

  String? _categoryFilterId;
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
            'id, name, generic_name, manual_code, category_id, medicine_categories(name)',
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

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(activeBranchMedicineCategoriesProvider);
    final cs = Theme.of(context).colorScheme;
    final branchId = ref.watch(selectedBranchIdProvider);
    if (_lastBranchId != branchId) {
      _lastBranchId = branchId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _categoryFilterId = null);
        _load();
      });
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
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
                    'Add your first medicine with the + button below.',
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
                        final category =
                            (m['medicine_categories']
                                as Map<String, dynamic>?)?['name'] ??
                            '';
                        return ('${m['name'] ?? ''} ${m['manual_code'] ?? ''} ${m['generic_name'] ?? ''} $category')
                            .toLowerCase()
                            .contains(q);
                      })
                      .where((m) {
                        if (_categoryFilterId == null ||
                            _categoryFilterId!.isEmpty) {
                          return true;
                        }
                        return m['category_id'] == _categoryFilterId;
                      })
                      .toList();
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (branchId == null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    'Select a branch in the menu to load medicines.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ),
                              TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search medicine',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  filled: true,
                                  fillColor: cs.surfaceContainerHighest
                                      .withValues(alpha: 0.25),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: cs.outlineVariant,
                                    ),
                                  ),
                                ),
                                onChanged: (value) =>
                                    setState(() => _query = value),
                              ),
                              const SizedBox(height: 8),
                              categoriesAsync.when(
                                data: (categories) =>
                                    DropdownButtonFormField<String>(
                                      initialValue: _categoryFilterId ?? '',
                                      decoration: InputDecoration(
                                        labelText: 'Category',
                                        filled: true,
                                        fillColor: cs.surfaceContainerHighest
                                            .withValues(alpha: 0.2),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: cs.outlineVariant,
                                          ),
                                        ),
                                      ),
                                      items: [
                                        const DropdownMenuItem<String>(
                                          value: '',
                                          child: Text('All categories'),
                                        ),
                                        ...categories.map(
                                          (c) => DropdownMenuItem<String>(
                                            value: c['id'] as String,
                                            child: Text(
                                              c['name'] as String? ?? '',
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (value) => setState(
                                        () => _categoryFilterId =
                                            (value == null || value.isEmpty)
                                            ? null
                                            : value,
                                      ),
                                    ),
                                loading: () => const LinearProgressIndicator(),
                                error: (error, stackTrace) =>
                                    const Text('Category filter unavailable'),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Showing ${filtered.length} of ${_rows.length}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
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
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          sliver: SliverList.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final m = filtered[i];
                              final id = m['id'] as String;
                              final category =
                                  (m['medicine_categories']
                                      as Map<String, dynamic>?)?['name'];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                child: ListTile(
                                  title: Text(
                                    m['name'] as String? ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    [
                                      '${m['manual_code'] ?? ''} · ${m['generic_name'] ?? ''}',
                                    ].join('\n'),
                                  ),
                                  leading: const Icon(Icons.medication_outlined),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if ((category as String?)?.isNotEmpty == true)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cs.secondaryContainer,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            category!,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: cs.onSecondaryContainer,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                  onTap: () => _openMedicineDetail(id),
                                ),
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
