import 'spreadsheet_models.dart';

/// RFC4180-ish CSV parse with delimiter auto-detect on the header line.
SpreadsheetTable parseCsvTable({
  required String text,
  required String sheetName,
}) {
  final normalized = text.replaceFirst(RegExp(r'^\uFEFF'), '');
  final lines = _splitCsvRecords(normalized);
  if (lines.isEmpty) {
    return SpreadsheetTable(name: sheetName, headers: const [], rows: const []);
  }

  final delimiter = _detectDelimiter(lines.first);
  final matrix = lines.map((line) => _parseCsvLine(line, delimiter)).toList();
  final headers = matrix.first.map((h) => h.trim()).toList();
  final rows = <List<String>>[];
  for (var i = 1; i < matrix.length; i++) {
    final raw = matrix[i];
    if (raw.every((c) => c.trim().isEmpty)) continue;
    final padded = List<String>.generate(
      headers.length,
      (j) => j < raw.length ? raw[j].trim() : '',
    );
    rows.add(padded);
  }
  return SpreadsheetTable(name: sheetName, headers: headers, rows: rows);
}

String _detectDelimiter(String headerLine) {
  final comma = ','.allMatches(headerLine).length;
  final semi = ';'.allMatches(headerLine).length;
  final tab = '\t'.allMatches(headerLine).length;
  if (tab >= comma && tab >= semi && tab > 0) return '\t';
  if (semi > comma) return ';';
  return ',';
}

List<String> _splitCsvRecords(String text) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < text.length && text[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (!inQuotes && (ch == '\n' || ch == '\r')) {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      out.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out.where((l) => l.trim().isNotEmpty || l.contains(',')).toList();
}

List<String> _parseCsvLine(String line, String delimiter) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (!inQuotes && ch == delimiter) {
      out.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  out.add(buf.toString());
  return out;
}
