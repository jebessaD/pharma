// Web-only: blob download when share sheet is unavailable.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

String _safeReceiptFileName(String saleId) {
  final safe = saleId.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '_');
  return 'receipt_${safe.isEmpty ? 'sale' : safe}.png';
}

void _triggerDownload(String saleId, Uint8List pngBytes) {
  final name = _safeReceiptFileName(saleId);
  final blob = html.Blob([pngBytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(const Duration(seconds: 1), () {
    html.Url.revokeObjectUrl(url);
  });
}

Future<void> shareReceiptPngBytes(String saleId, Uint8List pngBytes) async {
  try {
    await Share.shareXFiles([
      XFile.fromData(
        pngBytes,
        name: 'receipt_$saleId.png',
        mimeType: 'image/png',
      ),
    ], subject: 'Pharmacy receipt');
  } catch (_) {
    _triggerDownload(saleId, pngBytes);
  }
}

void runWebReceiptSave(String saleId, Uint8List pngBytes) {
  _triggerDownload(saleId, pngBytes);
}

/// After async work, the browser blocks auto-download — caller shows SnackBar
/// with [runWebReceiptSave] on "Save".
Future<({bool ok, bool webSaveTap, String? message})> saveReceiptPngToDevice(
  String saleId,
  Uint8List pngBytes,
) async {
  return (ok: true, webSaveTap: true, message: null);
}
