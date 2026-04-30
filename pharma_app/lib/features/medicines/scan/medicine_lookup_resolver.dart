import 'package:supabase_flutter/supabase_flutter.dart';

enum MedicineLookupState { foundSingle, multipleMatches, notFound }

class MedicineLookupResult {
  const MedicineLookupResult({
    required this.state,
    required this.matches,
    this.query,
  });

  final MedicineLookupState state;
  final List<Map<String, dynamic>> matches;
  final String? query;
}

class MedicineLookupResolver {
  const MedicineLookupResolver();

  int _rank(Map<String, dynamic> row, String q) {
    final name = (row['name'] as String? ?? '').toLowerCase();
    final code = (row['manual_code'] as String? ?? '').toLowerCase();
    final barcode = (row['barcode'] as String? ?? '').toLowerCase();
    final generic = (row['generic_name'] as String? ?? '').toLowerCase();

    if (name == q || code == q || barcode == q) return 0;
    if (name.startsWith(q)) return 1;
    if (code.startsWith(q) || barcode.startsWith(q)) return 2;
    if (generic.startsWith(q)) return 3;
    if (name.contains(q)) return 4;
    if (code.contains(q) || barcode.contains(q)) return 5;
    if (generic.contains(q)) return 6;
    return 99;
  }

  Future<MedicineLookupResult> resolve({
    required String teamId,
    required String branchId,
    required String query,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const MedicineLookupResult(
        state: MedicineLookupState.notFound,
        matches: [],
      );
    }
    final client = Supabase.instance.client;
    final barcodeRows = await client
        .from('medicines')
        .select(
          'id,name,generic_name,manual_code,barcode,selling_price,is_active',
        )
        .eq('team_id', teamId)
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .eq('barcode', q)
        .limit(5);
    final barcodeMatches = List<Map<String, dynamic>>.from(barcodeRows as List);
    if (barcodeMatches.length == 1) {
      return MedicineLookupResult(
        state: MedicineLookupState.foundSingle,
        matches: barcodeMatches,
        query: q,
      );
    }
    if (barcodeMatches.length > 1) {
      return MedicineLookupResult(
        state: MedicineLookupState.multipleMatches,
        matches: barcodeMatches,
        query: q,
      );
    }

    final manualRows = await client
        .from('medicines')
        .select(
          'id,name,generic_name,manual_code,barcode,selling_price,is_active',
        )
        .eq('team_id', teamId)
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .ilike('manual_code', q)
        .limit(5);
    final manualMatches = List<Map<String, dynamic>>.from(manualRows as List);
    if (manualMatches.length == 1) {
      return MedicineLookupResult(
        state: MedicineLookupState.foundSingle,
        matches: manualMatches,
        query: q,
      );
    }
    if (manualMatches.length > 1) {
      return MedicineLookupResult(
        state: MedicineLookupState.multipleMatches,
        matches: manualMatches,
        query: q,
      );
    }

    final like = '%${q.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final fuzzyRows = await client
        .from('medicines')
        .select(
          'id,name,generic_name,manual_code,barcode,selling_price,is_active',
        )
        .eq('team_id', teamId)
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .or(
          'name.ilike.$like,generic_name.ilike.$like,manual_code.ilike.$like,barcode.ilike.$like',
        )
        .limit(20);
    final fuzzyMatches = List<Map<String, dynamic>>.from(fuzzyRows as List)
      ..sort((a, b) {
        final ar = _rank(a, q.toLowerCase());
        final br = _rank(b, q.toLowerCase());
        if (ar != br) return ar.compareTo(br);
        return (a['name'] as String? ?? '').compareTo(
          b['name'] as String? ?? '',
        );
      });
    if (fuzzyMatches.length == 1) {
      return MedicineLookupResult(
        state: MedicineLookupState.foundSingle,
        matches: fuzzyMatches,
        query: q,
      );
    }
    if (fuzzyMatches.isEmpty) {
      return MedicineLookupResult(
        state: MedicineLookupState.notFound,
        matches: const [],
        query: q,
      );
    }
    return MedicineLookupResult(
      state: MedicineLookupState.multipleMatches,
      matches: fuzzyMatches,
      query: q,
    );
  }
}
