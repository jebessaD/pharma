import 'dart:convert';
import 'dart:io';

Future<void> agentDebugLog(
  String location,
  String message,
  Map<String, Object?> data, {
  String hypothesisId = 'G',
}) async {
  try {
    final line = jsonEncode({
      'sessionId': '109aeb',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'location': location,
      'message': message,
      'data': data,
      'hypothesisId': hypothesisId,
    });
    await File(
      '/Users/jeba/Documents/projects/pharma/.cursor/debug-109aeb.log',
    ).writeAsString('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}
