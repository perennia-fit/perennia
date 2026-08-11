import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/settings/services/client_crash_reporting.dart';

void main() {
  group('client crash reporting', () {
    test('crash reporting is default-off and persisted', () async {
      final directory = await Directory.systemTemp.createTemp('perennia-settings-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}settings.json',
      );

      final repository = FileSettingsRepository(settingsFile: () async => file);
      expect((await repository.load()).crashReportingEnabled, isFalse);

      await repository.save(
        AppSettings.defaults.copyWith(crashReportingEnabled: true),
      );

      final reloaded = FileSettingsRepository(settingsFile: () async => file);
      expect((await reloaded.load()).crashReportingEnabled, isTrue);
    });

    test('toggle gates Sentry initialization and capture', () async {
      final sdk = _FakeSentryFlutterSdk();
      final reporter = SentryClientCrashReporter(
        config: const ClientCrashReportingConfig(
          dsn: 'https://public@example.com/1',
          environment: 'test',
        ),
        sdk: sdk,
      );

      await reporter.setEnabled(false);
      await reporter.captureException(StateError('off'), StackTrace.current);

      expect(sdk.initOptions, isEmpty);
      expect(sdk.capturedThrowables, isEmpty);

      await reporter.setEnabled(true);
      await reporter.captureException(StateError('on'), StackTrace.current);

      expect(sdk.initOptions, hasLength(1));
      expect(sdk.initOptions.single.dsn, 'https://public@example.com/1');
      expect(sdk.initOptions.single.environment, 'test');
      expect(sdk.initOptions.single.sendDefaultPii, isFalse);
      expect(sdk.initOptions.single.enableAutoSessionTracking, isFalse);
      expect(sdk.initOptions.single.attachScreenshot, isFalse);
      expect(sdk.capturedThrowables, hasLength(1));

      await reporter.setEnabled(false);
      await reporter.captureException(
          StateError('off again'), StackTrace.current);

      expect(sdk.closeCount, 1);
      expect(sdk.capturedThrowables, hasLength(1));
    });

    test('enabled toggle does not initialize Sentry without a DSN', () async {
      final sdk = _FakeSentryFlutterSdk();
      final reporter = SentryClientCrashReporter(
        config: const ClientCrashReportingConfig(dsn: ''),
        sdk: sdk,
      );

      await reporter.setEnabled(true);
      await reporter.captureException(
          StateError('missing DSN'), StackTrace.current);

      expect(sdk.initOptions, isEmpty);
      expect(sdk.capturedThrowables, isEmpty);
    });

    test('event scrubber keeps stack and device class only', () {
      final event = SentryEvent(
        message: SentryMessage(
          'Back Squat failed for leona@example.com',
        ),
        tags: const <String, String>{
          'exerciseName': 'Back Squat',
          'authToken': 'secret-token',
        },
        // ignore: deprecated_member_use
        extra: const <String, dynamic>{
          'bodyWeight': 82.4,
          'comment': 'felt heavy',
        },
        user: SentryUser(
          id: 'user-1',
          email: 'leona@example.com',
          username: 'leona',
        ),
        request: SentryRequest(
          url: 'https://api.example.test/sync?comment=Back+Squat',
          queryString: 'comment=Back Squat',
          data: const <String, Object?>{
            'reps': 5,
            'load': 120,
          },
          headers: const <String, String>{
            'authorization': 'Bearer secret-token',
          },
        ),
        contexts: Contexts(
          device: SentryDevice(
            name: 'Leona phone',
            family: 'iPhone',
            model: 'iPhone16,2',
            manufacturer: 'Apple',
            brand: 'Apple',
            arch: 'arm64',
            simulator: false,
            deviceUniqueIdentifier: 'device-123',
            batteryLevel: 84,
            freeMemory: 1024,
          ),
          operatingSystem: SentryOperatingSystem(name: 'iOS'),
        ),
        breadcrumbs: <Breadcrumb>[
          Breadcrumb(
            message: 'Back Squat set comment: felt heavy',
            category: 'training.saveSet',
            data: const <String, dynamic>{
              'exerciseName': 'Back Squat',
              'comment': 'felt heavy',
              'bodyWeight': 82.4,
              'email': 'leona@example.com',
              'reps': 5,
              'load': 120,
              'method': 'POST',
              'status_code': 200,
            },
          ),
        ],
        exceptions: <SentryException>[
          SentryException(
            type: 'StateError',
            value: 'Back Squat failed for leona@example.com',
            stackTrace: SentryStackTrace(
              frames: <SentryStackFrame>[
                SentryStackFrame(
                  fileName: 'training_screen.dart',
                  function: 'saveSet',
                  lineNo: 42,
                  contextLine: 'final comment = "felt heavy";',
                  vars: const <String, Object?>{
                    'exerciseName': 'Back Squat',
                  },
                ),
              ],
            ),
          ),
        ],
      );

      final scrubbed = scrubClientCrashEvent(event, Hint());
      expect(scrubbed, isNotNull);

      final encoded = jsonEncode(scrubbed!.toJson());
      for (final forbidden in <String>[
        'Back Squat',
        'leona@example.com',
        'secret-token',
        'felt heavy',
        'bodyWeight',
        'reps',
        'load',
        'device-123',
        'Leona phone',
        'comment=',
      ]) {
        expect(encoded, isNot(contains(forbidden)));
      }

      expect(encoded, contains('StateError'));
      expect(encoded, contains('[Filtered]'));
      expect(encoded, contains('training_screen.dart'));
      expect(encoded, contains('saveSet'));
      expect(encoded, contains('iPhone16,2'));
      expect(scrubbed.message, isNull);
      expect(scrubbed.tags, isNull);
      // ignore: deprecated_member_use
      expect(scrubbed.extra, isNull);
      expect(scrubbed.user, isNull);
      expect(scrubbed.request, isNull);
      expect(scrubbed.contexts.device?.deviceUniqueIdentifier, isNull);
      expect(scrubbed.contexts.operatingSystem, isNull);
    });

    test('breadcrumb scrubber strips disallowed fields', () {
      final breadcrumb = Breadcrumb(
        message: 'Back Squat comment from leona@example.com',
        category: 'training.saveSet',
        data: const <String, dynamic>{
          'exerciseName': 'Back Squat',
          'comment': 'felt heavy',
          'bodyWeight': 82.4,
          'authToken': 'secret-token',
          'email': 'leona@example.com',
          'reps': 5,
          'load': 120,
          'method': 'POST',
          'status_code': 200,
        },
      );

      final scrubbed = scrubClientCrashBreadcrumb(breadcrumb, Hint());
      expect(scrubbed, isNotNull);

      final encoded = jsonEncode(scrubbed!.toJson());
      for (final forbidden in <String>[
        'Back Squat',
        'leona@example.com',
        'secret-token',
        'felt heavy',
        'bodyWeight',
        'reps',
        'load',
      ]) {
        expect(encoded, isNot(contains(forbidden)));
      }

      expect(scrubbed.message, isNull);
      expect(scrubbed.data, <String, dynamic>{
        'method': 'POST',
        'status_code': 200,
      });
    });

    test(
        'never admits Protocols content (Compound/Dose) into a scrubbed '
        'breadcrumb, even if a caller tried (PROTOCOLS.md §4.1)',
        () async {
      final breadcrumb = Breadcrumb(
        message: 'Logged 250 mg of Redacted Compound Name',
        category: 'protocols.logDose',
        data: const <String, dynamic>{
          'compoundName': 'Redacted Compound Name',
          'compoundId': 'compound-secret-123',
          'doseId': 'dose-secret-456',
          'amountEntered': '250',
          'amountValue': 250,
          'unit': 'milligram',
          'route': 'subcutaneous',
          // The narrow allowlist stays operational-only.
          'method': 'POST',
          'status_code': 200,
        },
      );

      final scrubbed = scrubClientCrashBreadcrumb(breadcrumb, Hint());
      expect(scrubbed, isNotNull);

      final encoded = jsonEncode(scrubbed!.toJson());
      for (final forbidden in <String>[
        'Redacted Compound Name',
        'compound-secret-123',
        'dose-secret-456',
        '250',
        'milligram',
        'subcutaneous',
        'compoundName',
        'amountEntered',
      ]) {
        expect(encoded, isNot(contains(forbidden)));
      }

      expect(scrubbed.message, isNull);
      expect(scrubbed.data, <String, dynamic>{
        'method': 'POST',
        'status_code': 200,
      });
    });

    test(
        'never admits a Protocols value into a scrubbed crash exception '
        ' (PROTOCOLS.md §4.1)', () async {
      final event = SentryEvent(
        exceptions: <SentryException>[
          SentryException(
            type: 'DoseValidationException',
            value: 'Rejected dose of 250 mg Redacted Compound Name '
                'via subcutaneous route',
          ),
        ],
      );

      final scrubbed = scrubClientCrashEvent(event, Hint());
      expect(scrubbed, isNotNull);

      final exception = scrubbed!.exceptions!.single;
      final encoded = jsonEncode(exception.toJson());
      expect(encoded, isNot(contains('Redacted Compound Name')));
      expect(encoded, isNot(contains('subcutaneous')));
      expect(encoded, isNot(contains('250')));
      expect(exception.type, 'DoseValidationException');
      expect(exception.value, filteredCrashValue);
    });
  });
}

class _FakeSentryFlutterSdk implements SentryFlutterSdk {
  final initOptions = <SentryFlutterOptions>[];
  final capturedThrowables = <Object?>[];
  final breadcrumbs = <Breadcrumb>[];
  var closeCount = 0;
  var _enabled = false;

  @override
  bool get isEnabled => _enabled;

  @override
  Future<void> init(
    FutureOr<void> Function(SentryFlutterOptions options) configure,
  ) async {
    final options = SentryFlutterOptions();
    final result = configure(options);
    if (result is Future<void>) {
      await result;
    }
    initOptions.add(options);
    _enabled = true;
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    _enabled = false;
  }

  @override
  Future<SentryId> captureException(
    Object throwable, {
    Object? stackTrace,
    Hint? hint,
  }) async {
    capturedThrowables.add(throwable);
    return SentryId.newId();
  }

  @override
  Future<void> addBreadcrumb(Breadcrumb breadcrumb, {Hint? hint}) async {
    breadcrumbs.add(breadcrumb);
  }
}
