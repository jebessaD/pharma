import 'package:supabase_flutter/supabase_flutter.dart';

import 'import_medicine_similarity.dart';
import 'import_models.dart';

/// Outcome of matching one extracted line to the medicine catalog.
enum MatchOutcome {
  /// Exactly one confident match.
  single,

  /// Several plausible matches; user must choose.
  multiple,

  /// No catalog match; likely a new medicine.
  none,
}

class MedicineMatch {
  const MedicineMatch({
    required this.outcome,
    required this.candidates,
    this.query,
  });

  final MatchOutcome outcome;
  final List<Map<String, dynamic>> candidates;
  final String? query;

  Map<String, dynamic>? get best =>
      candidates.isEmpty ? null : candidates.first;
}

/// Resolves extracted lines to catalog medicines.
/// Auto-link: exact barcode/code/name, or high similarity score with clear lead.
class ImportMedicineMatcher {
  ImportMedicineMatcher({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  List<Map<String, dynamic>>? _catalogCache;
  String? _catalogTeamId;
  String? _catalogBranchId;

  static const _medicineSelect =
      'id,name,generic_name,manual_code,barcode,purchase_price,selling_price,'
      'is_active,subcategory,country,presentation,strength,dosage_form';

  /// Loads branch catalog once and reuses for batch matching.
  Future<List<Map<String, dynamic>>> loadCatalog({
    required String teamId,
    required String branchId,
  }) async {
    if (_catalogCache != null &&
        _catalogTeamId == teamId &&
        _catalogBranchId == branchId) {
      return _catalogCache!;
    }
    final rows = await _client
        .from('medicines')
        .select(_medicineSelect)
        .eq('team_id', teamId)
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('name');
    _catalogCache = List<Map<String, dynamic>>.from(rows as List);
    _catalogTeamId = teamId;
    _catalogBranchId = branchId;
    return _catalogCache!;
  }

  void clearCatalogCache() {
    _catalogCache = null;
    _catalogTeamId = null;
    _catalogBranchId = null;
  }

  Future<MedicineMatch> match({
    required String teamId,
    required String branchId,
    required ExtractedLine line,
    List<Map<String, dynamic>>? catalog,
  }) async {
    final meds = catalog ?? await loadCatalog(teamId: teamId, branchId: branchId);

    final barcode = line.barcode?.trim();
    if (barcode != null && barcode.isNotEmpty) {
      final hits = meds
          .where((r) => (r['barcode'] as String? ?? '').trim() == barcode)
          .toList();
      final match = _exactSingle(hits, 'Barcode match');
      if (match != null) return match;
    }

    final code = line.resolvedManualCode?.trim();
    if (code != null && code.isNotEmpty) {
      final hits = meds
          .where(
            (r) =>
                (r['manual_code'] as String? ?? '').toLowerCase() ==
                code.toLowerCase(),
          )
          .toList();
      final match = _exactSingle(hits, 'Manual code match');
      if (match != null) return match;
    }

    final name = line.resolvedName?.trim();
    if (name != null && name.isNotEmpty) {
      final exact = meds
          .where(
            (r) =>
                (r['name'] as String? ?? '').toLowerCase() == name.toLowerCase(),
          )
          .toList();
      final match = _exactSingle(exact, 'Exact name match');
      if (match != null) return match;

      return _similarityMatch(name, meds);
    }

    return const MedicineMatch(outcome: MatchOutcome.none, candidates: []);
  }

  MedicineMatch _similarityMatch(
    String name,
    List<Map<String, dynamic>> catalog,
  ) {
    final ranked = rankMedicinesBySimilarity(catalog, name, minScore: 350, limit: 8);
    if (ranked.isEmpty) {
      return MedicineMatch(outcome: MatchOutcome.none, candidates: [], query: name);
    }

    final scores = ranked
        .map((m) => m['_match_score'] as int? ?? scoreMedicineSimilarity(name, m))
        .toList();

    if (shouldAutoLinkSimilarity(scores)) {
      final row = Map<String, dynamic>.from(ranked.first);
      row['_match_reason'] = 'Best match (${_scoreLabel(scores.first)})';
      return MedicineMatch(
        outcome: MatchOutcome.single,
        candidates: [row],
        query: name,
      );
    }

    if (hasAmbiguousSimilarity(scores)) {
      final candidates = ranked
          .take(5)
          .map((m) {
            final copy = Map<String, dynamic>.from(m);
            final s = copy['_match_score'] as int? ?? 0;
            copy['_match_reason'] = 'Similar (${_scoreLabel(s)})';
            return copy;
          })
          .toList();
      return MedicineMatch(
        outcome: MatchOutcome.multiple,
        candidates: candidates,
        query: name,
      );
    }

    final suggestions = ranked.map((m) {
      final copy = Map<String, dynamic>.from(m);
      final s = copy['_match_score'] as int? ?? 0;
      copy['_match_reason'] = 'Similar (${_scoreLabel(s)})';
      return copy;
    }).toList();

    return MedicineMatch(
      outcome: MatchOutcome.none,
      candidates: suggestions,
      query: name,
    );
  }

  String _scoreLabel(int score) => '${(score / 10).round()}%';

  MedicineMatch? _exactSingle(
    List<Map<String, dynamic>> rows,
    String reason,
  ) {
    if (rows.length != 1) return null;
    final row = Map<String, dynamic>.from(rows.first);
    row['_match_reason'] = reason;
    row['_match_score'] = 1000;
    return MedicineMatch(
      outcome: MatchOutcome.single,
      candidates: [row],
    );
  }

  /// Creates a new catalog medicine from review-row values and returns its id.
  Future<String> createMedicine({
    required String teamId,
    required String branchId,
    required String name,
    String? genericName,
    String? manualCode,
    String? barcode,
    String categoryKey = 'medicine',
    String? subcategory,
    String? country,
    String? presentation,
    String? strength,
    String? dosageForm,
    num purchasePrice = 0,
    num sellingPrice = 0,
    num reorderLevel = 0,
  }) async {
    String? clean(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final inserted = await _client
        .from('medicines')
        .insert({
          'team_id': teamId,
          'branch_id': branchId,
          'name': name.trim(),
          'generic_name': clean(genericName),
          'manual_code': clean(manualCode),
          'barcode': clean(barcode),
          'category_key': categoryKey,
          'subcategory': clean(subcategory),
          'country': clean(country),
          'presentation': clean(presentation),
          'strength': clean(strength),
          'dosage_form': clean(dosageForm),
          'purchase_price': purchasePrice,
          'selling_price': sellingPrice,
          'reorder_level': reorderLevel,
        })
        .select(
          'id, name, manual_code, barcode, generic_name, '
          'purchase_price, selling_price, subcategory, country, '
          'presentation, strength, dosage_form',
        )
        .single();
    return inserted['id'] as String;
  }
}
