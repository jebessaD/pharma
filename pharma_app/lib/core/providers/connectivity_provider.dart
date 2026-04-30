import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<bool>((ref) {
  final plugin = Connectivity();

  Stream<bool> stream() async* {
    final initial = await plugin.checkConnectivity();
    yield !initial.contains(ConnectivityResult.none);
    yield* plugin.onConnectivityChanged.map(
      (results) => !results.contains(ConnectivityResult.none),
    );
  }

  final controller = StreamController<bool>();
  late final StreamSubscription<bool> sub;
  sub = stream().listen(
    controller.add,
    onError: controller.addError,
    onDone: controller.close,
  );
  ref.onDispose(() async {
    await sub.cancel();
    await controller.close();
  });
  return controller.stream.distinct();
});
