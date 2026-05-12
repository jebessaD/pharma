import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'receipt_download_share_vm.dart'
    if (dart.library.html) 'receipt_download_share_web.dart'
    as impl;

/// Result of [saveReceiptPngToDevice].
/// When [webSaveTap] is true, the browser needs a fresh user gesture — show a
/// SnackBar whose action calls [runWebReceiptSave].
typedef ReceiptSaveResult = ({
  bool ok,
  bool webSaveTap,
  String? message,
});

/// Opens the system share sheet with a PNG receipt (mobile / desktop).
Future<void> shareReceiptPngBytes(String saleId, Uint8List pngBytes) {
  return impl.shareReceiptPngBytes(saleId, pngBytes);
}

/// Saves the PNG on disk (native) or returns [webSaveTap] so the UI can run
/// [runWebReceiptSave] from a SnackBar action (web).
Future<ReceiptSaveResult> saveReceiptPngToDevice(
  String saleId,
  Uint8List pngBytes,
) {
  return impl.saveReceiptPngToDevice(saleId, pngBytes);
}

/// Web only: must run synchronously from a user tap (e.g. SnackBar "Save").
void runWebReceiptSave(String saleId, Uint8List pngBytes) {
  impl.runWebReceiptSave(saleId, pngBytes);
}

void showReceiptSaveFeedback(
  BuildContext context,
  String saleId,
  Uint8List pngBytes,
  ReceiptSaveResult result,
) {
  if (!result.ok) {
    final m = result.message?.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          m == null || m.isEmpty ? 'Could not save receipt image.' : m,
        ),
      ),
    );
    return;
  }
  if (result.webSaveTap) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Tap Save to download your receipt (browser security).',
        ),
        action: SnackBarAction(
          label: 'Save',
          onPressed: () => runWebReceiptSave(saleId, pngBytes),
        ),
        duration: const Duration(seconds: 25),
      ),
    );
    return;
  }
  final msg = result.message;
  if (msg != null && msg.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Receipt saved.')),
    );
  }
}
