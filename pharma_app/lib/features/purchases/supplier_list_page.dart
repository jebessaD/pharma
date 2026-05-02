import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_error_state.dart';
import '../../core/widgets/form_error_banner.dart';

class SupplierListPage extends ConsumerStatefulWidget {
  const SupplierListPage({super.key});

  @override
  ConsumerState<SupplierListPage> createState() => _SupplierListPageState();
}

class _SupplierListPageState extends ConsumerState<SupplierListPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _openSupplierEdit(String id) async {
    await context.push('/pharmacy/suppliers/$id/edit');
    if (mounted) _load();
  }

  Future<void> _deleteSupplier(Map<String, dynamic> s) async {
    final id = s['id'] as String? ?? '';
    final name = s['name'] as String? ?? 'Supplier';
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete supplier?'),
        content: Text(
          'Remove “$name” from your team? This cannot be undone. '
          'Existing purchases stay in history; their supplier link will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.from('suppliers').delete().eq('id', id);
      await _load();
      if (mounted) AppFeedback.success(context, 'Supplier deleted');
    } catch (e) {
      if (mounted) AppFeedback.error(context, mapFormError(e));
    }
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
          .from('suppliers')
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

  Future<void> _add() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    if (teamId == null) return;
    final name = TextEditingController();
    final phone = TextEditingController();
    var formError = '';
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final screenW = MediaQuery.sizeOf(ctx).width;
        final dialogWidth = (screenW - 48).clamp(420.0, 720.0);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            title: Row(
              children: [
                const Expanded(child: Text('New supplier')),
                IconButton(
                  tooltip: 'Clear fields',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () {
                    name.clear();
                    phone.clear();
                    setDialogState(() => formError = '');
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: name,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: (v) =>
                            FormValidators.requiredText(v, label: 'Name'),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                      if (formError.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        FormErrorBanner(message: formError),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  if (name.text.trim().isEmpty) {
                    setDialogState(() => formError = 'Name is required.');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) {
      name.dispose();
      phone.dispose();
      return;
    }
    try {
      await Supabase.instance.client.from('suppliers').insert({
        'team_id': teamId,
        'name': name.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
      });
      name.dispose();
      phone.dispose();
      await _load();
      if (mounted) AppFeedback.success(context, 'Supplier created');
    } catch (e) {
      name.dispose();
      phone.dispose();
      if (mounted) {
        AppFeedback.error(context, mapFormError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Supplier'),
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
                  ? const Center(child: Text('No suppliers'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: Builder(
                        builder: (context) {
                          final filtered = _rows.where((s) {
                            if (_query.trim().isEmpty) return true;
                            final q = _query.trim().toLowerCase();
                            return ('${s['name'] ?? ''} ${s['phone'] ?? ''}')
                                .toLowerCase()
                                .contains(q);
                          }).toList();
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: TextField(
                                  decoration: const InputDecoration(labelText: 'Search supplier'),
                                  onChanged: (value) => setState(() => _query = value),
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    final s = filtered[i];
                                    final id = s['id'] as String? ?? '';
                                    return ListTile(
                                      title: Text(s['name'] as String? ?? ''),
                                      subtitle: Text(s['phone'] as String? ?? ''),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Delete',
                                            onPressed: () =>
                                                _deleteSupplier(s),
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Edit',
                                            onPressed: () =>
                                                _openSupplierEdit(id),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: () => _openSupplierEdit(id),
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
