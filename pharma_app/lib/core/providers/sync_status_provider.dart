import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncState { idle, syncing, offline, failed }

class SyncStatus {
  const SyncStatus({
    required this.state,
    required this.pendingCount,
    this.lastSyncAt,
    this.lastError,
  });

  final SyncState state;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final String? lastError;

  SyncStatus copyWith({
    SyncState? state,
    int? pendingCount,
    DateTime? lastSyncAt,
    String? lastError,
  }) {
    return SyncStatus(
      state: state ?? this.state,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: lastError,
    );
  }
}

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() =>
      const SyncStatus(state: SyncState.idle, pendingCount: 0);

  void markOffline() {
    state = state.copyWith(state: SyncState.offline);
  }

  void markSyncing() {
    state = state.copyWith(state: SyncState.syncing, lastError: null);
  }

  void markFailed(String error) {
    state = state.copyWith(state: SyncState.failed, lastError: error);
  }

  void markIdle() {
    state = state.copyWith(state: SyncState.idle, lastError: null);
  }

  void updatePending(int pendingCount) {
    state = state.copyWith(pendingCount: pendingCount);
  }

  void markSyncedNow() {
    state = state.copyWith(
      state: SyncState.idle,
      lastSyncAt: DateTime.now(),
      lastError: null,
    );
  }
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);
