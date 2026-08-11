import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/biometric_authenticator.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';
import 'package:perennia/features/protocols/widgets/protocols_lock_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

/// Covers `ProtocolsLockGate` — the widget every Supplements screen wraps
/// itself in — with a FAKE store + FAKE authenticator. No device,
/// no platform channel: `flutter test` never touches `local_auth` or
/// `flutter_secure_storage`.
void main() {
  late _FakeProtocolsLockStore store;
  late _FakeBiometricAuthenticator authenticator;

  setUp(() {
    store = _FakeProtocolsLockStore();
    authenticator = _FakeBiometricAuthenticator();
  });

  Future<void> pumpGate(
    WidgetTester tester, {
    ThemeData? theme,
    bool biometricSupported = false,
  }) async {
    authenticator.supported = biometricSupported;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          protocolsLockStoreProvider.overrideWith((ref) => store),
          biometricAuthenticatorProvider.overrideWith((ref) => authenticator),
          protocolsLockControllerProvider.overrideWith(
            () => ProtocolsLockController(
              hasher: const ProtocolsPinHasher(iterations: 10),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme ?? AppTheme.light(),
          home: const ProtocolsLockGate(
            child: Scaffold(
              body: Center(child: Text('Ashwagandha 500 mg')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the child directly when no lock is configured', (
    tester,
  ) async {
    await pumpGate(tester);

    expect(find.text('Ashwagandha 500 mg'), findsOneWidget);
    expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsNothing);
  });

  testWidgets(
    'a configured lock hides Dose/Compound content behind the lock screen',
    (tester) async {
      store.enabled = true;
      store.pinHash =
          await const ProtocolsPinHasher(iterations: 10).hash('1234');

      await pumpGate(tester);

      expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
      // At minimum: the locked surface renders NO Dose/Compound content.
      expect(find.text('Ashwagandha 500 mg'), findsNothing);
    },
  );

  testWidgets(
    'secure-storage read failures keep Dose/Compound content hidden',
    (tester) async {
      store.throwOnRead = true;

      await pumpGate(tester);

      expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
      expect(find.text('Supplements lock unavailable'), findsOneWidget);
      expect(find.byKey(ProtocolsUnlockForm.pinFieldKey), findsNothing);
      expect(find.text('Ashwagandha 500 mg'), findsNothing);
    },
  );

  testWidgets('a wrong PIN keeps the surface locked and shows an error', (
    tester,
  ) async {
    store.enabled = true;
    store.pinHash = await const ProtocolsPinHasher(iterations: 10).hash('1234');

    await pumpGate(tester);

    await tester.enterText(
      find.byKey(ProtocolsUnlockForm.pinFieldKey),
      '0000',
    );
    await tester.tap(find.byKey(ProtocolsUnlockForm.unlockPinButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
    expect(find.text('Ashwagandha 500 mg'), findsNothing);
    expect(find.byKey(ProtocolsUnlockForm.errorTextKey), findsOneWidget);
  });

  testWidgets('the correct PIN unlocks and reveals the surface', (
    tester,
  ) async {
    store.enabled = true;
    store.pinHash = await const ProtocolsPinHasher(iterations: 10).hash('1234');

    await pumpGate(tester);

    await tester.enterText(
      find.byKey(ProtocolsUnlockForm.pinFieldKey),
      '1234',
    );
    await tester.tap(find.byKey(ProtocolsUnlockForm.unlockPinButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsNothing);
    expect(find.text('Ashwagandha 500 mg'), findsOneWidget);
  });

  testWidgets(
    'the biometric button only appears when the device supports it, and '
    'unlocks on success',
    (tester) async {
      store.enabled = true;
      store.pinHash =
          await const ProtocolsPinHasher(iterations: 10).hash('1234');

      await pumpGate(tester, biometricSupported: true);
      expect(
        find.byKey(ProtocolsUnlockForm.unlockBiometricButtonKey),
        findsOneWidget,
      );

      authenticator.nextResult = true;
      await tester.tap(
        find.byKey(ProtocolsUnlockForm.unlockBiometricButtonKey),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsNothing);
      expect(find.text('Ashwagandha 500 mg'), findsOneWidget);
    },
  );

  testWidgets('no biometric button when the device does not support it', (
    tester,
  ) async {
    store.enabled = true;
    store.pinHash = await const ProtocolsPinHasher(iterations: 10).hash('1234');

    await pumpGate(tester, biometricSupported: false);

    expect(
      find.byKey(ProtocolsUnlockForm.unlockBiometricButtonKey),
      findsNothing,
    );
  });

  testWidgets(
    'the locked state survives a backgrounding->resume cycle: once '
    'unlocked, backgrounding re-locks and hides content again',
    (tester) async {
      store.enabled = true;
      store.pinHash =
          await const ProtocolsPinHasher(iterations: 10).hash('1234');

      await pumpGate(tester);
      await tester.enterText(
        find.byKey(ProtocolsUnlockForm.pinFieldKey),
        '1234',
      );
      await tester.tap(find.byKey(ProtocolsUnlockForm.unlockPinButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('Ashwagandha 500 mg'), findsOneWidget);

      // Simulate the app leaving the foreground (app switcher, lock button,
      // home button) — the whole point of's re-lock mechanism.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
      expect(find.text('Ashwagandha 500 mg'), findsNothing);

      // Resuming does NOT silently reveal content — re-authentication is
      // required again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
      expect(find.text('Ashwagandha 500 mg'), findsNothing);
    },
  );

  testWidgets('lock screen meets accessibility guidelines in both themes', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      store = _FakeProtocolsLockStore();
      store.enabled = true;
      store.pinHash =
          await const ProtocolsPinHasher(iterations: 10).hash('1234');
      authenticator = _FakeBiometricAuthenticator();

      await pumpGate(tester, theme: theme, biometricSupported: true);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

class _FakeProtocolsLockStore implements ProtocolsLockStore {
  bool enabled = false;
  String? pinHash;
  bool throwOnRead = false;

  @override
  Future<bool> isEnabled() async {
    if (throwOnRead) {
      throw StateError('secure storage unavailable');
    }
    return enabled;
  }

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }

  @override
  Future<String?> readPinHash() async {
    if (throwOnRead) {
      throw StateError('secure storage unavailable');
    }
    return pinHash;
  }

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
  bool supported = false;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate({required String reason}) async => nextResult;
}
