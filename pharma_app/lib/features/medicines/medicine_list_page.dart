import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
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

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _openNewMedicine() async {
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
      final data = await Supabase.instance.client
          .from('medicines')
          .select()
          .eq('team_id', teamId)
          .order('name');
      setState(() => _rows = List<Map<String, dynamic>>.from(data as List));
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                          final filtered = _rows.where((m) {
                            if (_query.trim().isEmpty) return true;
                            final q = _query.trim().toLowerCase();
                            return ('${m['name'] ?? ''} ${m['manual_code'] ?? ''} ${m['generic_name'] ?? ''}')
                                .toLowerCase()
                                .contains(q);
                          }).toList();
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: TextField(
                                  decoration: const InputDecoration(labelText: 'Search name/code/generic'),
                                  onChanged: (value) => setState(() => _query = value),
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    final m = filtered[i];
                                    final id = m['id'] as String;
                                    return ListTile(
                                      title: Text(m['name'] as String? ?? ''),
                                      subtitle: Text(
                                        '${m['manual_code'] ?? ''} · ${m['generic_name'] ?? ''}',
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
