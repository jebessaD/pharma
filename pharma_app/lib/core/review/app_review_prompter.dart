import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared_preferences_provider.dart';

final appReviewPrompterProvider = Provider<AppReviewPrompter>((ref) {
  return AppReviewPrompter(ref.watch(sharedPreferencesProvider));
});

enum AppReviewMoment {
  saleCompleted('sale_completed', 2),
  stockRecorded('stock_recorded', 2),
  reportExported('report_exported', 2);

  const AppReviewMoment(this.storageKey, this.minimumCount);

  final String storageKey;
  final int minimumCount;
}

class AppReviewPrompter {
  AppReviewPrompter(this._prefs, {InAppReview? inAppReview})
    : _inAppReview = inAppReview ?? InAppReview.instance;

  static const _prefix = 'app_review';
  static const _totalMeaningfulActionsKey = '$_prefix.total_meaningful_actions';
  static const _requestAttemptsKey = '$_prefix.request_attempts';
  static const _lastRequestAtKey = '$_prefix.last_request_at';
  static const _cooldown = Duration(days: 60);
  static const _minimumMeaningfulActions = 4;
  static const _maximumAttempts = 3;

  final SharedPreferences _prefs;
  final InAppReview _inAppReview;

  Future<void> maybeRequestReview(AppReviewMoment moment) async {
    await _recordMeaningfulAction(moment);
    if (!_isEligible(moment)) return;
    if (kIsWeb) return;

    try {
      final available = await _inAppReview.isAvailable();
      if (!available) return;

      final now = DateTime.now().toUtc();
      await _prefs.setString(_lastRequestAtKey, now.toIso8601String());
      await _prefs.setInt(_requestAttemptsKey, _requestAttempts + 1);
      await _inAppReview.requestReview();
    } catch (_) {
      // Review prompts are best-effort and must never interrupt the workflow.
    }
  }

  Future<void> _recordMeaningfulAction(AppReviewMoment moment) async {
    final momentKey = '$_prefix.moment.${moment.storageKey}';
    await _prefs.setInt(momentKey, (_prefs.getInt(momentKey) ?? 0) + 1);
    await _prefs.setInt(
      _totalMeaningfulActionsKey,
      (_prefs.getInt(_totalMeaningfulActionsKey) ?? 0) + 1,
    );
  }

  bool _isEligible(AppReviewMoment moment) {
    if (_requestAttempts >= _maximumAttempts) return false;
    if ((_prefs.getInt(_totalMeaningfulActionsKey) ?? 0) <
        _minimumMeaningfulActions) {
      return false;
    }
    final momentCount = _prefs.getInt(
      '$_prefix.moment.${moment.storageKey}',
    );
    if ((momentCount ?? 0) < moment.minimumCount) return false;

    final lastRequestAt = _lastRequestAt;
    if (lastRequestAt == null) return true;
    return DateTime.now().toUtc().difference(lastRequestAt) >= _cooldown;
  }

  int get _requestAttempts => _prefs.getInt(_requestAttemptsKey) ?? 0;

  DateTime? get _lastRequestAt {
    final raw = _prefs.getString(_lastRequestAtKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }
}
