import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/services/protocol_reminder_plan.dart';
import 'package:perennia/features/protocols/services/protocol_reminder_scheduler.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/training/services/timer_background_scheduler.dart';
import 'package:perennia/l10n/app_localizations.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The reminder reconciler (D5, file 49) against a fake plugin boundary,
/// and the real boundary against the plugin's method channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late tz.Location newYork;

  setUpAll(() {
    tz_data.initializeTimeZones();
    newYork = tz.getLocation('America/New_York');
  });

  const today = ProtocolDayDate(year: 2026, month: 10, day: 28);
  final tomorrow = today.addDays(1);
  // 08:00 in New York.
  final now = DateTime.utc(2026, 10, 28, 12);

  group('the diff', () {
    late _FakePlatform platform;
    late _FakePermissions permissions;
    late List<ProtocolReminderInput> inputs;
    late ProtocolReminderScheduler scheduler;

    setUp(() {
      platform = _FakePlatform(newYork);
      permissions = _FakePermissions();
      inputs = <ProtocolReminderInput>[
        _input('trt', today, '09:00'),
        _input('creatine', today, '17:00'),
        _input('trt', tomorrow, '09:00'),
      ];
      scheduler = _scheduler(
        platform: platform,
        permissions: permissions,
        inputs: () => inputs,
        clock: () => now,
      );
    });

    tearDown(() => scheduler.dispose());

    test('cancels stale reminders, schedules missing ones, and leaves every '
        'other notification alone, with no cancel-all', () async {
      // A rest timer's notifications, and a reminder the plan dropped.
      platform.pending[7] = const PendingProtocolNotification(id: 7);
      platform.pending[8] =
          const PendingProtocolNotification(id: 8, payload: '{"kind":"rest"}');
      final stale = protocolReminderId(today, '13:00');
      platform.pending[stale] = PendingProtocolNotification(
        id: stale,
        payload: protocolReminderPayload(today),
      );

      await scheduler.reconcile();

      expect(platform.cancelled, <int>[stale]);
      expect(platform.scheduledIds, <int>{
        protocolReminderId(today, '09:00'),
        protocolReminderId(today, '17:00'),
        protocolReminderId(tomorrow, '09:00'),
      });
      expect(platform.pending.keys, containsAll(<int>[7, 8]));
      expect(
        platform.calls.where(
          (call) => !call.startsWith('schedule') && !call.startsWith('cancel'),
        ),
        <String>['localLocation', 'pendingNotifications'],
      );

      // The plan drops tomorrow: only its reminder goes, and nothing still
      // pending is scheduled again.
      platform.calls.clear();
      platform.cancelled.clear();
      inputs = inputs.sublist(0, 2);
      await scheduler.reconcile();

      expect(platform.cancelled, <int>[protocolReminderId(tomorrow, '09:00')]);
      expect(platform.calls.where((call) => call.startsWith('schedule')),
          isEmpty);
      expect(platform.pending.keys, containsAll(<int>[7, 8]));
      expect(scheduler.status.horizonEnd, today.addDays(13));
    });

    test('schedules every reminder again after the zone changes (CUJ 8)',
        () async {
      await scheduler.reconcile();
      final lisbon = tz.getLocation('Europe/Lisbon');
      platform.location = lisbon;
      platform.calls.clear();

      await scheduler.reconcile();

      // 12:00 UTC is 12:00 in Lisbon: today's 09:00 has passed there and
      // goes; the other two are scheduled again at Lisbon instants.
      expect(platform.cancelled, <int>[protocolReminderId(today, '09:00')]);
      expect(
        platform.calls.where((c) => c.startsWith('schedule')),
        <String>[
          'schedule ${protocolReminderId(today, '17:00')}',
          'schedule ${protocolReminderId(tomorrow, '09:00')}',
        ],
      );
      expect(
        platform.notifications[protocolReminderId(tomorrow, '09:00')]!
            .scheduledAt
            .toUtc(),
        // 09:00 WET, Lisbon time.
        DateTime.utc(2026, 10, 29, 9),
      );
    });

    test('runs one at a time: triggers during a run mark it dirty, and '
        'exactly one more run follows', () async {
      platform.gate = Completer<void>();
      final first = scheduler.reconcile();
      await pumpEventQueue();
      final second = scheduler.reconcile();
      final third = scheduler.reconcile();
      await pumpEventQueue();
      expect(platform.runs, 1);

      platform.gate!.complete();
      platform.gate = null;
      await Future.wait(<Future<void>>[first, second, third]);

      expect(platform.runs, 2);
      expect(platform.maxActiveRuns, 1);
    });

    test('a failed run leaves what is pending, and the next trigger runs',
        () async {
      platform.failPending = true;
      await scheduler.reconcile();
      expect(platform.scheduledIds, isEmpty);

      platform.failPending = false;
      await scheduler.reconcile();
      expect(platform.scheduledIds, hasLength(3));
    });
  });

  group('triggers', () {
    late _FakePlatform platform;
    late _FakePermissions permissions;
    late StreamController<void> planChanges;
    late StreamController<DateTime?> syncs;
    late ProtocolReminderScheduler scheduler;
    final taps = <ProtocolDayDate>[];

    setUp(() {
      platform = _FakePlatform(newYork);
      permissions = _FakePermissions();
      planChanges = StreamController<void>.broadcast();
      syncs = StreamController<DateTime?>.broadcast();
      taps.clear();
      scheduler = _scheduler(
        platform: platform,
        permissions: permissions,
        inputs: () => <ProtocolReminderInput>[_input('trt', today, '09:00')],
        clock: () => now,
        planChanges: () => planChanges.stream,
        syncs: () => syncs.stream,
      );
    });

    tearDown(() async {
      await scheduler.dispose();
      await planChanges.close();
      await syncs.close();
    });

    test('app start initializes the plugin and runs', () async {
      await scheduler.start(onReminderTapped: taps.add);

      expect(platform.calls.first, 'initialize');
      expect(platform.runs, 1);
      expect(platform.scheduledIds, <int>{protocolReminderId(today, '09:00')});
    });

    test('plan and Dose writes run once, 500 ms after the last of a burst',
        () async {
      await scheduler.start(onReminderTapped: taps.add);
      expect(platform.runs, 1);

      planChanges.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      planChanges.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      planChanges.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(platform.runs, 1, reason: 'still inside the debounce');

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(platform.runs, 2);
    });

    test('a change of the last successful sync runs; its first reading '
        'and repeats do not', () async {
      await scheduler.start(onReminderTapped: taps.add);
      expect(platform.runs, 1);

      syncs.add(DateTime.utc(2026, 10, 28, 11));
      await pumpEventQueue();
      expect(platform.runs, 1, reason: 'the stored value, not a sync');

      syncs.add(DateTime.utc(2026, 10, 28, 11));
      await pumpEventQueue();
      expect(platform.runs, 1);

      syncs.add(DateTime.utc(2026, 10, 28, 12, 5));
      await pumpEventQueue();
      expect(platform.runs, 2);
    });

    test('resume runs through reconcile', () async {
      await scheduler.start(onReminderTapped: taps.add);
      await scheduler.reconcile();
      expect(platform.runs, 2);
    });

    test('an Android tap, warm or from a cold start, reports its date',
        () async {
      platform.launch = protocolReminderPayload(today);
      await scheduler.start(onReminderTapped: taps.add);
      expect(taps, <ProtocolDayDate>[today]);

      platform.onTap!(protocolReminderPayload(tomorrow));
      platform.onTap!('{"kind":"rest"}');
      platform.onTap!(null);
      expect(taps, <ProtocolDayDate>[today, tomorrow]);
    });

    test('a first permission read that fails still starts every trigger',
        () async {
      permissions.failingReads = 1;
      await scheduler.start(onReminderTapped: taps.add);

      expect(planChanges.hasListener, isTrue);
      expect(syncs.hasListener, isTrue);
      expect(platform.runs, 1);
      expect(platform.scheduledIds, <int>{protocolReminderId(today, '09:00')});

      planChanges.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(platform.runs, 2);
    });

    test(
        'with no notification system, it listens to nothing and schedules '
        'nothing', () async {
      permissions.status = TimerBackgroundPermissionStatus.unsupported;
      await scheduler.start(onReminderTapped: taps.add);

      expect(planChanges.hasListener, isFalse);
      expect(syncs.hasListener, isFalse);
      expect(platform.runs, 0);
      expect(
        scheduler.status.permission,
        TimerBackgroundPermissionStatus.unsupported,
      );
    });
  });

  group('when nothing should be scheduled', () {
    late _FakePlatform platform;
    late _FakePermissions permissions;
    var deviceOn = true;
    var remindersOn = true;
    late ProtocolReminderScheduler scheduler;

    setUp(() {
      platform = _FakePlatform(newYork);
      permissions = _FakePermissions();
      deviceOn = true;
      remindersOn = true;
      scheduler = _scheduler(
        platform: platform,
        permissions: permissions,
        inputs: () => <ProtocolReminderInput>[
          _input('trt', today, '09:00', remindersEnabled: remindersOn),
        ],
        clock: () => now,
        deviceSwitchOn: () => deviceOn,
        anyProtocolRemindersOn: () => remindersOn,
      );
    });

    tearDown(() => scheduler.dispose());

    Future<void> scheduleThenRun(void Function() change) async {
      await scheduler.reconcile();
      expect(platform.scheduledIds, hasLength(1));
      platform.pending[7] = const PendingProtocolNotification(id: 7);
      change();
      await scheduler.reconcile();
    }

    test('the device switch off cancels its own reminders and schedules none',
        () async {
      await scheduleThenRun(() => deviceOn = false);

      expect(platform.cancelled, <int>[protocolReminderId(today, '09:00')]);
      expect(platform.pending.keys, <int>[7]);
      expect(scheduler.status.deviceSwitchOn, isFalse);
      expect(scheduler.status.horizonEnd, isNull);
    });

    test('no Protocol with reminders on does the same', () async {
      await scheduleThenRun(() => remindersOn = false);

      expect(platform.cancelled, <int>[protocolReminderId(today, '09:00')]);
      expect(platform.pending.keys, <int>[7]);
      expect(scheduler.status.remindersRequested, isFalse);
      expect(scheduler.status.horizonEnd, isNull);
    });

    test('never asked for permission (CUJ 12): schedules none and asks the '
        'banner to show; allowing schedules', () async {
      permissions.status = TimerBackgroundPermissionStatus.notDetermined;
      await scheduler.reconcile();

      expect(platform.scheduledIds, isEmpty);
      expect(scheduler.status.needsPermission, isTrue);
      expect(permissions.requests, 0);

      permissions.answer = TimerBackgroundPermissionStatus.granted;
      final answer = await scheduler.requestPermission();

      expect(answer, TimerBackgroundPermissionStatus.granted);
      expect(permissions.requests, 1);
      expect(platform.scheduledIds, <int>{protocolReminderId(today, '09:00')});
      expect(scheduler.status.needsPermission, isFalse);
    });

    test(
        'CUJ 12: the banner shows for a Protocol with reminders on even '
        'when none of its timed doses falls in the horizon', () async {
      final platform = _FakePlatform(newYork);
      final permissions = _FakePermissions()
        ..status = TimerBackgroundPermissionStatus.notDetermined;
      // "Daily" starts in 3 weeks, so the horizon holds none of its doses.
      final later = _scheduler(
        platform: platform,
        permissions: permissions,
        inputs: () => <ProtocolReminderInput>[
          _input('trt', today.addDays(21), '09:00'),
        ],
        clock: () => now,
        anyProtocolRemindersOn: () => true,
      );
      addTearDown(later.dispose);

      await later.reconcile();

      expect(later.status.remindersRequested, isTrue);
      expect(later.status.needsPermission, isTrue);
      expect(platform.scheduledIds, isEmpty);
    });

    test('permission denied schedules none', () async {
      permissions.status = TimerBackgroundPermissionStatus.denied;
      await scheduler.reconcile();

      expect(platform.scheduledIds, isEmpty);
      expect(scheduler.status.needsPermission, isFalse);
      expect(scheduler.status.horizonEnd, isNull);
    });
  });

  group('text and payload', () {
    test('the text is generic and the payload carries only a kind and a '
        'local date', () async {
      final platform = _FakePlatform(newYork);
      final scheduler = _scheduler(
        platform: platform,
        permissions: _FakePermissions(),
        inputs: () => <ProtocolReminderInput>[
          _input('trt', today, '09:00'),
          _input('agemate', today, '09:00'),
        ],
        clock: () => now,
      );
      addTearDown(scheduler.dispose);

      await scheduler.reconcile();

      final notification =
          platform.notifications[protocolReminderId(today, '09:00')]!;
      expect(notification.title, 'Supplements');
      expect(notification.channelName, 'Reminders');
      expect(
        notification.body,
        'Planned for ${DateFormat.jm().format(DateTime(2000, 1, 1, 9))}',
      );
      expect(notification.body, matches(RegExp(r'^Planned for 9:00\sAM$')));
      expect(
        jsonDecode(notification.payload),
        <String, Object?>{'kind': 'protocolReminder', 'localDate': '2026-10-28'},
      );
      expect(notification.scheduledAt.toUtc(), DateTime.utc(2026, 10, 28, 13));
    });

    test('a payload reads back to its date, and nothing else does', () {
      expect(
        protocolReminderDateFromPayload(protocolReminderPayload(today)),
        today,
      );
      expect(protocolReminderDateFromPayload(null), isNull);
      expect(protocolReminderDateFromPayload(''), isNull);
      expect(protocolReminderDateFromPayload('not json'), isNull);
      expect(protocolReminderDateFromPayload('{"kind":"rest"}'), isNull);
      expect(
        protocolReminderDateFromPayload(
          '{"kind":"protocolReminder","localDate":"2026-13-01"}',
        ),
        isNull,
      );
    });

    test('initialization and runs request no permission', () async {
      final platform = _FakePlatform(newYork);
      final permissions = _FakePermissions()
        ..status = TimerBackgroundPermissionStatus.notDetermined;
      final scheduler = _scheduler(
        platform: platform,
        permissions: permissions,
        inputs: () => <ProtocolReminderInput>[_input('trt', today, '09:00')],
        clock: () => now,
      );
      addTearDown(scheduler.dispose);

      await scheduler.start(onReminderTapped: (_) {});
      await scheduler.reconcile();

      expect(permissions.requests, 0);
      expect(permissions.reads, greaterThan(0));
    });
  });

  group('over the repository and in-memory SQLite', () {
    late AppDatabase database;
    late _FakePlatform platform;
    late ProviderContainer container;
    late DateTime clock;

    setUp(() {
      database = AppDatabase.inMemory();
      clock = DateTime(2026, 10, 28, 8);
      // The test process's own offset, fixed: the repository freezes a
      // Dose's local date and time in the process zone.
      platform = _FakePlatform(_fixedOffset(clock.timeZoneOffset));
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    ProviderContainer containerWith({bool locked = false}) {
      return ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) => database),
          protocolReminderPlatformProvider.overrideWith((ref) => platform),
          timerBackgroundSchedulerProvider
              .overrideWith((ref) => _FakePermissions()),
          settingsRepositoryProvider
              .overrideWith((ref) => InMemorySettingsRepository()),
          protocolsClockProvider.overrideWithValue(() => clock),
          protocolsLockStoreProvider
              .overrideWith((ref) => _LockStore(enabled: locked)),
        ],
      );
    }

    Future<void> waitForRuns(int runs) async {
      for (var attempt = 0; attempt < 100 && platform.runs < runs; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(platform.runs, greaterThanOrEqualTo(runs));
      await pumpEventQueue();
    }

    test('CUJs 1 and 2: one 09:00 reminder for the stack, kept while '
        'AgeMate is unfilled, gone once both are logged', () async {
      container = containerWith();
      final repositories = container.read(trainingRepositoriesProvider);
      final stack = await _seedDailyStack(repositories, today);
      final scheduler = container.read(protocolReminderSchedulerProvider);

      await scheduler.start(onReminderTapped: (_) {});

      final nine = protocolReminderId(today, '09:00');
      final five = protocolReminderId(today, '17:00');
      expect(platform.scheduledIds, containsAll(<int>[nine, five]));
      // 09:00 and 17:00 on each of 14 days.
      expect(platform.scheduledIds, hasLength(28));
      expect(scheduler.status.horizonEnd, today.addDays(13));

      // CUJ 2: TRT at 08:40 leaves AgeMate due at 09:00.
      clock = DateTime(2026, 10, 28, 8, 40);
      await repositories.protocols.logDose(stack.dose('trt', clock));
      await waitForRuns(2);
      expect(platform.pending.keys, contains(nine));

      await repositories.protocols.logDose(stack.dose('agemate', clock));
      await waitForRuns(3);
      expect(platform.pending.keys, isNot(contains(nine)));
      expect(platform.pending.keys, contains(five));
      // Tomorrow's 09:00 is still due.
      expect(
        platform.pending.keys,
        contains(protocolReminderId(tomorrow, '09:00')),
      );
    });

    test('the text is the same whether or not the lock is on', () async {
      Future<Map<int, ProtocolReminderNotification>> notificationsWith({
        required bool locked,
      }) async {
        container = containerWith(locked: locked);
        await _seedDailyStack(container.read(trainingRepositoriesProvider),
            today);
        await container
            .read(protocolReminderSchedulerProvider)
            .start(onReminderTapped: (_) {});
        final notifications = Map<int, ProtocolReminderNotification>.of(
          platform.notifications,
        );
        container.dispose();
        await database.close();
        database = AppDatabase.inMemory();
        platform = _FakePlatform(platform.location);
        return notifications;
      }

      final unlocked = await notificationsWith(locked: false);
      final locked = await notificationsWith(locked: true);
      container = containerWith();

      expect(locked.keys, unlocked.keys);
      for (final id in unlocked.keys) {
        expect(locked[id]!.title, unlocked[id]!.title);
        expect(locked[id]!.body, unlocked[id]!.body);
        expect(locked[id]!.payload, unlocked[id]!.payload);
        for (final name in <String>['TRT', 'AgeMate', 'Creatine', 'Daily']) {
          expect(locked[id]!.title, isNot(contains(name)));
          expect(locked[id]!.body, isNot(contains(name)));
          expect(locked[id]!.payload, isNot(contains(name)));
        }
      }
    });

    test('reminderInputs: today\'s fills, later dates unfilled, untimed '
        'doses left out', () async {
      container = containerWith();
      final repositories = container.read(trainingRepositoriesProvider);
      final stack = await _seedDailyStack(repositories, today, untimed: true);
      await repositories.protocols.logDose(
        stack.dose('trt', DateTime(2026, 10, 28, 8, 40)),
      );

      final inputs =
          await repositories.protocolPlan.reminderInputs(today, tomorrow);

      expect(
        inputs.map(
          (input) => (
            input.compoundId == stack.ids['trt']
                ? 'trt'
                : input.compoundId == stack.ids['agemate']
                    ? 'agemate'
                    : 'creatine',
            input.localDate,
            input.localTime,
            input.filled,
          ),
        ),
        unorderedEquals(<(String, ProtocolDayDate, String, bool)>[
          ('trt', today, '09:00', true),
          ('agemate', today, '09:00', false),
          ('creatine', today, '17:00', false),
          ('trt', tomorrow, '09:00', false),
          ('agemate', tomorrow, '09:00', false),
          ('creatine', tomorrow, '17:00', false),
        ]),
      );
      expect(inputs.every((input) => input.remindersEnabled), isTrue);
      expect(
        inputs.where((input) => input.compoundId == stack.ids['magnesium']),
        isEmpty,
      );
    });
  });

  group('over the repository: planned days and reminders-on Protocols', () {
    late AppDatabase database;
    late ProviderContainer container;

    setUp(() {
      database = AppDatabase.inMemory();
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) => database)],
      );
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    test(
        'reminderInputs leaves out off-cycle and paused days (CUJs 3 and '
        '5)', () async {
      final repositories = container.read(trainingRepositoriesProvider);
      // On today and tomorrow, off the day after, then on again; the fourth
      // day is paused.
      final stack = await _seedDailyStack(
        repositories,
        today,
        period: ProtocolPeriod(
          cycle: ProtocolCycle(
            onDays: 2,
            offDays: 1,
            anchor: today,
            anchorIsDefault: false,
          ),
          pauses: <ProtocolPause>[
            ProtocolPause(from: today.addDays(3), to: today.addDays(3)),
          ],
        ),
      );

      final inputs = await repositories.protocolPlan
          .reminderInputs(today, today.addDays(4));

      expect(
        inputs.map((input) => input.localDate).toSet(),
        <ProtocolDayDate>{today, tomorrow, today.addDays(4)},
      );
      expect(
        inputs.where((input) => input.compoundId == stack.ids['trt']),
        hasLength(3),
      );
    });

    test(
        'anyProtocolRemindersOn reads the Reminders switch of every '
        'Protocol not archived', () async {
      final repositories = container.read(trainingRepositoriesProvider);
      expect(await repositories.protocolPlan.anyProtocolRemindersOn(), isFalse);

      final stack = await _seedDailyStack(repositories, today);
      expect(await repositories.protocolPlan.anyProtocolRemindersOn(), isTrue);

      await repositories.protocols.archiveProtocol(
        stack.protocolId,
        today: today,
      );
      expect(await repositories.protocolPlan.anyProtocolRemindersOn(), isFalse);
    });
  });

  group('the zone', () {
    test('a zone id the database has is that zone', () {
      expect(
        protocolReminderLocation('America/New_York', Duration.zero).name,
        'America/New_York',
      );
    });

    test(
        'a zone id the database lacks falls back to the phone\'s current '
        'offset, named by it', () {
      final location = protocolReminderLocation(
        'Vendor/Unknown',
        const Duration(hours: 5, minutes: 30),
      );
      final instant = protocolReminderInstant(location, today, '09:00');

      expect(instant.toUtc(), DateTime.utc(2026, 10, 28, 3, 30));
      expect(
        location.name,
        isNot(
          protocolReminderLocation('Vendor/Unknown', const Duration(hours: 5))
              .name,
        ),
      );
    });
  });

  group('the plugin boundary', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    const timerChannel = MethodChannel('perennia/timer_background');
    late List<MethodCall> calls;
    late List<MethodCall> timerCalls;

    setUp(() {
      calls = <MethodCall>[];
      timerCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timerChannel, (call) async {
        timerCalls.add(call);
        return switch (call.method) {
          'pendingProtocolReminders' => <Object?>[
              <String, Object?>{
                'id': -7,
                'payload': protocolReminderPayload(protocolReminderIdEpoch),
              },
            ],
          _ => null,
        };
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'initialize' => true,
          'pendingNotificationRequests' => <Object?>[
              <String, Object?>{
                'id': -1,
                'title': 'Supplements',
                'body': 'Planned for 12:00 AM',
                'payload': protocolReminderPayload(protocolReminderIdEpoch),
              },
            ],
          _ => null,
        };
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timerChannel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    FlutterLocalNotificationsReminderPlatform boundary() {
      return FlutterLocalNotificationsReminderPlatform(
        plugin: FlutterLocalNotificationsPlugin(),
      );
    }

    test('on iOS, initializing turns every permission request off', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();

      await boundary().initialize(onTap: (_) {});

      final initialize = calls.single;
      expect(initialize.method, 'initialize');
      final arguments = Map<String, Object?>.from(initialize.arguments as Map);
      for (final key in <String>[
        'requestAlertPermission',
        'requestSoundPermission',
        'requestBadgePermission',
        'requestProvisionalPermission',
        'requestCriticalPermission',
        'requestProvidesAppNotificationSettings',
      ]) {
        expect(arguments[key], isFalse, reason: key);
      }
      expect(
        calls.map((call) => call.method),
        isNot(contains('requestPermissions')),
      );
    });

    test('on iOS, the pending reminders are read over the timer channel, '
        'not the plugin', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();

      final pending = await boundary().pendingNotifications();

      expect(timerCalls.single.method, 'pendingProtocolReminders');
      expect(pending.single.id, -7);
      expect(
        protocolReminderDateFromPayload(pending.single.payload),
        protocolReminderIdEpoch,
      );
      expect(
        calls.map((call) => call.method),
        isNot(contains('pendingNotificationRequests')),
      );
    });

    test('on Android, initializing asks for nothing, and a reminder is '
        'inexact, private, on the Reminders channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final platform = boundary();

      await platform.initialize(onTap: (_) {});
      expect(calls.single.method, 'initialize');
      expect(
        (calls.single.arguments as Map)['defaultIcon'],
        '@mipmap/ic_launcher',
      );

      final at = tz.TZDateTime(newYork, 2030, 1, 2, 9);
      await platform.schedule(
        ProtocolReminderNotification(
          id: protocolReminderId(
            const ProtocolDayDate(year: 2030, month: 1, day: 2),
            '09:00',
          ),
          title: 'Supplements',
          body: 'Planned for 9:00 AM',
          scheduledAt: at,
          payload: protocolReminderPayload(
            const ProtocolDayDate(year: 2030, month: 1, day: 2),
          ),
          channelName: 'Reminders',
        ),
      );
      final schedule = calls.last;
      expect(schedule.method, 'zonedSchedule');
      final arguments = Map<String, Object?>.from(schedule.arguments as Map);
      final specifics =
          Map<String, Object?>.from(arguments['platformSpecifics'] as Map);
      expect(specifics['scheduleMode'], 'inexactAllowWhileIdle');
      expect(specifics['channelName'], 'Reminders');
      expect(specifics['icon'], '@mipmap/ic_launcher');
      expect(specifics['visibility'], NotificationVisibility.private.index);
      expect(arguments['timeZoneName'], 'America/New_York');

      await platform.cancel(-5);
      final pending = await platform.pendingNotifications();
      expect(calls.last.method, 'pendingNotificationRequests');
      expect(timerCalls, isEmpty);
      expect(pending.single.id, -1);
      expect(
        protocolReminderDateFromPayload(pending.single.payload),
        protocolReminderIdEpoch,
      );

      expect(
        calls.map((call) => call.method),
        isNot(anyOf(contains('cancelAll'), contains('requestNotificationsPermission'))),
      );
      expect(
        calls.map((call) => call.method),
        isNot(contains('requestExactAlarmsPermission')),
      );
    });
  });
}

ProtocolReminderInput _input(
  String compoundId,
  ProtocolDayDate localDate,
  String localTime, {
  bool remindersEnabled = true,
  bool filled = false,
}) {
  return ProtocolReminderInput(
    protocolId: 'daily',
    compoundId: compoundId,
    localDate: localDate,
    localTime: localTime,
    remindersEnabled: remindersEnabled,
    filled: filled,
  );
}

ProtocolReminderScheduler _scheduler({
  required _FakePlatform platform,
  required _FakePermissions permissions,
  required List<ProtocolReminderInput> Function() inputs,
  required DateTime Function() clock,
  Stream<void> Function()? planChanges,
  Stream<DateTime?> Function()? syncs,
  bool Function()? deviceSwitchOn,
  bool Function()? anyProtocolRemindersOn,
}) {
  return ProtocolReminderScheduler(
    platform: platform,
    permissions: permissions,
    readInputs: (from, to) async => inputs()
        .where(
          (input) =>
              input.localDate.compareTo(from) >= 0 &&
              input.localDate.compareTo(to) <= 0,
        )
        .toList(),
    anyProtocolRemindersOn: () async =>
        anyProtocolRemindersOn?.call() ??
        inputs().any((input) => input.remindersEnabled),
    planChanges: planChanges ?? () => const Stream<void>.empty(),
    lastSuccessfulSyncAt:
        syncs ?? () => const Stream<DateTime?>.empty(),
    deviceSwitchOn: () async => deviceSwitchOn?.call() ?? true,
    clock: clock,
    localizations: () => lookupAppLocalizations(const Locale('en')),
  );
}

tz.Location _fixedOffset(Duration offset) {
  return tz.Location(
    'Test/Fixed',
    const <int>[],
    const <int>[],
    <tz.TimeZone>[tz.TimeZone(offset, isDst: false, abbreviation: 'TEST')],
  );
}

class _FakePlatform implements ProtocolReminderPlatform {
  _FakePlatform(this.location);

  tz.Location location;
  final calls = <String>[];
  final pending = <int, PendingProtocolNotification>{};
  final notifications = <int, ProtocolReminderNotification>{};
  final cancelled = <int>[];
  void Function(String? payload)? onTap;
  String? launch;
  Completer<void>? gate;
  bool failPending = false;
  int runs = 0;
  int _activeRuns = 0;
  int maxActiveRuns = 0;

  Set<int> get scheduledIds => notifications.keys.toSet();

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    calls.add('initialize');
    this.onTap = onTap;
  }

  @override
  Future<String?> launchPayload() async => launch;

  @override
  Future<tz.Location> localLocation() async {
    calls.add('localLocation');
    runs += 1;
    _activeRuns += 1;
    if (_activeRuns > maxActiveRuns) {
      maxActiveRuns = _activeRuns;
    }
    return location;
  }

  @override
  Future<List<PendingProtocolNotification>> pendingNotifications() async {
    calls.add('pendingNotifications');
    try {
      final gate = this.gate;
      if (gate != null) {
        await gate.future;
      }
      if (failPending) {
        throw StateError('pending list unavailable');
      }
      return pending.values.toList();
    } finally {
      _activeRuns -= 1;
    }
  }

  @override
  Future<void> schedule(ProtocolReminderNotification notification) async {
    calls.add('schedule ${notification.id}');
    notifications[notification.id] = notification;
    pending[notification.id] = PendingProtocolNotification(
      id: notification.id,
      payload: notification.payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel $id');
    cancelled.add(id);
    pending.remove(id);
    notifications.remove(id);
  }

  @override
  Future<void> openNotificationSettings() async {
    calls.add('openNotificationSettings');
  }
}

class _FakePermissions implements TimerBackgroundScheduler {
  TimerBackgroundPermissionStatus status =
      TimerBackgroundPermissionStatus.granted;
  TimerBackgroundPermissionStatus answer =
      TimerBackgroundPermissionStatus.granted;
  int requests = 0;
  int reads = 0;

  /// How many of the next reads throw, as a failed channel call does.
  int failingReads = 0;

  @override
  Future<TimerBackgroundPermissionStatus> notificationPermissionStatus() async {
    reads += 1;
    if (failingReads > 0) {
      failingReads -= 1;
      throw PlatformException(code: 'unavailable');
    }
    return status;
  }

  @override
  Future<TimerBackgroundPermissionStatus> requestPermissionIfNeeded() async {
    requests += 1;
    status = answer;
    return answer;
  }

  @override
  Future<TimerBackgroundPermissionStatus> schedule(
    TimerBackgroundSchedule schedule,
  ) async {
    return status;
  }

  @override
  Future<void> cancel(String timerId) async {}
}

class _LockStore implements ProtocolsLockStore {
  _LockStore({required this.enabled});

  bool enabled;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool enabled) async => this.enabled = enabled;

  @override
  Future<String?> readPinHash() async => enabled ? 'hash' : null;

  @override
  Future<void> writePinHash(String hash) async {}

  @override
  Future<void> clearPin() async {}
}

/// The CUJ 1 stack: "Daily", reminders on, TRT and AgeMate at 09:00 and
/// creatine at 17:00 (and, with [untimed], magnesium twice at any time).
Future<_Stack> _seedDailyStack(
  TrainingRepositories repositories,
  ProtocolDayDate today, {
  bool untimed = false,
  ProtocolPeriod? period,
}) async {
  final compounds = <String, CompoundRecord>{};
  Future<void> compound(String key, String name, DoseUnit unit) async {
    final result = await repositories.protocols.createCompound(
      CompoundDraft(name: name, defaultUnit: unit, defaultRoute: DoseRoute.oral),
    );
    compounds[key] = CompoundRecord(
      id: result.compoundId,
      name: name,
      defaultUnit: unit,
      defaultRoute: DoseRoute.oral,
      updatedAt: DateTime.utc(2026, 10, 1),
    );
  }

  await compound('trt', 'TRT', DoseUnit.milliliter);
  await compound('agemate', 'AgeMate', DoseUnit.capsule);
  await compound('creatine', 'Creatine', DoseUnit.gram);
  if (untimed) {
    await compound('magnesium', 'Magnesium', DoseUnit.capsule);
  }

  ScheduleDraft draft(ScheduleRule rule, DoseUnit unit) => ScheduleDraft(
        rule: rule,
        doseAmountValue: 1,
        doseAmountEntered: '1',
        doseUnit: unit,
        route: DoseRoute.oral,
      );
  ScheduleRule dailyAt(String time) => TimedScheduleRule(
        days: const DailyScheduleDays(),
        times: <String>[time],
      );

  final protocol = await repositories.protocols.createProtocol(
    ProtocolDraft(
      name: 'Daily',
      startLocalDate: today,
      period: period,
      remindersEnabled: true,
      compoundIds: <String>[for (final record in compounds.values) record.id],
      schedulesByCompoundId: <String, ScheduleDraft?>{
        compounds['trt']!.id: draft(dailyAt('09:00'), DoseUnit.milliliter),
        compounds['agemate']!.id: draft(dailyAt('09:00'), DoseUnit.capsule),
        compounds['creatine']!.id: draft(dailyAt('17:00'), DoseUnit.gram),
        if (untimed)
          compounds['magnesium']!.id: draft(
            UntimedScheduleRule(days: const DailyScheduleDays(), count: 2),
            DoseUnit.capsule,
          ),
      },
    ),
    today: today,
  );
  return _Stack(compounds, protocol.protocolId);
}

class _Stack {
  _Stack(this.compounds, this.protocolId);

  final Map<String, CompoundRecord> compounds;
  final String protocolId;

  Map<String, String> get ids => <String, String>{
        for (final entry in compounds.entries) entry.key: entry.value.id,
      };

  DoseSnapshotDraft dose(String key, DateTime tookAt) {
    final compound = compounds[key]!;
    return DoseSnapshotDraft.fromCompound(
      compound: compound,
      amountValue: 1,
      amountEntered: '1',
      unit: compound.defaultUnit,
      route: DoseRoute.oral,
      tookAt: tookAt,
      protocol: ProtocolOptionRecord(id: protocolId, name: 'Daily'),
    );
  }
}
