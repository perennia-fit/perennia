import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/biometric_authenticator.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';

/// Covers the lock state machine end-to-end with FAKE dependencies —
/// no device, no platform channel, no real secure storage. This is the
/// authoritative "no device needed" coverage the milestone brief calls for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeProtocolsLockStore store;
  late _FakeBiometricAuthenticator authenticator;
  late ProviderContainer container;

  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        protocolsLockStoreProvider.overrideWith((ref) => store),
        biometricAuthenticatorProvider.overrideWith((ref) => authenticator),
        // A tiny iteration count keeps PBKDF2 fast in tests.
        protocolsLockControllerProvider.overrideWith(
          () => ProtocolsLockController(
            hasher: const ProtocolsPinHasher(iterations: 10),
          ),
        ),
      ],
    );
  }

  setUp(() {
    store = _FakeProtocolsLockStore();
    authenticator = _FakeBiometricAuthenticator();
    container = buildContainer();
  });

  tearDown(() {
    container.dispose();
  });

  test('starts disabled with no prior configuration', () async {
    final state = await container.read(protocolsLockControllerProvider.future);
    expect(state.status, ProtocolsLockStatus.disabled);
    expect(state.isEnabled, isFalse);
    expect(state.hasPin, isFalse);
  });

  test('enabling the lock configures a PIN and immediately gates the surface',
      () async {
    await container.read(protocolsLockControllerProvider.future);
    final controller = container.read(protocolsLockControllerProvider.notifier);

    await controller.enableLock('1234');

    final state = container.read(protocolsLockControllerProvider).value!;
    expect(state.status, ProtocolsLockStatus.locked);
    expect(state.isEnabled, isTrue);
    expect(state.hasPin, isTrue);
    // Never plaintext.
    expect(store.pinHash, isNotNull);
    expect(store.pinHash, isNot('1234'));
    expect(store.enabled, isTrue);
  });

  test('rejects a malformed PIN and leaves the lock unconfigured', () async {
    await container.read(protocolsLockControllerProvider.future);
    final controller = container.read(protocolsLockControllerProvider.notifier);

    await expectLater(() => controller.enableLock('12'), throwsArgumentError);

    final state = container.read(protocolsLockControllerProvider).value!;
    expect(state.status, ProtocolsLockStatus.disabled);
    expect(store.enabled, isFalse);
  });

  test('a wrong PIN keeps the surface locked', () async {
    await container.read(protocolsLockControllerProvider.future);
    final controller = container.read(protocolsLockControllerProvider.notifier);
    await controller.enableLock('1234');

    final unlocked = await controller.unlockWithPin('0000');

    expect(unlocked, isFalse);
    expect(
      container.read(protocolsLockControllerProvider).value!.status,
      ProtocolsLockStatus.locked,
    );
  });

  test('the correct PIN unlocks the surface', () async {
    await container.read(protocolsLockControllerProvider.future);
    final controller = container.read(protocolsLockControllerProvider.notifier);
    await controller.enableLock('4321');

    final unlocked = await controller.unlockWithPin('4321');

    expect(unlocked, isTrue);
    expect(
      container.read(protocolsLockControllerProvider).value!.status,
      ProtocolsLockStatus.unlocked,
    );
  });

  test('a successful biometric prompt unlocks the surface', () async {
    await container.read(protocolsLockControllerProvider.future);
    final controller = container.read(protocolsLockControllerProvider.notifier);
    await controller.enableLock('1234');
    authenticator.nextResult = true;

    final unlocked = await controller.unlockWithBiometrics();

    expect(unlocked, isTrue);
    expect(authenticator.authenticateCalls, 1);
    expect(
      container.read(protocolsLockControllerProvider).value!.status,
      ProtocolsLockStatus.unlocked,
    );
  });

  test('a failed/cancelled biometric prompt keeps the surface locked', () async {
    await container.read(protocolsLockControllerProvider.future);
    final controller = container.read(protocolsLockControllerProvider.notifier);
    await controller.enableLock('1234');
    authenticator.nextResult = false;

    final unlocked = await controller.unlockWithBiometrics();

    expect(unlocked, isFalse);
    expect(
      container.read(protocolsLockControllerProvider).value!.status,
      ProtocolsLockStatus.locked,
    );
  });

  test(
    'the locked state survives a backgrounding->resume cycle and re-locks',
    () async {
      await container.read(protocolsLockControllerProvider.future);
      final controller =
          container.read(protocolsLockControllerProvider.notifier);
      await controller.enableLock('1234');
      await controller.unlockWithPin('1234');
      expect(
        container.read(protocolsLockControllerProvider).value!.status,
        ProtocolsLockStatus.unlocked,
      );

      // Backgrounding (inactive on iOS app-switcher entry, paused once fully
      // backgrounded) re-locks immediately — this is what makes hide-at-a-
      // glance work: the very next frame renders the lock screen, not
      // Compound/Dose content.
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(
        container.read(protocolsLockControllerProvider).value!.status,
        ProtocolsLockStatus.locked,
      );

      // Resuming does NOT silently unlock — the user must re-authenticate.
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(
        container.read(protocolsLockControllerProvider).value!.status,
        ProtocolsLockStatus.locked,
      );
    },
  );

  test('backgrounding is a no-op when no lock is configured', () async {
    await container.read(protocolsLockControllerProvider.future);
    final controller = container.read(protocolsLockControllerProvider.notifier);

    controller.didChangeAppLifecycleState(AppLifecycleState.paused);

    expect(
      container.read(protocolsLockControllerProvider).value!.status,
      ProtocolsLockStatus.disabled,
    );
  });

  test(
    'a fresh app start with a prior lock configured starts locked, not '
    'unlocked (sticky across process restarts, not just backgrounding)',
    () async {
      store.enabled = true;
      store.pinHash = await const ProtocolsPinHasher(iterations: 10).hash(
        '1234',
      );

      final freshState = await container.read(
        protocolsLockControllerProvider.future,
      );

      expect(freshState.status, ProtocolsLockStatus.locked);
      expect(freshState.hasPin, isTrue);
    },
  );

  test('disableLock refuses while still locked', () async {
    await container.read(protocolsLockControllerProvider.future);
    final controller = container.read(protocolsLockControllerProvider.notifier);
    await controller.enableLock('1234');

    final disabled = await controller.disableLock();

    expect(disabled, isFalse);
    expect(store.enabled, isTrue);
    expect(
      container.read(protocolsLockControllerProvider).value!.status,
      ProtocolsLockStatus.locked,
    );
  });

  test('disableLock succeeds once unlocked, and forgets the PIN', () async {
    await container.read(protocolsLockControllerProvider.future);
    final controller = container.read(protocolsLockControllerProvider.notifier);
    await controller.enableLock('1234');
    await controller.unlockWithPin('1234');

    final disabled = await controller.disableLock();

    expect(disabled, isTrue);
    expect(store.enabled, isFalse);
    expect(store.pinHash, isNull);
    final state = container.read(protocolsLockControllerProvider).value!;
    expect(state.status, ProtocolsLockStatus.disabled);
    expect(state.hasPin, isFalse);
  });
}

class _FakeProtocolsLockStore implements ProtocolsLockStore {
  bool enabled = false;
  String? pinHash;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }

  @override
  Future<String?> readPinHash() async => pinHash;

  @override
  Future<void> writePinHash(String hash) async {
    pinHash = hash;
  }

  @override
  Future<void> clearPin() async {
    pinHash = null;
  }
}

class _FakeBiometricAuthenticator implements BiometricAuthenticator {
  bool nextResult = false;
  bool supported = true;
  int authenticateCalls = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate({required String reason}) async {
    authenticateCalls += 1;
    return nextResult;
  }
}
