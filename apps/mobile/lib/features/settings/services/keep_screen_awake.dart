import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final keepScreenAwakeControllerProvider =
    Provider<KeepScreenAwakeController>((ref) {
  return const WakelockKeepScreenAwakeController();
});

abstract interface class KeepScreenAwakeController {
  Future<void> setEnabled(bool enabled);
}

class WakelockKeepScreenAwakeController implements KeepScreenAwakeController {
  const WakelockKeepScreenAwakeController();

  @override
  Future<void> setEnabled(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } on Object {
      // Widget tests and unsupported platforms may not have a wakelock channel.
    }
  }
}
