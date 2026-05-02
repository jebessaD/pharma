import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cached profile + team status for [GoRouter.redirect] to avoid a round-trip on every navigation.
class PharmacyGateData {
  PharmacyGateData({
    required this.userId,
    required this.role,
    required this.teamId,
    required this.isActiveUser,
    required this.teamStatus,
    required this.pharmacyName,
    required this.trialEndsAt,
    required this.billingStatus,
    required this.billingGraceEndsAt,
    required this.fetchedAt,
  });

  /// Auth user this row was loaded for (avoids reusing another account after sign-out/sign-in).
  final String userId;
  final String? role;
  final String? teamId;
  final bool isActiveUser;
  /// `teams.status` when [teamId] is non-null.
  final String? teamStatus;
  final String? pharmacyName;
  /// When set and in the past (UTC), self-serve trial is over.
  final DateTime? trialEndsAt;
  /// `teams.billing_status` when present in the database.
  final String? billingStatus;
  final DateTime? billingGraceEndsAt;
  final DateTime fetchedAt;

  bool get stale =>
      DateTime.now().difference(fetchedAt) > const Duration(minutes: 3);

  bool get trialEnded {
    if (billingStatus == 'active') return false;
    final t = trialEndsAt;
    if (t == null) return false;
    return DateTime.now().toUtc().isAfter(t.toUtc());
  }

  /// Subscription / billing gate for pharmacy routes (not team admin suspension).
  bool get billingBlocksPharmacyAccess {
    final s = billingStatus ?? 'trial';
    if (s == 'active') return false;
    if (s == 'past_due' || s == 'suspended_billing' || s == 'churned') {
      return true;
    }
    if (s == 'grace') {
      final g = billingGraceEndsAt;
      if (g != null && DateTime.now().toUtc().isAfter(g.toUtc())) return true;
      return false;
    }
    if (s == 'trial') return trialEnded;
    return false;
  }

  bool get shouldShowTrialEndedRoute =>
      billingBlocksPharmacyAccess && (billingStatus ?? 'trial') == 'trial';

  bool get shouldShowBillingBlockedRoute =>
      billingBlocksPharmacyAccess && (billingStatus ?? 'trial') != 'trial';
}

class PharmacyRedirectCacheNotifier extends Notifier<PharmacyGateData?> {
  @override
  PharmacyGateData? build() => null;

  void clear() => state = null;

  Future<void> hydrate(String? userId) async {
    if (userId == null) {
      state = null;
      return;
    }
    final cur = state;
    if (cur != null && cur.userId != userId) {
      await _refresh(userId);
      return;
    }
    if (cur != null && cur.userId == userId && !cur.stale) return;
    await _refresh(userId);
  }

  Future<void> _refresh(String userId) async {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('role, team_id, is_active')
        .eq('id', userId)
        .maybeSingle();
    final role = profile?['role'] as String?;
    final isActiveUser = profile?['is_active'] != false;
    final teamId = profile?['team_id'] as String?;
    String? teamStatus;
    String? pharmacyName;
    DateTime? trialEndsAt;
    String? billingStatus;
    DateTime? billingGraceEndsAt;
    if (teamId != null) {
      Map<String, dynamic>? team;
      try {
        team = await Supabase.instance.client
            .from('teams')
            .select(
              'status, trial_ends_at, billing_status, billing_grace_ends_at',
            )
            .eq('id', teamId)
            .maybeSingle();
      } on PostgrestException catch (e) {
        if (e.code != '42703') rethrow;
        try {
          team = await Supabase.instance.client
              .from('teams')
              .select('status, trial_ends_at')
              .eq('id', teamId)
              .maybeSingle();
        } on PostgrestException catch (e2) {
          if (e2.code != '42703') rethrow;
          team = await Supabase.instance.client
              .from('teams')
              .select('status')
              .eq('id', teamId)
              .maybeSingle();
        }
      }
      teamStatus = team?['status'] as String?;
      final raw = team?['trial_ends_at'] as String?;
      if (raw != null) {
        trialEndsAt = DateTime.tryParse(raw);
      }
      billingStatus = team?['billing_status'] as String?;
      final rawGrace = team?['billing_grace_ends_at'] as String?;
      if (rawGrace != null) {
        billingGraceEndsAt = DateTime.tryParse(rawGrace);
      }
      final tp = await Supabase.instance.client
          .from('team_profiles')
          .select('pharmacy_name')
          .eq('team_id', teamId)
          .maybeSingle();
      pharmacyName = tp?['pharmacy_name'] as String?;
    }
    state = PharmacyGateData(
      userId: userId,
      role: role,
      teamId: teamId,
      isActiveUser: isActiveUser,
      teamStatus: teamStatus,
      pharmacyName: pharmacyName,
      trialEndsAt: trialEndsAt,
      billingStatus: billingStatus,
      billingGraceEndsAt: billingGraceEndsAt,
      fetchedAt: DateTime.now(),
    );
  }
}

final pharmacyRedirectCacheProvider =
    NotifierProvider<PharmacyRedirectCacheNotifier, PharmacyGateData?>(
  PharmacyRedirectCacheNotifier.new,
);
