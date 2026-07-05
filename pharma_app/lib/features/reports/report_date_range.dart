import '../../core/utils/date_formatters.dart';

enum ReportDatePreset {
  today,
  last7,
  thisMonth,
  last30,
  thisYear,
  lifetime,
  custom,
}

class ReportDateRange {
  ReportDateRange({
    required this.preset,
    required this.from,
    required this.to,
  });

  ReportDatePreset preset;
  DateTime from;
  DateTime to;

  static final DateTime lifetimeFrom = DateTime(2020, 1, 1);

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  factory ReportDateRange.initial({ReportDatePreset preset = ReportDatePreset.last30}) {
    final range = ReportDateRange(
      preset: preset,
      from: dateOnly(DateTime.now()),
      to: dateOnly(DateTime.now()),
    );
    range.applyPreset(preset);
    return range;
  }

  void applyPreset(ReportDatePreset p) {
    final today = dateOnly(DateTime.now());
    switch (p) {
      case ReportDatePreset.today:
        from = today;
        to = today;
      case ReportDatePreset.last7:
        to = today;
        from = today.subtract(const Duration(days: 6));
      case ReportDatePreset.thisMonth:
        to = today;
        from = DateTime(today.year, today.month, 1);
      case ReportDatePreset.last30:
        to = today;
        from = today.subtract(const Duration(days: 29));
      case ReportDatePreset.thisYear:
        to = today;
        from = DateTime(today.year, 1, 1);
      case ReportDatePreset.lifetime:
        to = today;
        from = dateOnly(lifetimeFrom);
      case ReportDatePreset.custom:
        break;
    }
    preset = p;
  }

  ReportDatePreset? get quickChipPreset {
    return switch (preset) {
      ReportDatePreset.today => ReportDatePreset.today,
      ReportDatePreset.last7 => ReportDatePreset.last7,
      ReportDatePreset.thisMonth => ReportDatePreset.thisMonth,
      ReportDatePreset.last30 => ReportDatePreset.last30,
      ReportDatePreset.thisYear => ReportDatePreset.thisYear,
      ReportDatePreset.lifetime => ReportDatePreset.lifetime,
      ReportDatePreset.custom => null,
    };
  }

  String? get rangeLabel {
    return switch (preset) {
      ReportDatePreset.custom ||
      ReportDatePreset.thisYear ||
      ReportDatePreset.lifetime ||
      ReportDatePreset.last30 =>
        '${formatDdMmYyyy(from)} – ${formatDdMmYyyy(to)}',
      _ => null,
    };
  }

  void clampForPharmacist() {
    if (preset != ReportDatePreset.today &&
        preset != ReportDatePreset.last7 &&
        preset != ReportDatePreset.last30) {
      applyPreset(ReportDatePreset.today);
    }
  }
}