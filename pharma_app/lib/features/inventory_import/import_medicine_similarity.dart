import '../../core/medicine/medicine_name_normalizer.dart';

/// Similarity score 0–1000 (higher = better). Used for import matching only.
int scoreMedicineSimilarity(String query, Map<String, dynamic> medicine) {
  final qRaw = query.trim();
  if (qRaw.isEmpty) return 0;

  final barcode = (medicine['barcode'] as String? ?? '').trim();
  final code = (medicine['manual_code'] as String? ?? '').trim();
  if (barcode.isNotEmpty && barcode == qRaw) return 1000;
  if (code.isNotEmpty && code.toLowerCase() == qRaw.toLowerCase()) return 1000;

  final q = normalizeMedicineMatchKey(qRaw);
  if (q.isEmpty) return 0;

  final name = normalizeMedicineMatchKey(medicine['name'] as String? ?? '');
  final generic = normalizeMedicineMatchKey(
    medicine['generic_name'] as String? ?? '',
  );

  var best = 0;
  if (generic.isNotEmpty) {
    best = _scoreField(q, qRaw, generic, medicine['generic_name'] as String? ?? '');
  }
  if (name.isNotEmpty) {
    final n = _scoreField(q, qRaw, name, medicine['name'] as String? ?? '');
    // Brand-only matches score lower — generic-first auto-linking.
    best = best > n - 120 ? best : (n - 120).clamp(0, 1000);
  }
  return best;
}

int _scoreField(
  String qNorm,
  String qRaw,
  String fieldNorm,
  String fieldRaw,
) {
  if (fieldNorm.isEmpty) return 0;
  if (fieldNorm == qNorm) return 950;
  if (fieldRaw.toLowerCase() == qRaw.toLowerCase()) return 950;

  var score = _tokenOverlapScore(qNorm, fieldNorm);

  // Penalize matching a much shorter catalog name inside a longer query
  // (e.g. "OCID" substring issues, or fuzzy hit on abbreviated names).
  if (fieldNorm.length < qNorm.length * 0.55) {
    if (qNorm.contains(fieldNorm) || fieldNorm.contains(qNorm)) {
      score = (score * 0.35).round();
    }
  }
  // Penalize when query is much shorter than catalog name.
  if (qNorm.length < fieldNorm.length * 0.55 && fieldNorm.contains(qNorm)) {
    score = (score * 0.45).round();
  }

  return score.clamp(0, 1000);
}

int _tokenOverlapScore(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final ta = a.split(' ').where((t) => t.length > 1).toSet();
  final tb = b.split(' ').where((t) => t.length > 1).toSet();
  if (ta.isEmpty || tb.isEmpty) {
    return _charOverlapScore(a, b);
  }
  final inter = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return ((inter / union) * 1000).round();
}

int _charOverlapScore(String a, String b) {
  final shorter = a.length < b.length ? a : b;
  final longer = a.length < b.length ? b : a;
  if (shorter.isEmpty) return 0;
  if (longer.contains(shorter)) {
    return ((shorter.length / longer.length) * 700).round();
  }
  return 0;
}

/// Auto-link when top score is high and clearly ahead of the runner-up.
bool shouldAutoLinkSimilarity(List<int> scoresDescending) {
  if (scoresDescending.isEmpty) return false;
  final top = scoresDescending.first;
  if (top < 880) return false;
  if (scoresDescending.length == 1) return true;
  return top - scoresDescending[1] >= 70;
}

/// Several close high scores — user should pick.
bool hasAmbiguousSimilarity(List<int> scoresDescending) {
  if (scoresDescending.length < 2) return false;
  final top = scoresDescending.first;
  if (top < 720) return false;
  return top - scoresDescending[1] < 70;
}

List<Map<String, dynamic>> rankMedicinesBySimilarity(
  List<Map<String, dynamic>> catalog,
  String query, {
  int minScore = 350,
  int limit = 8,
}) {
  final scored = <({Map<String, dynamic> row, int score})>[];
  for (final row in catalog) {
    final score = scoreMedicineSimilarity(query, row);
    if (score >= minScore) {
      scored.add((row: row, score: score));
    }
  }
  scored.sort((a, b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    final ga = a.row['generic_name'] as String? ?? a.row['name'] as String? ?? '';
    final gb = b.row['generic_name'] as String? ?? b.row['name'] as String? ?? '';
    return ga.compareTo(gb);
  });
  return scored.take(limit).map((e) {
    final copy = Map<String, dynamic>.from(e.row);
    copy['_match_score'] = e.score;
    return copy;
  }).toList();
}

/// Parses qty text from invoices (commas, spaces).
num? parseImportQty(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;
  t = t.replaceAll(',', '').replaceAll(' ', '');
  return num.tryParse(t);
}
