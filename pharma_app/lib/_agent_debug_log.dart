import '_agent_debug_log_stub.dart'
    if (dart.library.io) '_agent_debug_log_io.dart' as impl;

Future<void> agentDebugLog(
  String location,
  String message,
  Map<String, Object?> data, {
  String hypothesisId = 'G',
}) =>
    impl.agentDebugLog(location, message, data, hypothesisId: hypothesisId);
