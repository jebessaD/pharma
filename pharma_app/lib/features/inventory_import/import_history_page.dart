import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/roles/stock_permissions.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

class ImportHistoryPage extends ConsumerStatefulWidget {
  const ImportHistoryPage({super.key});

  @override
  ConsumerState<ImportHistoryPage> createState() => _ImportHistoryPageState();
}

class _ImportHistoryPageState extends ConsumerState<ImportHistoryPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  String? _undoingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() {
        _loading = false;
        _error = 'Select a branch first.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('inventory_import_batches')
          .select(
            'id, source_kind, source_filename, sheet_name, status, row_count, '
            'created_at, undone_at, undo_error',
          )
          .eq('team_id', teamId)
          .eq('branch_id', branchId)
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _undo(Map<String, dynamic> row) async {
    final role = ref.read(pharmacyProfileProvider).value?['role'] as String?;
    if (!canAddStockInForRole(role)) {
      setState(() => _error = 'Only owners and admins can undo imports.');
      return;
    }
    final id = row['id'] as String?;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo this import?'),
        content: const Text(
          'Stock added by this import will be removed, only if none of it '
          'has been sold. If any units were sold, undo is blocked and you '
          'will see what happened.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Undo'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _undoingId = id;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'undo_inventory_import',
        params: {'p_import_batch_id': id},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import undone.')),
      );
      await _load();
    } on PostgrestException catch (e) {
      final msg = e.message;
      final blocked = msg.contains('import_undo_blocked')
          ? msg.replaceFirst(RegExp(r'^.*import_undo_blocked:\s*'), '')
          : msg;
      if (!mounted) return;
      setState(() {
        _error =
            'Cannot undo this import. $blocked';
        _undoingId = null;
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _undoingId = null;
      });
    } finally {
      if (mounted) setState(() => _undoingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pharmacyPageAppBar(
        context,
        title: 'Import history',
        subtitle: 'Undo mistaken stock imports when safe',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_error != null) ...[
                  FormErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                if (_rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('No imports yet.')),
                  )
                else
                  ..._rows.map((r) {
                    final status = '${r['status'] ?? ''}';
                    final undone = status == 'undone';
                    final filename =
                        (r['source_filename'] as String?)?.trim().isNotEmpty ==
                            true
                        ? r['source_filename'] as String
                        : (r['source_kind'] as String? ?? 'import');
                    final sheet = r['sheet_name'] as String?;
                    final created = (r['created_at'] as String?)?.substring(0, 16) ?? '';
                    final undoError = r['undo_error'] as String?;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(filename),
                        subtitle: Text(
                          [
                            created,
                            '${r['row_count'] ?? 0} row(s)',
                            if (sheet != null && sheet.isNotEmpty) 'Sheet: $sheet',
                            status,
                            if (undoError != null && undoError.isNotEmpty)
                              undoError,
                          ].join(' · '),
                        ),
                        isThreeLine: true,
                        trailing: undone
                            ? const Text('Undone')
                            : TextButton(
                                onPressed: _undoingId == r['id']
                                    ? null
                                    : () => _undo(r),
                                child: _undoingId == r['id']
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Undo'),
                              ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
