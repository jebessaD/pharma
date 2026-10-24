import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'csv_parser.dart';
import 'spreadsheet_models.dart';

/// Minimal XLSX reader (shared strings + sheet rows) without the excel package.
SpreadsheetWorkbook parseXlsxBytes({
  required Uint8List bytes,
  required String filename,
}) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final shared = _readSharedStrings(archive);
  final sheetEntries = archive.files
      .where(
        (f) =>
            f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'),
      )
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  final names = _readSheetNames(archive);
  final sheets = <SpreadsheetTable>[];
  for (var i = 0; i < sheetEntries.length; i++) {
    final entry = sheetEntries[i];
    final content = entry.content as List<int>;
    final xml = utf8.decode(content, allowMalformed: true);
    final name = i < names.length ? names[i] : 'Sheet ${i + 1}';
    sheets.add(_parseSheetXml(xml, shared, name));
  }

  if (sheets.isEmpty) {
    throw const FormatException('No worksheets found in this Excel file.');
  }

  return SpreadsheetWorkbook(filename: filename, kind: 'xlsx', sheets: sheets);
}

SpreadsheetWorkbook parseCsvBytes({
  required Uint8List bytes,
  required String filename,
}) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final table = parseCsvTable(text: text, sheetName: 'Sheet1');
  return SpreadsheetWorkbook(filename: filename, kind: 'csv', sheets: [table]);
}

List<String> _readSharedStrings(Archive archive) {
  final file = archive.findFile('xl/sharedStrings.xml');
  if (file == null) return const [];
  final xml = XmlDocument.parse(
    utf8.decode(file.content as List<int>, allowMalformed: true),
  );
  final out = <String>[];
  for (final si in xml.findAllElements('si')) {
    final texts = si.findAllElements('t').map((t) => t.innerText).join();
    out.add(texts);
  }
  return out;
}

List<String> _readSheetNames(Archive archive) {
  final file = archive.findFile('xl/workbook.xml');
  if (file == null) return const [];
  final xml = XmlDocument.parse(
    utf8.decode(file.content as List<int>, allowMalformed: true),
  );
  return xml
      .findAllElements('sheet')
      .map((s) => s.getAttribute('name') ?? 'Sheet')
      .toList();
}

SpreadsheetTable _parseSheetXml(
  String xmlText,
  List<String> shared,
  String name,
) {
  final doc = XmlDocument.parse(xmlText);
  final rowMap = <int, Map<int, String>>{};
  var maxCol = 0;

  for (final row in doc.findAllElements('row')) {
    final rowIndex = int.tryParse(row.getAttribute('r') ?? '') ?? 0;
    if (rowIndex <= 0) continue;
    final cells = <int, String>{};
    for (final c in row.findAllElements('c')) {
      final ref = c.getAttribute('r') ?? '';
      final col = _colIndexFromRef(ref);
      if (col <= 0) continue;
      maxCol = maxCol < col ? col : maxCol;
      final type = c.getAttribute('t');
      final v = c.getElement('v')?.innerText ?? '';
      final inlineStr = c.getElement('is');
      String value;
      if (type == 's') {
        final idx = int.tryParse(v) ?? -1;
        value = (idx >= 0 && idx < shared.length) ? shared[idx] : '';
      } else if (type == 'inlineStr' && inlineStr != null) {
        value = inlineStr.findAllElements('t').map((t) => t.innerText).join();
      } else {
        value = v;
      }
      cells[col] = value.trim();
    }
    if (cells.isNotEmpty) rowMap[rowIndex] = cells;
  }

  if (rowMap.isEmpty) {
    return SpreadsheetTable(name: name, headers: const [], rows: const []);
  }

  final sortedRows = rowMap.keys.toList()..sort();
  final headerRowIndex = sortedRows.first;
  final headerCells = rowMap[headerRowIndex] ?? {};
  final headers = List<String>.generate(
    maxCol,
    (i) => (headerCells[i + 1] ?? '').trim(),
  );

  // Drop trailing empty headers.
  while (headers.isNotEmpty && headers.last.isEmpty) {
    headers.removeLast();
  }

  final rows = <List<String>>[];
  for (final r in sortedRows.skip(1)) {
    final cells = rowMap[r] ?? {};
    final row = List<String>.generate(
      headers.length,
      (i) => (cells[i + 1] ?? '').trim(),
    );
    if (row.every((c) => c.isEmpty)) continue;
    rows.add(row);
  }

  return SpreadsheetTable(name: name, headers: headers, rows: rows);
}

int _colIndexFromRef(String ref) {
  final letters = RegExp(r'^[A-Z]+').firstMatch(ref.toUpperCase())?.group(0);
  if (letters == null || letters.isEmpty) return 0;
  var n = 0;
  for (final code in letters.codeUnits) {
    n = n * 26 + (code - 64);
  }
  return n;
}
