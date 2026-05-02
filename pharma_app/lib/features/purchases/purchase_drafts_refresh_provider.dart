import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped after stock-changing purchase actions (e.g. receive) so the
/// drafts list reloads when the purchases hub is shown again.
class PurchaseDraftsRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state = state + 1;
  }
}

final purchaseDraftsRefreshProvider =
    NotifierProvider<PurchaseDraftsRefreshNotifier, int>(
  PurchaseDraftsRefreshNotifier.new,
);
