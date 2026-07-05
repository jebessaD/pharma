import 'package:shared_preferences/shared_preferences.dart';

import 'report_date_range.dart';

/// Persists unified reports UI choices across sessions.
abstract final class ReportPreferences {
  static const keyDatePreset = 'reports_date_preset';
  static const keyCustomFrom = 'reports_custom_from';
  static const keyCustomTo = 'reports_custom_to';
  static const keyViewMode = 'reports_view_mode';

  static ReportDatePreset? parsePreset(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final p in ReportDatePreset.values) {
      if (p.name == raw) return p;
    }
    return null;
  }

  static ReportDateRange loadDateRange(
    SharedPreferences prefs, {
    required bool pharmacistMode,
  }) {
    final preset = parsePreset(prefs.getString(keyDatePreset));
    final fallback = pharmacistMode
        ? ReportDatePreset.today
        : ReportDatePreset.last30;
    final range = ReportDateRange.initial(preset: preset ?? fallback);

    if (range.preset == ReportDatePreset.custom) {
      final fromRaw = prefs.getString(keyCustomFrom);
      final toRaw = prefs.getString(keyCustomTo);
      final from = DateTime.tryParse(fromRaw ?? '');
      final to = DateTime.tryParse(toRaw ?? '');
      if (from != null && to != null) {
        range.from = ReportDateRange.dateOnly(from);
        range.to = ReportDateRange.dateOnly(to);
      } else {
        range.applyPreset(fallback);
      }
    }

    if (pharmacistMode) {
      range.clampForPharmacist();
    }
    return range;
  }

  static Future<void> saveDateRange(
    SharedPreferences prefs,
    ReportDateRange range,
  ) async {
    await prefs.setString(keyDatePreset, range.preset.name);
    if (range.preset == ReportDatePreset.custom) {
      await prefs.setString(
        keyCustomFrom,
        range.from.toIso8601String().split('T').first,
      );
      await prefs.setString(
        keyCustomTo,
        range.to.toIso8601String().split('T').first,
      );
    } else {
      await prefs.remove(keyCustomFrom);
      await prefs.remove(keyCustomTo);
    }
  }

  static bool loadCardsView(SharedPreferences prefs) {
    final raw = prefs.getString(keyViewMode);
    if (raw == null || raw.isEmpty) return true;
    return raw != 'table';
  }

  static Future<void> saveCardsView(
    SharedPreferences prefs, {
    required bool cards,
  }) async {
    await prefs.setString(keyViewMode, cards ? 'cards' : 'table');
  }
}
