import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show basicLocaleListResolution;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/repositories/settings_repository.dart';
import '../../sync/repositories/sync_repository.dart';
import '../../training/services/timer_background_scheduler.dart';
import '../controllers/protocols_day_controller.dart' show protocolsClockProvider;
import 'protocol_reminder_plan.dart';

/// The payload `kind` every Supplement reminder carries (D5). The reconciler
/// cancels only notifications with this kind, and the iOS `AppDelegate`
/// routes a tap by it.
const String protocolReminderPayloadKind = 'protocolReminder';

/// A reminder's payload: its kind and local date, and nothing else (NFR
/// Privacy). It never names a Compound, a Protocol or an amount.
String protocolReminderPayload(ProtocolDayDate localDate) {
  return jsonEncode(<String, Object?>{
    'kind': protocolReminderPayloadKind,
    'localDate': localDate.storageValue,
  });
}

/// The local date a reminder payload carries, or null when [payload] isn't
/// a Supplement reminder's.
ProtocolDayDate? protocolReminderDateFromPayload(String? payload) {
  if (payload == null || payload.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map || decoded['kind'] != protocolReminderPayloadKind) {
      return null;
    }
    final localDate = decoded['localDate'];
    return localDate is String ? ProtocolDayDate.parse(localDate) : null;
  } on FormatException {
    return null;
  }
}

/// One reminder handed to the plugin.
@immutable
final class ProtocolReminderNotification {
  const ProtocolReminderNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledAt,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime scheduledAt;
  final String payload;
}

/// One notification the plugin reports as pending: its id and payload. The
/// rest timer's notifications have no reminder payload.
@immutable
final class PendingProtocolNotification {
  const PendingProtocolNotification({required this.id, this.payload});

  final int id;
  final String? payload;
}

/// The small boundary over `flutter_local_notifications`, `timezone` and
/// `flutter_timezone`, so the reconciler runs against a fake in tests. It has
/// no "cancel all": the reconciler cancels its own reminders one by one, and
/// never the rest timer's notifications (D5).
abstract interface class ProtocolReminderPlatform {
  /// Initializes the plugin with every permission request turned off, so it
  /// never asks at startup. [onTap] receives the payload of a tapped
  /// notification the plugin delivers (Android; iOS taps reach the app over
  /// the timer channel instead, file 53).
  Future<void> initialize({required void Function(String? payload) onTap});

  /// The payload of the notification that launched the app (an Android cold
  /// start), or null.
  Future<String?> launchPayload();

  /// The phone's zone now, read afresh each time so travel takes effect on
  /// the next run (CUJ 8).
  Future<tz.Location> localLocation();

  Future<List<PendingProtocolNotification>> pendingNotifications();

  /// Schedules [notification], replacing any pending one with its id.
  Future<void> schedule(ProtocolReminderNotification notification);

  Future<void> cancel(int id);

  /// Opens the system settings where the user can allow notifications.
  Future<void> openNotificationSettings();
}

/// [ProtocolReminderPlatform] over the real plugins.
final class FlutterLocalNotificationsReminderPlatform
    implements ProtocolReminderPlatform {
  FlutterLocalNotificationsReminderPlatform({
    FlutterLocalNotificationsPlugin? plugin,
    AppLocalizations Function()? localizations,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _localizations = localizations ?? protocolReminderLocalizations;

  /// The Android channel's id. Its user-visible name is "Reminders".
  static const String androidChannelId = 'protocol_reminders';

  /// The small icon of a reminder, and the plugin's default (file 49).
  static const String androidIcon = '@mipmap/ic_launcher';

  final FlutterLocalNotificationsPlugin _plugin;
  final AppLocalizations Function() _localizations;
  static bool _timeZonesLoaded = false;

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(androidIcon),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestProvisionalPermission: false,
          requestCriticalPermission: false,
          requestProvidesAppNotificationSettings: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
  }

  @override
  Future<String?> launchPayload() async {
    // iOS taps never reach the plugin: `AppDelegate` answers them and
    // forwards a reminder's date over the timer channel (file 53).
    if (defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) {
      return null;
    }
    return details.notificationResponse?.payload;
  }

  @override
  Future<tz.Location> localLocation() async {
    if (!_timeZonesLoaded) {
      tz_data.initializeTimeZones();
      _timeZonesLoaded = true;
    }
    final zone = await FlutterTimezone.getLocalTimezone();
    final location = tz.getLocation(zone.identifier);
    tz.setLocalLocation(location);
    return location;
  }

  @override
  Future<List<PendingProtocolNotification>> pendingNotifications() async {
    final pending = await _plugin.pendingNotificationRequests();
    return <PendingProtocolNotification>[
      for (final request in pending)
        PendingProtocolNotification(id: request.id, payload: request.payload),
    ];
  }

  @override
  Future<void> schedule(ProtocolReminderNotification notification) {
    return _plugin.zonedSchedule(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      scheduledDate: notification.scheduledAt,
      payload: notification.payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          androidChannelId,
          _localizations().protocolReminderChannelName,
          icon: androidIcon,
          visibility: NotificationVisibility.private,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> openNotificationSettings() async {
    await _plugin.openAppNotificationSettings();
  }
}

/// The app's strings in the phone's language, for text written where there
/// is no widget context: the reminder's title, body and channel name.
AppLocalizations protocolReminderLocalizations() {
  final locale = basicLocaleListResolution(
    PlatformDispatcher.instance.locales,
    AppLocalizations.supportedLocales,
  );
  return lookupAppLocalizations(locale);
}

/// What the reminder screens show (D5): the permission, whether this phone
/// would remind, and how far ahead it has scheduled. Read from the
/// reconciler's last run; never stored.
@immutable
final class ProtocolReminderStatus {
  const ProtocolReminderStatus({
    this.permission,
    this.deviceSwitchOn = true,
    this.remindersRequested = false,
    this.horizonEnd,
  });

  /// Before the first run.
  static const ProtocolReminderStatus unknown = ProtocolReminderStatus();

  /// The system notification permission, or null before the first run.
  final TimerBackgroundPermissionStatus? permission;

  /// "Reminders on this device" (file 55).
  final bool deviceSwitchOn;

  /// Whether a Protocol with reminders on plans a timed dose in the
  /// scheduling horizon.
  final bool remindersRequested;

  /// The last day reminders are scheduled through (CUJ 11), or null when
  /// this phone schedules none: the device switch is off, nothing asks for
  /// a reminder, or notifications aren't allowed.
  final ProtocolDayDate? horizonEnd;

  /// The Protocol Day view's banner (CUJ 12): a Protocol has reminders on,
  /// the device switch is on, and the user has never been asked.
  bool get needsPermission =>
      remindersRequested &&
      deviceSwitchOn &&
      permission == TimerBackgroundPermissionStatus.notDetermined;

  @override
  bool operator ==(Object other) =>
      other is ProtocolReminderStatus &&
      other.permission == permission &&
      other.deviceSwitchOn == deviceSwitchOn &&
      other.remindersRequested == remindersRequested &&
      other.horizonEnd == horizonEnd;

  @override
  int get hashCode =>
      Object.hash(permission, deviceSwitchOn, remindersRequested, horizonEnd);
}

typedef ProtocolReminderInputReader = Future<List<ProtocolReminderInput>>
    Function(ProtocolDayDate from, ProtocolDayDate to);

/// The reminder reconciler (D5, file 49): keeps the phone's pending
/// Supplement reminders equal to [desiredReminders].
///
/// * **Triggers:** [start] (app start), [reconcile] on resume (from
///   `app.dart`), writes to Protocols, Protocol Members, Schedule Versions or
///   Doses (debounced 500 ms), and a change of `lastSuccessfulSyncAt`. There
///   are no background or timezone-change triggers: travel takes effect on
///   the next open or resume (CUJ 8).
/// * **Runs:** one at a time. A trigger during a run marks it dirty, and one
///   more run follows. Nothing on the logging path waits for it.
/// * **Diff:** it cancels pending reminders the plan no longer wants and
///   schedules the ones missing, matching by payload kind and id. It never
///   cancels anything else, and has no "cancel all". The first run in a
///   process, and any run after the zone changed, schedules every wanted
///   reminder again: a pending reminder's id says its date and time, not
///   the zone it was scheduled in.
/// * **Off:** with the device switch off, no Protocol asking for a reminder,
///   or notifications not allowed, it cancels its own reminders and
///   schedules none (CUJ 12).
///
/// Nothing it does is stored, synced or written to the Activity Log.
class ProtocolReminderScheduler {
  ProtocolReminderScheduler({
    required ProtocolReminderPlatform platform,
    required TimerBackgroundScheduler permissions,
    required ProtocolReminderInputReader readInputs,
    required Stream<void> Function() planChanges,
    required Stream<DateTime?> Function() lastSuccessfulSyncAt,
    required Future<bool> Function() deviceSwitchOn,
    DateTime Function() clock = DateTime.now,
    AppLocalizations Function() localizations = protocolReminderLocalizations,
    Duration debounce = const Duration(milliseconds: 500),
  })  : _platform = platform,
        _permissions = permissions,
        _readInputs = readInputs,
        _planChanges = planChanges,
        _lastSuccessfulSyncAt = lastSuccessfulSyncAt,
        _deviceSwitchOn = deviceSwitchOn,
        _clock = clock,
        _localizations = localizations,
        _debounce = debounce;

  final ProtocolReminderPlatform _platform;
  final TimerBackgroundScheduler _permissions;
  final ProtocolReminderInputReader _readInputs;
  final Stream<void> Function() _planChanges;
  final Stream<DateTime?> Function() _lastSuccessfulSyncAt;
  final Future<bool> Function() _deviceSwitchOn;
  final DateTime Function() _clock;
  final AppLocalizations Function() _localizations;
  final Duration _debounce;

  final StreamController<ProtocolReminderStatus> _statusController =
      StreamController<ProtocolReminderStatus>.broadcast();
  ProtocolReminderStatus _status = ProtocolReminderStatus.unknown;

  bool _started = false;
  bool _disposed = false;
  void Function(ProtocolDayDate localDate)? _onReminderTapped;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  Timer? _debounceTimer;

  Future<void>? _run;
  bool _dirty = false;

  /// The zone the last run scheduled in; null before the first run.
  String? _scheduledZone;

  /// The last run's result.
  ProtocolReminderStatus get status => _status;

  /// The current status, then every change.
  Stream<ProtocolReminderStatus> watchStatus() async* {
    yield _status;
    yield* _statusController.stream;
  }

  /// Starts the reconciler once, after the first frame (file 52): it
  /// initializes the plugin, listens to its triggers, routes an Android
  /// cold-start tap to [onReminderTapped], and runs.
  Future<void> start({
    required void Function(ProtocolDayDate localDate) onReminderTapped,
  }) async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _onReminderTapped = onReminderTapped;
    try {
      await _platform.initialize(onTap: _handleTap);
    } on Object {
      // No plugin here (tests, an unsupported platform): runs still report
      // the permission, and schedule nothing they can't.
    }
    if (_disposed) {
      return;
    }
    final permission = await _readPermission();
    if (permission == TimerBackgroundPermissionStatus.unsupported) {
      // No notification system here (tests, an unsupported platform), and
      // none will appear: nothing to listen for or reconcile.
      _publish(ProtocolReminderStatus(permission: permission));
      return;
    }
    _subscriptions.add(
      _planChanges().listen((_) => _scheduleDebounced(), onError: _ignore),
    );
    var sawFirstSync = false;
    DateTime? lastSync;
    _subscriptions.add(
      _lastSuccessfulSyncAt().listen(
        (at) {
          // The first emission is the stored value, not a sync completing.
          if (sawFirstSync && at != lastSync) {
            unawaited(reconcile());
          }
          sawFirstSync = true;
          lastSync = at;
        },
        onError: _ignore,
      ),
    );
    try {
      _handleTap(await _platform.launchPayload());
    } on Object {
      // Nothing launched the app, or the plugin isn't there.
    }
    await reconcile();
  }

  /// Runs the reconciler, or, while a run is in flight, marks it dirty so
  /// one more run follows. Completes when the reconciler is idle. Never
  /// throws: a run that fails leaves what is pending as it was, for the
  /// next trigger to fix.
  Future<void> reconcile() {
    if (_disposed) {
      return Future<void>.value();
    }
    final current = _run;
    if (current != null) {
      _dirty = true;
      return current;
    }
    final run = _runUntilClean();
    _run = run;
    return run;
  }

  /// Asks for the notification permission through the one permission path
  /// (`requestPermissionIfNeeded`, D5), then runs so reminders follow the
  /// answer.
  Future<TimerBackgroundPermissionStatus> requestPermission() async {
    TimerBackgroundPermissionStatus status;
    try {
      status = await _permissions.requestPermissionIfNeeded();
    } on Object {
      status = TimerBackgroundPermissionStatus.unsupported;
    }
    await reconcile();
    return status;
  }

  /// Opens the system notification settings. Returning to the app resumes
  /// it, which runs the reconciler.
  Future<void> openNotificationSettings() async {
    try {
      await _platform.openNotificationSettings();
    } on Object {
      // Nothing to open here.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounceTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _statusController.close();
  }

  void _scheduleDebounced() {
    if (_disposed) {
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => unawaited(reconcile()));
  }

  void _handleTap(String? payload) {
    final localDate = protocolReminderDateFromPayload(payload);
    if (localDate != null) {
      _onReminderTapped?.call(localDate);
    }
  }

  static void _ignore(Object error) {}

  /// The permission without prompting (file 51); unsupported when the
  /// platform has no answer.
  Future<TimerBackgroundPermissionStatus> _readPermission() async {
    try {
      return await _permissions.notificationPermissionStatus();
    } on Object {
      return TimerBackgroundPermissionStatus.unsupported;
    }
  }

  Future<void> _runUntilClean() async {
    try {
      do {
        _dirty = false;
        try {
          await _runOnce();
        } on Object {
          // See [reconcile].
        }
      } while (_dirty && !_disposed);
    } finally {
      _run = null;
    }
  }

  Future<void> _runOnce() async {
    final permission = await _readPermission();
    if (permission == TimerBackgroundPermissionStatus.unsupported) {
      // No notification system to reconcile against.
      _publish(ProtocolReminderStatus(permission: permission));
      return;
    }

    final deviceSwitchOn = await _deviceSwitchOn();
    final location = await _platform.localLocation();
    final now = tz.TZDateTime.from(_clock(), location);
    final today =
        ProtocolDayDate(year: now.year, month: now.month, day: now.day);
    final inputs = await _readInputs(
      today,
      today.addDays(protocolReminderHorizonDays - 1),
    );
    final remindersRequested = inputs.any((input) => input.remindersEnabled);
    final scheduling = deviceSwitchOn &&
        remindersRequested &&
        permission == TimerBackgroundPermissionStatus.granted;
    final desired = scheduling ? desiredReminders(inputs, now) : null;
    final wanted = <int, ReminderSpec>{
      for (final reminder in desired?.reminders ?? const <ReminderSpec>[])
        reminder.id: reminder,
    };

    final pending = await _platform.pendingNotifications();
    final own = <int>{
      for (final notification in pending)
        if (protocolReminderDateFromPayload(notification.payload) != null)
          notification.id,
    };
    for (final id in own) {
      if (!wanted.containsKey(id)) {
        await _platform.cancel(id);
      }
    }

    final rescheduleAll = _scheduledZone != location.name;
    if (wanted.isNotEmpty) {
      final l10n = _localizations();
      for (final reminder in wanted.values) {
        if (!rescheduleAll && own.contains(reminder.id)) {
          continue;
        }
        await _platform.schedule(_notification(reminder, l10n));
      }
    }
    _scheduledZone = location.name;

    _publish(
      ProtocolReminderStatus(
        permission: permission,
        deviceSwitchOn: deviceSwitchOn,
        remindersRequested: remindersRequested,
        horizonEnd: desired?.horizonEnd,
      ),
    );
  }

  /// The notification for [reminder]. Its text is always generic (D5):
  /// title "Supplements", body "Planned for <time>", whether or not the lock
  /// is on, so turning the lock on later can't leave named reminders queued.
  ProtocolReminderNotification _notification(
    ReminderSpec reminder,
    AppLocalizations l10n,
  ) {
    final minutes = planLocalTimeMinutes(reminder.localTime);
    // The device's time format, as the day's Dose rows use it.
    final time = DateFormat.jm().format(
      DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60),
    );
    return ProtocolReminderNotification(
      id: reminder.id,
      title: l10n.protocolReminderTitle,
      body: l10n.protocolReminderBody(time),
      scheduledAt: reminder.scheduledAt,
      payload: protocolReminderPayload(reminder.localDate),
    );
  }

  void _publish(ProtocolReminderStatus status) {
    if (_disposed || status == _status) {
      return;
    }
    _status = status;
    _statusController.add(status);
  }
}

/// The plugin boundary the reconciler uses. Overridden in tests.
final protocolReminderPlatformProvider = Provider<ProtocolReminderPlatform>(
  (ref) => FlutterLocalNotificationsReminderPlatform(),
);

/// The app's one reminder reconciler. `app.dart` starts it after the first
/// frame and runs it on resume.
final protocolReminderSchedulerProvider =
    Provider<ProtocolReminderScheduler>((ref) {
  final scheduler = ProtocolReminderScheduler(
    platform: ref.watch(protocolReminderPlatformProvider),
    permissions: ref.watch(timerBackgroundSchedulerProvider),
    readInputs: (from, to) => ref
        .read(trainingRepositoriesProvider)
        .protocolPlan
        .reminderInputs(from, to),
    planChanges: () => ref
        .read(trainingRepositoriesProvider)
        .protocolPlan
        .watchReminderInputChanges(),
    lastSuccessfulSyncAt: () => ref
        .read(syncStatusRepositoryProvider)
        .watchStatus()
        .map((status) => status.lastSuccessfulSyncAt),
    deviceSwitchOn: () async => (await ref.read(
      settingsControllerProvider.future,
    ))
        .protocolRemindersOnThisDevice,
    clock: ref.watch(protocolsClockProvider),
  );
  ref.onDispose(() => unawaited(scheduler.dispose()));
  return scheduler;
});

/// The reconciler's status for the reminder screens and the banner.
final protocolReminderStatusProvider =
    StreamProvider<ProtocolReminderStatus>((ref) {
  return ref.watch(protocolReminderSchedulerProvider).watchStatus();
});
