import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'import_logger.dart';
import 'import_models.dart';

/// Maps import/extraction error codes to friendly, actionable messages.
String importErrorText(Object error) {
  final extracted = importExceptionFromError(error);
  if (extracted != null) {
    final message = _messageForCode(
      extracted.code,
      extracted.detail,
      keysTried: extracted.keysTried,
      failoverAttempts: extracted.failoverAttempts,
    );
    ImportLogger.warn(
      'User-facing error',
      {
        'code': extracted.code,
        'detail': extracted.detail,
        'message': message,
        'raw': error.toString(),
      },
    );
    return message;
  }

  final text = error.toString().toLowerCase();
  ImportLogger.error('Unmapped import error', error);

  if (text.contains('socket') ||
      text.contains('network') ||
      text.contains('failed host lookup') ||
      text.contains('timed out') ||
      text.contains('timeout') ||
      text.contains('connection') ||
      text.contains('clientexception')) {
    return 'No internet connection or the request timed out. Check your network and try again.';
  }
  if (text.contains('functionexception') && text.contains('404')) {
    return 'Photo import service is not deployed yet. Ask your administrator to deploy inventory-import-extract on Supabase.';
  }
  return 'Could not read the photo. Check the terminal for [PhotoImport] logs, then try again with a clearer picture.';
}

/// Pulls a structured [ImportExtractionException] from any thrown error.
ImportExtractionException? importExceptionFromError(
  Object error, {
  int? status,
}) {
  if (error is ImportExtractionException) return error;
  if (error is FunctionException) {
    return _exceptionFromPayload(
      error.details,
      status: error.status,
    );
  }
  final recovered = _functionExceptionFromToString(error.toString());
  if (recovered != null) {
    return _exceptionFromPayload(
      recovered.details,
      status: recovered.status,
    );
  }
  return _exceptionFromPayload(error, status: status);
}

/// Parses [FunctionException.toString] when the SDK wraps the failure.
FunctionException? _functionExceptionFromToString(String raw) {
  if (!raw.contains('FunctionException')) return null;
  final re = RegExp(
    r'FunctionException\(status:\s*(\d+),\s*details:\s*(.*?),\s*reasonPhrase:',
    dotAll: true,
  );
  final m = re.firstMatch(raw);
  if (m == null) return null;
  final status = int.tryParse(m.group(1) ?? '') ?? 500;
  final detailsRaw = m.group(2);
  if (detailsRaw == null) {
    return FunctionException(status: status, details: '');
  }
  return FunctionException(status: status, details: detailsRaw);
}

ImportExtractionException? _exceptionFromPayload(
  Object? payload, {
  int? status,
}) {
  final map = _asErrorMap(payload);
  if (map != null) {
    final code = map['error'] ?? map['code'] ?? map['message'];
    if (code != null) {
      final codeStr = code.toString().trim();
      if (codeStr.isNotEmpty && codeStr != '{}') {
        return ImportExtractionException(
          _normalizeErrorCode(codeStr),
          detail: _detailFromMap(map),
          keysTried: _intFromMap(map, 'keys_tried'),
          failoverAttempts: _failoverAttemptCount(map),
        );
      }
    }
  }

  if (status != null) {
    return switch (status) {
      401 => const ImportExtractionException('unauthorized'),
      403 => const ImportExtractionException('forbidden'),
      404 => const ImportExtractionException(
        'extract_not_configured',
        detail: 'function_not_found',
      ),
      413 => const ImportExtractionException('image_too_large'),
      415 => const ImportExtractionException('unsupported_mime'),
      429 => const ImportExtractionException('quota_exceeded'),
      502 || 503 => const ImportExtractionException('extract_provider_error'),
      422 => _exceptionFrom422Payload(map),
      500 => const ImportExtractionException('extract_not_configured'),
      504 || 546 => const ImportExtractionException(
        'extract_failed',
        detail: 'timeout',
      ),
      _ => ImportExtractionException('extract_failed', detail: 'http_$status'),
    };
  }

  if (payload is String) {
    final lower = payload.trim().toLowerCase();
    if (lower == 'unauthorized') {
      return const ImportExtractionException('unauthorized');
    }
    if (lower == 'forbidden') {
      return const ImportExtractionException('forbidden');
    }
    if (lower.contains('not found') || lower.contains('404')) {
      return const ImportExtractionException(
        'extract_not_configured',
        detail: 'function_not_found',
      );
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return const ImportExtractionException('extract_failed', detail: 'timeout');
    }
  }

  return null;
}

ImportExtractionException _exceptionFrom422Payload(Map<String, dynamic>? map) {
  if (map != null && map['error'] != null) {
    return ImportExtractionException(
      _normalizeErrorCode(map['error'].toString()),
      detail: _detailFromMap(map),
      keysTried: _intFromMap(map, 'keys_tried'),
      failoverAttempts: _failoverAttemptCount(map),
    );
  }
  return const ImportExtractionException('extract_unreadable');
}

String _normalizeErrorCode(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('quota')) return 'quota_exceeded';
  if (lower.contains('not configured') || lower.contains('gemini')) {
    return 'extract_not_configured';
  }
  return raw;
}

String? _detailFromMap(Map<String, dynamic> map) {
  final detail = map['detail'] ?? map['details'] ?? map['error_description'];
  if (detail == null) return null;
  final text = detail.toString().trim();
  return text.isEmpty ? null : text;
}

int? _intFromMap(Map<String, dynamic> map, String key) {
  final v = map[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

int? _failoverAttemptCount(Map<String, dynamic> map) {
  final trace = map['failover_trace'];
  if (trace is List) return trace.length;
  return null;
}

Map<String, dynamic>? _asErrorMap(Object? data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return data.cast<String, dynamic>();
  if (data is Uint8List) {
    try {
      return _asErrorMap(utf8.decode(data));
    } catch (_) {
      return null;
    }
  }
  if (data is List<int>) {
    try {
      return _asErrorMap(utf8.decode(data));
    } catch (_) {
      return null;
    }
  }
  if (data is String && data.trim().isNotEmpty) {
    final trimmed = data.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        return null;
      }
    }
    return {'error': trimmed};
  }
  return null;
}

String _messageForCode(
  String code,
  String? detail, {
  int? keysTried,
  int? failoverAttempts,
}) {
  switch (code) {
    case 'missing_image':
      return 'No photo was selected. Take or choose a picture of the invoice table.';
    case 'image_too_large':
      return 'That photo is too large. Take a new one or choose a smaller image from your gallery.';
    case 'unsupported_mime':
      return 'That file type is not supported. Use a JPG or PNG photo of the invoice.';
    case 'image_rejected':
      return 'The photo could not be processed. Retake it in good light, hold the phone straight, and include the full item table.';
    case 'quota_exceeded':
      if (keysTried != null && keysTried < 2) {
        return 'Primary scan key hit its limit and no backup key was used. '
            'Set GEMINI_API_KEY_FALLBACK in Supabase secrets (different Google project), redeploy, then retry.';
      }
      if (detail == 'all_failover_attempts_exhausted') {
        final attempts = failoverAttempts;
        final attemptNote = attempts != null && attempts > 0
            ? ' ($attempts attempts across $keysTried keys)'
            : '';
        return 'Scan tried all backup models and keys$attemptNote but each hit a limit. '
            'Wait a few minutes and retry, or add rows manually.';
      }
      return 'The scan service is busy. Wait a few minutes and try again, or add rows manually.';
    case 'extract_not_configured':
      if (detail == 'function_not_found') {
        return 'Photo import is not deployed on the server yet. Deploy the inventory-import-extract Edge Function and set GEMINI_API_KEY in Supabase secrets.';
      }
      return 'Photo import is not configured yet. Set GEMINI_API_KEY in Supabase Edge Function secrets, then redeploy.';
    case 'unsupported_document':
      if (detail == 'no_inventory_table_found') {
        return 'No medicine table was found in this photo. Make sure the full item list is visible, not just the header or totals.';
      }
      return 'This does not look like a stock or invoice table. Photograph the product list and try again.';
    case 'extract_unreadable':
      if (detail == 'json_parse' || detail == 'no_json') {
        return 'We could not read the table clearly. Retake the photo with better light and straighter columns, then try again.';
      }
      if (detail == 'low_quality') {
        return 'The table was detected but no usable rows were found. Try a closer photo of the item list.';
      }
      return 'The table in this photo was hard to read. Try a clearer photo or enter items manually.';
    case 'extract_provider_error':
      if (detail == 'provider_unavailable') {
        return 'Gemini could not complete the scan right now. Wait a moment and try again.';
      }
      return 'The scan service is temporarily unavailable. Wait a moment and try again.';
    case 'forbidden':
      return 'Only team owners and admins can import stock from photos.';
    case 'unauthorized':
      return 'Your session expired. Sign in again and retry.';
    case 'bad_request':
      return 'Something went wrong sending the photo. Please try again.';
    case 'server_env_missing':
    case 'profile_error':
      return 'The server could not complete the scan. Please try again later.';
    case 'extract_failed':
      if (detail == 'timeout') {
        return 'The scan took too long and timed out. Try again with a smaller photo or stronger Wi‑Fi.';
      }
      if (detail == 'http_404') {
        return 'Photo import service was not found (404). Deploy inventory-import-extract on Supabase.';
      }
      if (detail?.startsWith('http_') == true) {
        final httpCode = int.tryParse(detail!.substring(5));
        return switch (httpCode) {
          400 => 'The server rejected the photo upload. Try a JPG/PNG image under 8 MB.',
          401 => 'Your session expired. Sign in again and retry.',
          403 => 'Only team owners and admins can import stock from photos.',
          413 => 'That photo is too large for the server. Choose a smaller image.',
          429 => 'The scan service has reached its daily limit. Try again later.',
          502 || 503 =>
            'The scan service is temporarily unavailable. Wait a moment and try again.',
          _ =>
            'The server returned an error (HTTP $httpCode). See [PhotoImport] logs in the terminal for details.',
        };
      }
      if (detail != null && detail.isNotEmpty) {
        return 'Scan failed ($detail). Try a clearer photo of the full item table.';
      }
      return 'Could not scan this photo. Check [PhotoImport] logs in the terminal, then try a clearer picture.';
    default:
      return 'Could not import from photo ($code). Try a clearer picture or add rows manually.';
  }
}
