import 'package:flutter/foundation.dart';

import 'import_models.dart';

/// Debug logging for photo import — visible in `flutter run` / IDE console.
abstract final class ImportLogger {
  static const _tag = '[PhotoImport]';

  static void phase(String message) => _log('phase', message);

  static void info(String message, [Map<String, Object?>? data]) =>
      _log('info', message, data);

  static void warn(String message, [Map<String, Object?>? data]) =>
      _log('warn', message, data);

  static void error(
    String message,
    Object? error, [
    Map<String, Object?>? data,
  ]) {
    final parts = <String>[_tag, 'ERROR', message];
    if (data != null && data.isNotEmpty) {
      parts.add(_formatData(data));
    }
    debugPrint(parts.join(' | '));
    if (error != null) {
      debugPrint('$_tag   thrown: $error');
      if (error is ImportExtractionException) {
        debugPrint(
          '$_tag   code=${error.code} detail=${error.detail ?? '(none)'}',
        );
      }
    }
  }

  static void _log(String level, String message, [Map<String, Object?>? data]) {
    final parts = <String>[_tag, level.toUpperCase(), message];
    if (data != null && data.isNotEmpty) {
      parts.add(_formatData(data));
    }
    debugPrint(parts.join(' | '));
  }

  static String _formatData(Map<String, Object?> data) {
    return data.entries
        .map((e) => '${e.key}=${_safeValue(e.value)}')
        .join(', ');
  }

  static String _safeValue(Object? value) {
    if (value == null) return 'null';
    final text = value.toString();
    if (text.length > 240) {
      return '${text.substring(0, 240)}…(${text.length} chars)';
    }
    return text;
  }

  /// Truncate response bodies for logs (never log image data).
  static String summarizeResponseBody(Object? body) {
    if (body == null) return 'null';
    if (body is Map) {
      final keys = body.keys.map((k) => '$k').join(',');
      final error = body['error'];
      final detail = body['detail'];
      final lineCount = (body['result'] is Map)
          ? ((body['result'] as Map)['lines'] as List?)?.length
          : null;
      return 'Map{keys=$keys, error=$error, detail=$detail, lines=$lineCount}';
    }
    if (body is String) {
      if (body.length > 280) {
        return '${body.substring(0, 280)}…(${body.length} chars)';
      }
      return body;
    }
    return _safeValue(body);
  }
}
