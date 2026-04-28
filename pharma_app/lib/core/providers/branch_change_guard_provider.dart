import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef DiscardChanges = void Function();

class BranchChangeGuardState {
  const BranchChangeGuardState(this._entries);

  final Map<String, ({bool isDirty, DiscardChanges? onDiscard})> _entries;

  bool get hasDirty => _entries.values.any((entry) => entry.isDirty);

  Map<String, ({bool isDirty, DiscardChanges? onDiscard})> get entries => _entries;
}

class BranchChangeGuard extends Notifier<BranchChangeGuardState> {
  @override
  BranchChangeGuardState build() => const BranchChangeGuardState({});

  void register(String key, {DiscardChanges? onDiscard}) {
    final next = Map<String, ({bool isDirty, DiscardChanges? onDiscard})>.from(state.entries);
    final current = next[key];
    next[key] = (isDirty: current?.isDirty ?? false, onDiscard: onDiscard);
    state = BranchChangeGuardState(next);
  }

  void setDirty(String key, bool isDirty) {
    final next = Map<String, ({bool isDirty, DiscardChanges? onDiscard})>.from(state.entries);
    final current = next[key];
    next[key] = (isDirty: isDirty, onDiscard: current?.onDiscard);
    state = BranchChangeGuardState(next);
  }

  void clearDirty(String key) {
    setDirty(key, false);
  }

  void unregister(String key) {
    final next = Map<String, ({bool isDirty, DiscardChanges? onDiscard})>.from(state.entries);
    next.remove(key);
    state = BranchChangeGuardState(next);
  }

  void discardAll() {
    for (final entry in state.entries.values) {
      entry.onDiscard?.call();
    }
    final reset = <String, ({bool isDirty, DiscardChanges? onDiscard})>{};
    for (final mapEntry in state.entries.entries) {
      reset[mapEntry.key] = (isDirty: false, onDiscard: mapEntry.value.onDiscard);
    }
    state = BranchChangeGuardState(reset);
  }
}

final branchChangeGuardProvider =
    NotifierProvider<BranchChangeGuard, BranchChangeGuardState>(BranchChangeGuard.new);
