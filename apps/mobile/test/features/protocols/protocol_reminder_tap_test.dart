import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/app.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/catalog/repositories/exercise_catalog_repository.dart';
import 'package:perennia/features/home/controllers/home_controller.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/biometric_authenticator.dart';
import 'package:perennia/features/protocols/services/protocol_reminder_scheduler.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';
import 'package:perennia/features/protocols/widgets/protocols_day_view.dart';
import 'package:perennia/features/protocols/widgets/protocols_lock_screen.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/training/services/timer_background_scheduler.dart';
import 'package:perennia/features/up_next/repositories/up_next_feature_repository.dart';
import 'package:timezone/timezone.dart' as tz;

/// A tapped Supplement reminder opens its date's Protocol Day through the
/// Supplements lock (D5, files 52 and 53), on both platform paths: iOS over
/// the timer channel (`onProtocolReminderTapped`, buffered natively until
/// `timerNotificationsReady`), Android through the plugin's tap callback and
/// its launch details.
void main() {
  const timerChannel = MethodChannel('perennia/timer_background');
  const tappedDate = ProtocolDayDate(year: 2026, month: 10, day: 27);

  late AppDatabase database;
  late _FakePlatform platform;
  late _LockStore lockStore;
  late List<String> nativeCalls;

  /// What the native side does when Dart says it is ready: drain a buffered
  /// cold-start tap, as `AppDelegate.drainBufferedTap` does.
  String? bufferedIosReminderDate;

  setUp(() async {
    database = AppDatabase.inMemory();
    platform = _FakePlatform();
    lockStore = _LockStore(
      pinHash: await const ProtocolsPinHasher(iterations: 10).hash('1234'),
    );
    nativeCalls = <String>[];
    bufferedIosReminderDate = null;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timerChannel, null);
  });

  Future<void> sendIosTap(WidgetTester tester, String localDate) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      timerChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onProtocolReminderTapped', localDate),
      ),
      (_) {},
    );
  }

  Future<void> pumpApp(WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timerChannel, (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'timerNotificationsReady') {
        final buffered = bufferedIosReminderDate;
        bufferedIosReminderDate = null;
        if (buffered != null) {
          // The native side answers the ready call, then drains.
          scheduleMicrotask(() => unawaited(sendIosTap(tester, buffered)));
        }
      }
      return null;
    });
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
        settingsRepository: InMemorySettingsRepository(),
        extraOverrides: <Override>[
          appDatabaseProvider.overrideWith((ref) => database),
          homeNutritionDayProvider.overrideWith(
            (ref) => Stream<NutritionDayRecord>.value(
              NutritionDayRecord(
                localDate:
                    const NutritionDayDate(year: 2026, month: 10, day: 28),
                meals: const <NutritionDayMealRecord>[],
              ),
            ),
          ),
          protocolDayControllerProvider
              .overrideWith(_SelectedDateProtocolDayController.new),
          protocolsLockStoreProvider.overrideWith((ref) => lockStore),
          biometricAuthenticatorProvider
              .overrideWith((ref) => _NoBiometrics()),
          protocolsLockControllerProvider.overrideWith(
            () => ProtocolsLockController(
              hasher: const ProtocolsPinHasher(iterations: 10),
            ),
          ),
          protocolReminderPlatformProvider.overrideWith((ref) => platform),
          timerBackgroundSchedulerProvider
              .overrideWith((ref) => _GrantedPermissions()),
          protocolsClockProvider
              .overrideWithValue(() => DateTime(2026, 10, 28, 8)),
        ],
      ),
    );
    await _pumpFrames(tester);
  }

  ProviderContainer containerOf(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
  }

  Future<void> expectLockedDay(WidgetTester tester) async {
    await _pumpUntilFound(tester, find.byKey(ProtocolsLockGate.lockScreenKey));
    expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
    expect(find.byType(ProtocolsDayView), findsNothing);
    expect(containerOf(tester).read(selectedProtocolDayProvider), tappedDate);

    await tester.enterText(find.byKey(ProtocolsUnlockForm.pinFieldKey), '1234');
    await tester.tap(find.byKey(ProtocolsUnlockForm.unlockPinButtonKey));
    await _pumpUntilFound(tester, find.byType(ProtocolsDayView));
    await _pumpFrames(tester);
    expect(
      find.textContaining(_SelectedDateProtocolDayController.label(tappedDate)),
      findsWidgets,
    );
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester);
    var closed = false;
    unawaited(database.close().then((_) => closed = true));
    for (var frame = 0; frame < 100 && !closed; frame += 1) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('iOS, cold start: the tap buffered until ready opens its day '
      'behind the lock', (tester) async {
    bufferedIosReminderDate = tappedDate.storageValue;
    await pumpApp(tester);

    expect(nativeCalls, contains('timerNotificationsReady'));
    await expectLockedDay(tester);
    await closeApp(tester);
  });

  testWidgets('iOS, from resume: a tap on the running app opens its day '
      'behind the lock', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsNothing);

    await sendIosTap(tester, tappedDate.storageValue);
    await expectLockedDay(tester);
    await closeApp(tester);
  });

  testWidgets('Android, cold start: the launch details open their day behind '
      'the lock', (tester) async {
    platform.launch = protocolReminderPayload(tappedDate);
    await pumpApp(tester);

    await expectLockedDay(tester);
    await closeApp(tester);
  });

  testWidgets('Android, from resume: the plugin\'s tap callback opens its day '
      'behind the lock, and resuming runs the reconciler', (tester) async {
    await pumpApp(tester);
    expect(platform.onTap, isNotNull);
    final runsBefore = platform.runs;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpFrames(tester);
    expect(platform.runs, greaterThan(runsBefore));

    platform.onTap!(protocolReminderPayload(tappedDate));
    await expectLockedDay(tester);
    await closeApp(tester);
  });

  testWidgets('a second tap for the day on top only selects its date',
      (tester) async {
    lockStore.enabled = false;
    await pumpApp(tester);

    platform.onTap!(protocolReminderPayload(tappedDate));
    await _pumpUntilFound(tester, find.byType(ProtocolsDayView));
    platform.onTap!(protocolReminderPayload(tappedDate.addDays(-1)));
    await _pumpFrames(tester);

    expect(find.byType(ProtocolsDayView), findsOneWidget);
    expect(
      containerOf(tester).read(selectedProtocolDayProvider),
      tappedDate.addDays(-1),
    );
    await closeApp(tester);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 40,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Could not find $finder.');
}

/// A Protocol Day that shows its selected date, so the test can see which
/// day the tap opened.
class _SelectedDateProtocolDayController extends ProtocolDayController {
  static String label(ProtocolDayDate date) => 'Day ${date.storageValue}';

  @override
  Stream<ProtocolDayState> build() {
    final selected = ref.watch(selectedProtocolDayProvider);
    return Stream<ProtocolDayState>.value(
      ProtocolDayState(
        day: ProtocolDayRecord(
          localDate: selected,
          doses: <DoseRecord>[
            DoseRecord(
              id: 'dose-label',
              compoundName: label(selected),
              amountValue: 1,
              amountEntered: '1',
              unit: DoseUnit.capsule,
              route: DoseRoute.oral,
              tookAt: selected.toLocalDateTime().add(const Duration(hours: 9)),
              timezone: 'UTC',
              localDate: selected,
              provenance: DoseProvenance.manual,
              updatedAt: DateTime.utc(2026, 10, 28),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> ensureOtcLibrarySeeded() async {}
}

class _FakePlatform implements ProtocolReminderPlatform {
  void Function(String? payload)? onTap;
  String? launch;
  int runs = 0;

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    this.onTap = onTap;
  }

  @override
  Future<String?> launchPayload() async => launch;

  @override
  Future<tz.Location> localLocation() async {
    runs += 1;
    return tz.UTC;
  }

  @override
  Future<List<PendingProtocolNotification>> pendingNotifications() async {
    return const <PendingProtocolNotification>[];
  }

  @override
  Future<void> schedule(ProtocolReminderNotification notification) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> openNotificationSettings() async {}
}

class _GrantedPermissions implements TimerBackgroundScheduler {
  @override
  Future<TimerBackgroundPermissionStatus> notificationPermissionStatus() async {
    return TimerBackgroundPermissionStatus.granted;
  }

  @override
  Future<TimerBackgroundPermissionStatus> requestPermissionIfNeeded() async {
    return TimerBackgroundPermissionStatus.granted;
  }

  @override
  Future<TimerBackgroundPermissionStatus> schedule(
    TimerBackgroundSchedule schedule,
  ) async {
    return TimerBackgroundPermissionStatus.granted;
  }

  @override
  Future<void> cancel(String timerId) async {}
}

class _LockStore implements ProtocolsLockStore {
  _LockStore({required this.pinHash});

  bool enabled = true;
  String? pinHash;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;

  @override
  Future<String?> readPinHash() async => pinHash;

  @override
  Future<void> writePinHash(String hash) async => pinHash = hash;

  @override
  Future<void> clearPin() async => pinHash = null;
}

class _NoBiometrics implements BiometricAuthenticator {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> authenticate({required String reason}) async => false;
}
