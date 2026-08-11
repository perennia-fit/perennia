import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Abstracts the native biometric/device-credential prompt behind a testable
/// interface — mirrors `KeepScreenAwakeController`
/// (features/settings/services/keep_screen_awake.dart): an
/// `abstract interface class` + a concrete impl that swallows platform-channel
/// errors, plus a `Provider` a test can override with a fake. This keeps the
/// `ProtocolsLockController` state machine fully unit/widget-testable with NO
/// device — `flutter test` never touches the real `local_auth` plugin.
///
/// The lock itself is a DEVICE/UI control only: it gates
/// LOCAL visibility of the Supplements section. It never touches sync (that
/// stays on the LWW rails) and it is NOT an agent scope wall (the
/// agent boundary is a later, separate milestone, M30/).
abstract interface class BiometricAuthenticator {
  /// Whether this device can attempt a biometric/device-credential prompt at
  /// all. When false, the lock screen falls back to PIN entry only.
  Future<bool> isSupported();

  /// Prompts for biometric/device-credential authentication. Returns true on
  /// success, false on failure, cancellation, or any platform error — never
  /// throws for expected conditions (locked-out device, no enrolled
  /// biometrics, simulators/emulators, widget tests).
  Future<bool> authenticate({required String reason});
}

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>((ref) {
  return LocalAuthBiometricAuthenticator();
});

/// Whether THIS device can attempt a biometric/device-credential prompt at
/// all — drives whether the lock screen offers the biometric button
/// alongside PIN entry. A `FutureProvider` so widget tests can override it
/// directly instead of waiting on the fake authenticator's async method.
final protocolsBiometricSupportedProvider = FutureProvider<bool>((ref) {
  return ref.watch(biometricAuthenticatorProvider).isSupported();
});

class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<bool> isSupported() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported || canCheck;
    } on Object {
      // Widget tests and unsupported platforms may not have a local_auth
      // channel at all.
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: false,
      );
    } on Object {
      // A failed/cancelled prompt, a `LocalAuthException` (no enrolled
      // biometrics, locked-out device, etc.), or an unsupported platform (no
      // local_auth channel at all in `flutter test`) all fall back to "not
      // authenticated" rather than crashing the lock screen.
      return false;
    }
  }
}
