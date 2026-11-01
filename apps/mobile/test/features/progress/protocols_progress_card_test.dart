import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/features/home/controllers/home_controller.dart';
import 'package:perennia/features/progress/controllers/progress_controller.dart';
import 'package:perennia/features/progress/repositories/progress_feature_repository.dart';
import 'package:perennia/features/progress/widgets/protocols_progress_card.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/biometric_authenticator.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';
import 'package:perennia/features/protocols/widgets/protocols_lock_screen.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

CompoundConsistencySummary _summary(
  int index, {
  int logged = 26,
  int partlyLogged = 0,
  int notLogged = 2,
  int paused = 0,
}) {
  return CompoundConsistencySummary(
    compoundId: 'compound-$index',
    compoundName: 'Compound $index',
    logged: logged,
    partlyLogged: partlyLogged,
    notLogged: notLogged,
    paused: paused,
  );
}

final _twoCompounds = <CompoundConsistencySummary>[
  const CompoundConsistencySummary(
    compoundId: 'creatine',
    compoundName: 'Creatine',
    logged: 26,
    partlyLogged: 0,
    notLogged: 2,
    paused: 0,
  ),
  const CompoundConsistencySummary(
    compoundId: 'trt',
    compoundName: 'TRT',
    logged: 10,
    partlyLogged: 3,
    notLogged: 1,
    paused: 4,
  ),
];

void main() {
  late _FakeLockStore store;

  setUp(() {
    store = _FakeLockStore();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<CompoundConsistencySummary> summaries =
        const <CompoundConsistencySummary>[],
    bool showProtocolsOnToday = true,
    ProgressFeatureRepository? repository,
    ProtocolsLockController Function()? lockController,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressFeatureRepositoryProvider.overrideWith(
            (ref) =>
                repository ??
                StubProgressFeatureRepository(consistencySummaries: summaries),
          ),
          settingsRepositoryProvider.overrideWith(
            (ref) => InMemorySettingsRepository(
              AppSettings.defaults.copyWith(
                showProtocolsOnToday: showProtocolsOnToday,
              ),
            ),
          ),
          progressClockProvider.overrideWith(
            (ref) => () => DateTime(2026, 11, 1, 18),
          ),
          protocolsLockStoreProvider.overrideWith((ref) => store),
          biometricAuthenticatorProvider.overrideWith(
            (ref) => _NoBiometrics(),
          ),
          protocolsLockControllerProvider.overrideWith(
            lockController ??
                () => ProtocolsLockController(
                      hasher: const ProtocolsPinHasher(iterations: 10),
                    ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(AppDimens.base),
              child: ProtocolsProgressCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
  }

  Future<void> lock() async {
    store.enabled = true;
    store.pinHash = await const ProtocolsPinHasher(iterations: 10).hash('1234');
  }

  /// Every text the card renders, in tree order.
  List<String> cardTexts(WidgetTester tester) {
    return tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ProtocolsProgressCard.cardKey),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .toList();
  }

  testWidgets('locked, the card shows only the lock row and no Compound', (
    tester,
  ) async {
    await lock();
    await pump(tester, summaries: _twoCompounds);

    expect(find.byKey(ProtocolsProgressCard.lockedRowKey), findsOneWidget);
    expect(find.text('Protocols are locked'), findsOneWidget);
    expect(find.byKey(ProtocolsProgressCard.unlockButtonKey), findsOneWidget);
    for (final summary in _twoCompounds) {
      expect(find.textContaining(summary.compoundName), findsNothing);
      expect(
        find.byKey(ProtocolsProgressCard.rowKey(summary.compoundId)),
        findsNothing,
      );
    }
    expect(find.textContaining('logged'), findsNothing);
  });

  testWidgets('the locked card is the same with and without Protocols', (
    tester,
  ) async {
    await lock();
    await pump(tester, summaries: _twoCompounds);
    final withProtocols = cardTexts(tester);
    final withSize = tester.getSize(find.byKey(ProtocolsProgressCard.cardKey));

    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester);

    expect(cardTexts(tester), withProtocols);
    expect(tester.getSize(find.byKey(ProtocolsProgressCard.cardKey)), withSize);
  });

  testWidgets('Unlock opens the unlock form; unlocking lists the Compounds', (
    tester,
  ) async {
    await lock();
    await pump(tester, summaries: _twoCompounds);

    await tester.tap(find.byKey(ProtocolsProgressCard.unlockButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(ProtocolsUnlockForm.pinFieldKey), '1234');
    await tester.tap(find.byKey(ProtocolsUnlockForm.unlockPinButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(ProtocolsProgressCard.lockedRowKey), findsNothing);
    expect(find.text('Creatine'), findsOneWidget);
    expect(find.text('26 logged · 2 not logged'), findsOneWidget);
    expect(find.text('TRT'), findsOneWidget);
    expect(
      find.text('10 logged · 3 partly logged · 1 not logged · 4 paused'),
      findsOneWidget,
    );

    // Leaving the foreground re-locks the card.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Creatine'), findsNothing);
    expect(find.byKey(ProtocolsProgressCard.lockedRowKey), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('an unreadable lock shows the lock row with no button', (
    tester,
  ) async {
    store.throwOnRead = true;
    await pump(tester, summaries: _twoCompounds);

    expect(find.byKey(ProtocolsProgressCard.lockedRowKey), findsOneWidget);
    expect(find.text('Protocols lock unavailable'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('Creatine'), findsNothing);
  });

  testWidgets('a lock controller error fails closed', (tester) async {
    await pump(
      tester,
      summaries: _twoCompounds,
      lockController: _FailingLockController.new,
    );

    expect(find.text('Protocols lock unavailable'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('Creatine'), findsNothing);
  });

  testWidgets('a failed Protocols read fails closed', (tester) async {
    await pump(tester, repository: const _FailingSummaries());

    expect(find.text('Protocols lock unavailable'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('with no lock, rows show the non-zero counts in order', (
    tester,
  ) async {
    await pump(tester, summaries: _twoCompounds);

    expect(find.text('Protocols'), findsOneWidget);
    expect(find.text('Creatine'), findsOneWidget);
    expect(find.text('26 logged · 2 not logged'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Creatine')).dy,
      lessThan(tester.getTopLeft(find.text('TRT')).dy),
    );
    expect(
        find.byKey(ProtocolsProgressCard.allProtocolsButtonKey), findsNothing);
    final row = tester.getSize(
      find.byKey(ProtocolsProgressCard.rowKey('creatine')),
    );
    expect(row.height, greaterThanOrEqualTo(48));
  });

  testWidgets(
      'seven Compounds show six rows and "All protocols", which '
      'opens Today on its Protocols tab', (tester) async {
    final container = await pump(
      tester,
      summaries: <CompoundConsistencySummary>[
        for (var index = 0; index < 7; index += 1) _summary(index),
      ],
    );
    container
        .read(selectedHomeDestinationProvider.notifier)
        .select(HomeDestination.progress);

    for (var index = 0; index < 6; index += 1) {
      expect(
        find.byKey(ProtocolsProgressCard.rowKey('compound-$index')),
        findsOneWidget,
      );
    }
    expect(
        find.byKey(ProtocolsProgressCard.rowKey('compound-6')), findsNothing);

    await tester.ensureVisible(
      find.byKey(ProtocolsProgressCard.allProtocolsButtonKey),
    );
    await tester.tap(find.byKey(ProtocolsProgressCard.allProtocolsButtonKey));
    await tester.pump();

    expect(
      container.read(selectedHomeDestinationProvider),
      HomeDestination.today,
    );
    expect(container.read(selectedHomeDomainProvider), HomeDomain.protocols);
  });

  testWidgets('a set lock, unlocked, with no rows says so instead of hiding', (
    tester,
  ) async {
    await lock();
    final container = await pump(tester);
    await container
        .read(protocolsLockControllerProvider.notifier)
        .unlockWithPin('1234');
    await tester.pumpAndSettle();

    expect(find.byKey(ProtocolsProgressCard.cardKey), findsOneWidget);
    expect(find.text('No protocol days in this period'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('no lock and no rows renders nothing', (tester) async {
    await pump(tester);

    expect(find.byKey(ProtocolsProgressCard.cardKey), findsNothing);
    expect(find.text('Protocols'), findsNothing);
  });

  testWidgets('the card is absent while Protocols are hidden from Today', (
    tester,
  ) async {
    await pump(tester, summaries: _twoCompounds, showProtocolsOnToday: false);
    expect(find.byKey(ProtocolsProgressCard.cardKey), findsNothing);

    await lock();
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester, summaries: _twoCompounds, showProtocolsOnToday: false);
    expect(find.byKey(ProtocolsProgressCard.cardKey), findsNothing);
  });
}

class _FakeLockStore implements ProtocolsLockStore {
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

class _NoBiometrics implements BiometricAuthenticator {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> authenticate({required String reason}) async => false;
}

class _FailingLockController extends ProtocolsLockController {
  @override
  Future<ProtocolsLockState> build() async {
    throw StateError('lock state failed');
  }
}

class _FailingSummaries extends StubProgressFeatureRepository {
  const _FailingSummaries();

  @override
  Stream<List<CompoundConsistencySummary>> watchConsistencySummary(
    TrainingDayDate from,
    TrainingDayDate to, {
    required TrainingDayDate today,
  }) {
    return Stream<List<CompoundConsistencySummary>>.error(
      StateError('read failed'),
    );
  }
}
