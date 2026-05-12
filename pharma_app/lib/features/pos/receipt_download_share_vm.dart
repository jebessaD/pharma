import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareReceiptPngBytes(String saleId, Uint8List pngBytes) async {
  await Share.shareXFiles([
    XFile.fromData(
      pngBytes,
      name: 'receipt_$saleId.png',
      mimeType: 'image/png',
    ),
  ], subject: 'Pharmacy receipt');
}

void runWebReceiptSave(String saleId, Uint8List pngBytes) {}

const _receiptAlbum = 'Pharma Shelf';

enum _GalleryAttempt { saved, permissionDenied, useFileFallback }

Future<({ _GalleryAttempt attempt, String? message})> _trySaveReceiptToGallery(
  Uint8List pngBytes,
  String baseName,
) async {
  if (Platform.isLinux) {
    return (attempt: _GalleryAttempt.useFileFallback, message: null);
  }
  const deniedMsg =
      'Photo access was denied. Allow Photos access in Settings to save '
      'receipts to your gallery, or use Share to send the image.';

  try {
    final granted = await Gal.requestAccess(toAlbum: true);
    if (!granted) {
      return (
        attempt: _GalleryAttempt.permissionDenied,
        message: deniedMsg,
      );
    }
    await Gal.putImageBytes(
      pngBytes,
      album: _receiptAlbum,
      name: baseName,
    );
    return (
      attempt: _GalleryAttempt.saved,
      message:
          'Receipt saved to your gallery (album "$_receiptAlbum"). Open Photos to view it.',
    );
  } on GalException catch (e) {
    if (e.type == GalExceptionType.accessDenied) {
      return (
        attempt: _GalleryAttempt.permissionDenied,
        message: deniedMsg,
      );
    }
    return (attempt: _GalleryAttempt.useFileFallback, message: null);
  } catch (_) {
    return (attempt: _GalleryAttempt.useFileFallback, message: null);
  }
}

Future<({bool ok, bool webSaveTap, String? message})> saveReceiptPngToDevice(
  String saleId,
  Uint8List pngBytes,
) async {
  final safe = saleId.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '');
  final baseName = 'receipt_${safe.isEmpty ? 'sale' : safe}';
  final fileName = '$baseName.png';

  Future<bool> tryWrite(Directory dir) async {
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(pngBytes, flush: true);
    return true;
  }

  final gallery = await _trySaveReceiptToGallery(pngBytes, baseName);
  switch (gallery.attempt) {
    case _GalleryAttempt.saved:
      return (
        ok: true,
        webSaveTap: false,
        message: gallery.message,
      );
    case _GalleryAttempt.permissionDenied:
      return (
        ok: false,
        webSaveTap: false,
        message: gallery.message,
      );
    case _GalleryAttempt.useFileFallback:
      break;
  }

  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null && await tryWrite(downloads)) {
      return (
        ok: true,
        webSaveTap: false,
        message: 'Receipt saved: $fileName (Downloads — may not appear in Photos).',
      );
    }
  } catch (_) {}
  try {
    if (await tryWrite(await getTemporaryDirectory())) {
      return (
        ok: true,
        webSaveTap: false,
        message: 'Receipt saved: $fileName (app cache — open Files app if needed).',
      );
    }
  } catch (_) {}
  try {
    if (await tryWrite(await getApplicationDocumentsDirectory())) {
      return (
        ok: true,
        webSaveTap: false,
        message: 'Receipt saved: $fileName (app Documents — not shown in gallery).',
      );
    }
  } catch (_) {}
  return (ok: false, webSaveTap: false, message: null);
}
