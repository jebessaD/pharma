import 'package:intl/intl.dart';

final DateFormat _ddmmyyyy = DateFormat('dd/MM/yyyy');
final DateFormat _ddmmyyyyHm = DateFormat('dd/MM/yyyy HH:mm');

String formatDdMmYyyy(dynamic value) {
  final dt = _asDateTime(value);
  if (dt == null) return value?.toString() ?? '';
  return _ddmmyyyy.format(dt.toLocal());
}

String formatDdMmYyyyHm(dynamic value) {
  final dt = _asDateTime(value);
  if (dt == null) return value?.toString() ?? '';
  return _ddmmyyyyHm.format(dt.toLocal());
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}
