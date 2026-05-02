/// RFC 4180-style single CSV field: quote and escape when needed.
String csvEscapeField(Object? value) {
  var s = '${value ?? ''}';
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final needsQuotes = s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.startsWith(' ') ||
      s.endsWith(' ');
  if (!needsQuotes) return s;
  return '"${s.replaceAll('"', '""')}"';
}
