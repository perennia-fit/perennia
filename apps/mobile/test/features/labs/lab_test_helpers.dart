import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/labs/lab_result.dart';
import 'package:perennia/features/labs/controllers/lab_entry_controller.dart';
import 'package:perennia/features/labs/widgets/lab_test_detail_screen.dart';
import 'package:perennia/features/profile/controllers/profile_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/biometric_authenticator.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

/// "Today" for every lab screen test: 25 November 2026.
final DateTime labTestToday = DateTime(2026, 11, 25, 10);

/// Shared set-up for the Lab Results screen and Lab Test detail tests: a
/// real in-memory database, real repositories, and the Protocols lock with a
/// fake store. With a [clock], the lab entry sheet's "today" comes from it.
class LabScreenHarness {
  LabScreenHarness({this.clock})
      : database = AppDatabase.inMemory(),
        lockStore = LabLockStore() {
    repositories = TrainingRepositories(database);
  }

  final AppDatabase database;
  late final TrainingRepositories repositories;
  final LabLockStore lockStore;
  final DateTime Function()? clock;

  List<Override> overrides() => <Override>[
        appDatabaseProvider.overrideWith((ref) => database),
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        profileDisclosureProvider.overrideWithValue(
          const ProfileDisclosure.localOnly(),
        ),
        protocolsLockStoreProvider.overrideWith((ref) => lockStore),
        biometricAuthenticatorProvider.overrideWith((ref) => LabNoBiometrics()),
        protocolsLockControllerProvider.overrideWith(
          () => ProtocolsLockController(
            hasher: const ProtocolsPinHasher(iterations: 10),
          ),
        ),
        if (clock case final clock?) labClockProvider.overrideWithValue(clock),
      ];

  /// Pumps [home] in an app that resolves the Lab Test detail route as
  /// `app.dart` does.
  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          onGenerateRoute: (settings) {
            if (settings.name == LabTestDetailScreen.routeName) {
              final labTestKey = settings.arguments;
              if (labTestKey is! String) return null;
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => LabTestDetailScreen(labTestKey: labTestKey),
              );
            }
            return null;
          },
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Unmounts the app so nothing holds the database when it closes.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> close() => database.close();

  /// Saves one collection through the repository.
  Future<String> save(
    WidgetTester tester, {
    required DateTime date,
    ({int hour, int minute})? time,
    ReportStatus reportStatus = ReportStatus.final_,
    required List<CollectionDraftRow> rows,
  }) {
    return onFakeTime(
      tester,
      () => repositories.labResults.saveCollection(
        CollectionDraft(
          collectedDate: date,
          collectedTime: time,
          reportStatus: reportStatus,
          rows: rows,
        ),
        today: labTestToday,
      ),
    );
  }

  /// A Lab Metric whose key this build's catalogue lacks ("Other"), with
  /// one result written as a later build would.
  Future<({String metricId, String readingId})> seedOther(
    WidgetTester tester, {
    String labTestKey = 'zinc_serum',
    String name = 'Zinc',
    String collected = '2026-02-01',
  }) {
    return onFakeTime(tester, () async {
      final metricId = await repositories.metrics.createMetric(
        MetricDraft(
          name: name,
          unit: 'umol/L',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.custom,
          enabled: true,
          pinned: false,
          sortOrder: 50,
          labTestKey: labTestKey,
        ),
      );
      const readingId = 'other-reading-1';
      await database.into(database.metricReadings).insert(
            MetricReadingsCompanion.insert(
              id: readingId,
              metricId: metricId,
              valueJson: jsonEncode(<String, Object?>{
                'shape': 'scalar',
                'unit': 'umol/L',
                'value': 12,
                'entered': '12',
                'enteredUnit': 'umol/L',
                'lab': <String, Object?>{
                  'collected': collected,
                  'limit': null,
                  'printedRange': '9-18',
                  'printedFlag': null,
                  'reportStatus': 'final',
                  'fasting': null,
                  'labName': null,
                },
              }),
              scalarValue: const Value<double?>(12),
              scalarEntered: const Value<String?>('12'),
              atTime: Value<DateTime?>(DateTime.utc(2026, 2, 1, 12)),
              provenance: MetricReadingProvenance.agent.name,
              source: MetricReadingProvenance.agent.name,
              updatedAt: DateTime.utc(2026, 2, 1, 12),
            ),
          );
      return (metricId: metricId, readingId: readingId);
    });
  }

  Future<List<MetricReadingRow>> readings(WidgetTester tester) =>
      onFakeTime(tester, () => database.select(database.metricReadings).get());
}

/// Drift's timers fire only on frames here, on fake time, so a database
/// call from the test body has to pump while it waits.
Future<T> onFakeTime<T>(
  WidgetTester tester,
  Future<T> Function() work,
) async {
  late T result;
  Object? failure;
  var done = false;
  unawaited(
    work().then(
      (value) {
        result = value;
        done = true;
      },
      onError: (Object error) {
        failure = error;
        done = true;
      },
    ),
  );
  for (var frame = 0; frame < 200 && !done; frame += 1) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done, isTrue);
  if (failure != null) {
    throw failure!;
  }
  return result;
}

class LabLockStore implements ProtocolsLockStore {
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

class LabNoBiometrics implements BiometricAuthenticator {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> authenticate({required String reason}) async => false;
}
