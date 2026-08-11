import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/biometric_authenticator.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';
import 'package:perennia/features/protocols/widgets/protocols_lock_screen.dart';
import 'package:perennia/features/protocols/widgets/protocols_lock_settings.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

/// Covers the Settings "Lock Supplements" toggle: configuring a PIN
/// turns the lock on and immediately gates the surface; turning it off
/// requires re-authentication first — a lent phone can never disable the
/// lock from Settings without proving possession.
void main() {
  late _FakeProtocolsLockStore store;
  late _FakeBiometricAuthenticator authenticator;

  setUp(() {
    store = _FakeProtocolsLockStore();
    authenticator = _FakeBiometricAuthenticator();
  });

  Future<void> pumpTile(WidgetTester tester, {ThemeData? theme}) async {
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
          home: const Scaffold(body: ProtocolsLockSettingsTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the toggle starts off when no lock is configured', (
    tester,
  ) async {
    await pumpTile(tester);

    final tile = tester.widget<SwitchListTile>(
      find.byKey(ProtocolsLockSettingsTile.switchKey),
    );
    expect(tile.value, isFalse);
  });

  testWidgets(
    'secure-storage read failures keep the toggle enabled and disabled',
    (tester) async {
      store.throwOnRead = true;

      await pumpTile(tester);

      final tile = tester.widget<SwitchListTile>(
        find.byKey(ProtocolsLockSettingsTile.switchKey),
      );
      expect(tile.value, isTrue);
      expect(tile.onChanged, isNull);
      expect(
        find.text(
          'Supplements stays hidden because secure storage is unavailable',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ProtocolsLockSettingsTile.switchKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ProtocolsLockConfigureSheet.pinFieldKey),
        findsNothing,
      );
    },
  );

  testWidgets(
    'turning the toggle on opens the configure sheet; matching PINs enable '
    'the lock',
    (tester) async {
      await pumpTile(tester);

      await tester.tap(find.byKey(ProtocolsLockSettingsTile.switchKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ProtocolsLockConfigureSheet.pinFieldKey),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(ProtocolsLockConfigureSheet.pinFieldKey),
        '1234',
      );
      await tester.enterText(
        find.byKey(ProtocolsLockConfigureSheet.confirmFieldKey),
        '1234',
      );
      await tester.tap(find.byKey(ProtocolsLockConfigureSheet.saveButtonKey));
      await tester.pumpAndSettle();

      expect(store.enabled, isTrue);
      expect(store.pinHash, isNotNull);
      expect(store.pinHash, isNot('1234'));
      final tile = tester.widget<SwitchListTile>(
        find.byKey(ProtocolsLockSettingsTile.switchKey),
      );
      expect(tile.value, isTrue);
    },
  );

  testWidgets('mismatched PINs in the configure sheet show an error', (
    tester,
  ) async {
    await pumpTile(tester);

    await tester.tap(find.byKey(ProtocolsLockSettingsTile.switchKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(ProtocolsLockConfigureSheet.pinFieldKey),
      '1234',
    );
    await tester.enterText(
      find.byKey(ProtocolsLockConfigureSheet.confirmFieldKey),
      '4321',
    );
    await tester.tap(find.byKey(ProtocolsLockConfigureSheet.saveButtonKey));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ProtocolsLockConfigureSheet.errorTextKey),
      findsOneWidget,
    );
    expect(store.enabled, isFalse);
  });

  testWidgets('a malformed PIN in the configure sheet shows an error', (
    tester,
  ) async {
    await pumpTile(tester);

    await tester.tap(find.byKey(ProtocolsLockSettingsTile.switchKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(ProtocolsLockConfigureSheet.pinFieldKey),
      '12',
    );
    await tester.enterText(
      find.byKey(ProtocolsLockConfigureSheet.confirmFieldKey),
      '12',
    );
    await tester.tap(find.byKey(ProtocolsLockConfigureSheet.saveButtonKey));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ProtocolsLockConfigureSheet.errorTextKey),
      findsOneWidget,
    );
    expect(store.enabled, isFalse);
  });

  testWidgets(
    'turning the toggle off requires authentication first; a wrong PIN '
    'leaves the lock enabled',
    (tester) async {
      store.enabled = true;
      store.pinHash =
          await const ProtocolsPinHasher(iterations: 10).hash('1234');

      await pumpTile(tester);
      await tester.tap(find.byKey(ProtocolsLockSettingsTile.switchKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ProtocolsUnlockForm.pinFieldKey), findsOneWidget);

      await tester.enterText(
        find.byKey(ProtocolsUnlockForm.pinFieldKey),
        '0000',
      );
      await tester.tap(find.byKey(ProtocolsUnlockForm.unlockPinButtonKey));
      await tester.pumpAndSettle();

      expect(store.enabled, isTrue);
      expect(find.byKey(ProtocolsUnlockForm.errorTextKey), findsOneWidget);
    },
  );

  testWidgets(
    'turning the toggle off with the correct PIN disables the lock and '
    'forgets the PIN',
    (tester) async {
      store.enabled = true;
      store.pinHash =
          await const ProtocolsPinHasher(iterations: 10).hash('1234');

      await pumpTile(tester);
      await tester.tap(find.byKey(ProtocolsLockSettingsTile.switchKey));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ProtocolsUnlockForm.pinFieldKey),
        '1234',
      );
      await tester.tap(find.byKey(ProtocolsUnlockForm.unlockPinButtonKey));
      await tester.pumpAndSettle();

      expect(store.enabled, isFalse);
      expect(store.pinHash, isNull);
      final tile = tester.widget<SwitchListTile>(
        find.byKey(ProtocolsLockSettingsTile.switchKey),
      );
      expect(tile.value, isFalse);
    },
  );

  testWidgets(
    'lock settings tile, configure sheet, and disable sheet meet '
    'accessibility guidelines in both themes',
    (tester) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();
        store = _FakeProtocolsLockStore();
        authenticator = _FakeBiometricAuthenticator();

        await pumpTile(tester, theme: theme);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await tester.tap(find.byKey(ProtocolsLockSettingsTile.switchKey));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ProtocolsLockConfigureSheet.pinFieldKey),
          findsOneWidget,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await tester.enterText(
          find.byKey(ProtocolsLockConfigureSheet.pinFieldKey),
          '1234',
        );
        await tester.enterText(
          find.byKey(ProtocolsLockConfigureSheet.confirmFieldKey),
          '1234',
        );
        await tester.tap(
          find.byKey(ProtocolsLockConfigureSheet.saveButtonKey),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ProtocolsLockSettingsTile.switchKey));
        await tester.pumpAndSettle();
        expect(find.byKey(ProtocolsUnlockForm.pinFieldKey), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
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
