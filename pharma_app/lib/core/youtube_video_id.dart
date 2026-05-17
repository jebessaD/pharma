/// Extracts a YouTube video id from common watch / share / embed URLs.
String? youtubeVideoIdFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;

  final host = uri.host.toLowerCase();
  if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
    if (uri.pathSegments.isEmpty) return null;
    final id = uri.pathSegments.first.trim();
    return id.isEmpty ? null : id;
  }

  if (!host.contains('youtube')) return null;

  final v = uri.queryParameters['v']?.trim();
  if (v != null && v.isNotEmpty) return v;

  final segments = uri.pathSegments;
  if (segments.length >= 2) {
    final kind = segments[0].toLowerCase();
    if (kind == 'embed' || kind == 'shorts' || kind == 'live') {
      final id = segments[1].trim();
      return id.isEmpty ? null : id;
    }
  }

  return null;
}
