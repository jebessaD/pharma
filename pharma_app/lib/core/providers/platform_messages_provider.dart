import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Active platform messages + read state for the signed-in user (ops / announcements).
final platformOpsProvider =
    FutureProvider.autoDispose<PlatformOpsSnapshot>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  final info = await PackageInfo.fromPlatform();
  final appVersion = info.version.split('+').first.trim();
  if (uid == null) {
    return PlatformOpsSnapshot(messages: const [], readIds: const {});
  }

  final now = DateTime.now().toUtc().toIso8601String();
  final data = await Supabase.instance.client
      .from('platform_messages')
      .select()
      .lte('starts_at', now)
      .or('ends_at.is.null,ends_at.gte.$now')
      .order('starts_at', ascending: false);

  final rows = List<Map<String, dynamic>>.from(data as List);
  final readsRaw = await Supabase.instance.client
      .from('platform_message_reads')
      .select('message_id')
      .eq('user_id', uid);
  final readIds = <String>{
    for (final r in readsRaw as List)
      r['message_id'] as String,
  };

  Version? appVer;
  try {
    appVer = Version.parse(appVersion);
  } catch (_) {
    appVer = null;
  }

  final visible = <Map<String, dynamic>>[];
  for (final m in rows) {
    final minRaw = m['min_app_version'] as String?;
    if (minRaw != null && minRaw.trim().isNotEmpty && appVer != null) {
      try {
        final minV = Version.parse(minRaw.trim());
        if (appVer < minV) continue;
      } catch (_) {
        /* ignore min filter if unparsable */
      }
    }
    visible.add(m);
  }

  return PlatformOpsSnapshot(messages: visible, readIds: readIds);
});

class PlatformOpsSnapshot {
  const PlatformOpsSnapshot({
    required this.messages,
    required this.readIds,
  });

  final List<Map<String, dynamic>> messages;
  final Set<String> readIds;

  int get unreadCount =>
      messages.where((m) => !readIds.contains(m['id'] as String)).length;

  /// First unread warning/critical for [MaterialBanner].
  Map<String, dynamic>? get bannerMessage {
    for (final m in messages) {
      final id = m['id'] as String?;
      if (id == null || readIds.contains(id)) continue;
      final sev = m['severity'] as String? ?? 'info';
      if (sev == 'warning' || sev == 'critical') return m;
    }
    return null;
  }
}

Future<void> markPlatformMessageRead(WidgetRef ref, String messageId) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return;
  await Supabase.instance.client.from('platform_message_reads').upsert({
    'user_id': uid,
    'message_id': messageId,
  });
  ref.invalidate(platformOpsProvider);
}
