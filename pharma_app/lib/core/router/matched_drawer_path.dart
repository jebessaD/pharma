/// Picks the longest [paths] such that [location] equals the path or goes under
/// it (`$path/`). Excludes [excludePath] (e.g. placeholder routes).
String? matchedDrawerPath(
  String location, {
  required List<String> paths,
  String excludePath = '/logout',
}) {
  if (location.isEmpty) return null;
  var best = '';
  for (final p in paths) {
    if (p == excludePath) continue;
    if (p == location && p.length > best.length) {
      best = p;
      continue;
    }
    if (p != location && location.startsWith('$p/') && p.length > best.length) {
      best = p;
    }
  }
  return best.isEmpty ? null : best;
}
