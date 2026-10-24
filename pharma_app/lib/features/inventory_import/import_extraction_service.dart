import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'import_error_text.dart';
import 'import_logger.dart';
import 'import_models.dart';

/// A picked image ready to send for extraction.
class PickedImportImage {
  const PickedImportImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

/// Handles image capture and the call to the `inventory-import-extract`
/// Edge Function. No stock is committed here.
class ImportExtractionService {
  ImportExtractionService({ImagePicker? picker, SupabaseClient? client})
    : _picker = picker ?? ImagePicker(),
      _client = client ?? Supabase.instance.client;

  final ImagePicker _picker;
  final SupabaseClient _client;

  static const _maxBytes = 8 * 1024 * 1024;

  /// Overall client-side ceiling. If the round trip (upload + Gemini) exceeds
  /// this, we fail loudly instead of showing an infinite spinner.
  static const _invokeTimeout = Duration(seconds: 150);

  Future<PickedImportImage?> pickImage({required ImageSource source}) async {
    ImportLogger.phase(
      source == ImageSource.camera ? 'Opening camera' : 'Opening gallery',
    );
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 72,
    );
    if (file == null) {
      ImportLogger.info('User cancelled photo picker');
      return null;
    }
    final bytes = await file.readAsBytes();
    final mime = _mimeFor(file.name, file.mimeType);
    ImportLogger.info(
      'Photo picked',
      {
        'name': file.name,
        'mime': mime,
        'bytes': bytes.length,
        'kb': (bytes.length / 1024).round(),
      },
    );
    return PickedImportImage(bytes: bytes, mimeType: mime);
  }

  String _mimeFor(String name, String? reported) {
    if (reported != null && reported.startsWith('image/')) return reported;
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  Future<ExtractionResult> extract({
    required PickedImportImage image,
    required ImportMode mode,
  }) async {
    if (image.bytes.isEmpty) {
      throw const ImportExtractionException('missing_image');
    }
    if (image.bytes.length > _maxBytes) {
      throw const ImportExtractionException('image_too_large');
    }

    final base64Image = base64Encode(image.bytes);
    ImportLogger.info(
      'Calling inventory-import-extract',
      {
        'mode': mode.wire,
        'mime': image.mimeType,
        'imageKb': (image.bytes.length / 1024).round(),
        'payloadKb': (base64Image.length / 1024).round(),
      },
    );

    final sw = Stopwatch()..start();
    try {
      final res = await _client.functions
          .invoke(
            'inventory-import-extract',
            body: {
              'mode': mode.wire,
              'image_base64': base64Image,
              'mime_type': image.mimeType,
            },
          )
          .timeout(
            _invokeTimeout,
            onTimeout: () {
              ImportLogger.error(
                'Invoke timed out (no server response)',
                null,
                {'timeoutSec': _invokeTimeout.inSeconds},
              );
              throw const ImportExtractionException(
                'extract_failed',
                detail: 'timeout',
              );
            },
          );
      sw.stop();

      ImportLogger.info(
        'Edge function responded',
        {
          'status': res.status,
          'elapsedMs': sw.elapsedMilliseconds,
          'body': ImportLogger.summarizeResponseBody(res.data),
        },
      );

      if (res.status >= 400) {
        final ex = FunctionException(status: res.status, details: res.data);
        final bodyMap = res.data is Map ? res.data as Map : null;
        ImportLogger.error('HTTP error from edge function', ex, {
          'status': res.status,
          'body': ImportLogger.summarizeResponseBody(res.data),
          'keysTried': bodyMap?['keys_tried'],
          'failoverTrace': bodyMap?['failover_trace'],
        });
        throw _toImportException(ex);
      }

      try {
        final result = ExtractionResult.parse(res.data);
        ImportLogger.info(
          'Extraction parsed',
          {
            'lines': result.lines.length,
            'supported': result.isSupported,
            'model': result.model,
            'serverMs': result.elapsedMs,
            'warnings': result.documentWarnings.length,
          },
        );
        return result;
      } catch (e) {
        ImportLogger.error('Could not parse success response', e, {
          'body': ImportLogger.summarizeResponseBody(res.data),
          'dataType': res.data.runtimeType.toString(),
        });
        rethrow;
      }
    } on FunctionException catch (e) {
      sw.stop();
      ImportLogger.error('FunctionException from Supabase SDK', e, {
        'status': e.status,
        'details': ImportLogger.summarizeResponseBody(e.details),
        'elapsedMs': sw.elapsedMilliseconds,
      });
      throw _toImportException(e);
    } catch (e) {
      sw.stop();
      ImportLogger.error('Unexpected extraction failure', e, {
        'elapsedMs': sw.elapsedMilliseconds,
      });
      final parsed = importExceptionFromError(e);
      if (parsed != null) throw parsed;
      rethrow;
    }
  }

  Never _toImportException(FunctionException e) {
    final parsed = importExceptionFromError(e);
    if (parsed != null) throw parsed;
    throw ImportExtractionException(
      'extract_failed',
      detail: 'http_${e.status}',
    );
  }
}
