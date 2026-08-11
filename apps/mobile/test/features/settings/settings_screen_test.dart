import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/api/perennia_api_client.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/activity/widgets/activity_feed_screen.dart';
import 'package:perennia/features/agent_keys/repositories/agent_api_key_repository.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/settings/services/client_crash_reporting.dart';
import 'package:perennia/features/sync/controllers/sync_status_controller.dart';
import 'package:perennia/features/sync/repositories/sync_device_id_repository.dart';
import 'package:perennia/features/sync/repositories/sync_repository.dart';
import 'package:perennia/features/sync/services/sync_coordinator.dart';
import 'package:perennia/features/settings/repositories/garmin_import_repository.dart';
import 'package:perennia/features/settings/repositories/imported_data_purge_repository.dart';
import 'package:perennia/features/settings/repositories/integration_consent_repository.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/settings/widgets/settings_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('settings screen', () {
    testWidgets('meets accessibility guidelines in both themes', (
      tester,
    ) async {
      for (final theme in <ThemeData>[
        AppTheme.light(),
        AppTheme.dark(),
      ]) {
        final semantics = tester.ensureSemantics();
        await _pumpSettings(tester, theme: theme);

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await tester.scrollUntilVisible(
          find.byKey(SettingsScreen.aboutTileKey),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('requires explicit confirmation before erasing local data', (
      tester,
    ) async {
      var eraseCount = 0;

      await _pumpSettings(
        tester,
        onEraseAllData: () async {
          eraseCount += 1;
        },
      );
      await _openHubScreen(tester, SettingsScreen.dataManagementTileKey);

      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.eraseAllDataButtonKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester
          .ensureVisible(find.byKey(SettingsScreen.eraseAllDataButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SettingsScreen.eraseAllDataButtonKey));
      await tester.pumpAndSettle();

      expect(eraseCount, 0);
      expect(
        find.byKey(SettingsScreen.confirmEraseAllDataButtonKey),
        findsOneWidget,
      );
      expect(find.textContaining('Backup restore is separate'), findsOneWidget);

      await tester.tap(
        find.byKey(SettingsScreen.confirmEraseAllDataButtonKey),
      );
      await tester.pumpAndSettle();

      expect(eraseCount, 1);
      expect(find.text('Local data erased'), findsOneWidget);
    });

    testWidgets('shows nutrition data credits and the honest offline boundary',
        (tester) async {
      await _pumpSettings(tester);
      await _openHubScreen(tester, SettingsScreen.aboutTileKey);

      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.exerciseCreditsKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.byKey(SettingsScreen.exerciseCreditsKey), findsOneWidget);
      expect(find.text('Exercise data'), findsOneWidget);
      expect(find.textContaining('wger English exercise fixtures'),
          findsOneWidget);
      expect(
          find.textContaining('Workout.cool exercise names'), findsOneWidget);
      expect(find.textContaining('distributed under CC-BY-SA 4.0'),
          findsOneWidget);
      expect(
          find.textContaining('no images, videos, thumbnails'), findsOneWidget);
      expect(find.text('Workout.cool source'), findsOneWidget);
      expect(find.text('CC-BY-SA 4.0'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.nutritionCreditsKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.byKey(SettingsScreen.nutritionCreditsKey), findsOneWidget);
      expect(find.text('Nutrition data'), findsOneWidget);
      expect(find.textContaining('Open Food Facts'), findsAtLeastNWidgets(1));
      expect(find.textContaining('ODbL'), findsOneWidget);
      expect(
        find.textContaining('USDA FoodData Central'),
        findsAtLeastNWidgets(1),
      );
      expect(find.textContaining('CC0'), findsAtLeastNWidgets(1));
      expect(
        find.textContaining('USDA logging works fully offline'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Open Food Facts branded/barcode lookups need '
            'network once'),
        findsOneWidget,
      );
      expect(
          find.textContaining('Quick Entry stays available'), findsOneWidget);
    });

    testWidgets(
        'nutrition data credits meet accessibility guidelines in both themes',
        (tester) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();
        await _pumpSettings(tester, theme: theme);
        await _openHubScreen(tester, SettingsScreen.aboutTileKey);

        await tester.scrollUntilVisible(
          find.byKey(SettingsScreen.nutritionCreditsKey),
          400,
          scrollable: find.byType(Scrollable).first,
        );

        expect(
          find.semantics.byLabel(RegExp(r'^Nutrition data credits')),
          findsOne,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('shows sync status row and non-modal failure banner', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        syncStatus: SyncStatusState(
          kind: SyncStatusKind.failed,
          lastSuccessfulSyncAt: DateTime.utc(2026, 6, 21, 8),
          firstFailureAt: DateTime.utc(2026, 6, 21, 9),
          lastFailureAt: DateTime.utc(2026, 6, 22, 10),
          lastFailureMessage: 'Network unavailable.',
          observedAt: DateTime.utc(2026, 6, 22, 12),
        ),
      );
      await _openHubScreen(tester, SettingsScreen.syncTileKey);

      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.syncStatusRowKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.byKey(SettingsScreen.syncStatusRowKey), findsOneWidget);
      expect(find.text('Sync failed'), findsOneWidget);
      expect(find.textContaining('Jun 21, 2026'), findsOneWidget);
      expect(find.byKey(SettingsScreen.syncFailureBannerKey), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('sync now pulls server changes for the signed-in device', (
      tester,
    ) async {
      final session = _session();
      final pulls = <({AuthSession session, String deviceId})>[];

      await _pumpSettings(
        tester,
        authState: AuthState(serverUrl: session.serverUrl, session: session),
        settingsSyncNow: ({
          required AuthSession session,
          required String deviceId,
        }) async {
          pulls.add((session: session, deviceId: deviceId));
          return const SyncCycleResult(
            appliedCount: 3,
            serverClock: '2026-06-25T10:00:00.000Z',
          );
        },
      );

      await _openHubScreen(tester, SettingsScreen.syncTileKey);
      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.syncNowButtonKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(SettingsScreen.syncNowButtonKey));
      await tester.pumpAndSettle();

      expect(pulls, hasLength(1));
      expect(pulls.single.session, session);
      expect(pulls.single.deviceId, 'device-a');
      expect(find.text('Sync complete: 3 changes applied.'), findsOneWidget);
    });

    testWidgets('auth-expired banner can explain Local-only account deletion', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        syncStatus: SyncStatusState(
          kind: SyncStatusKind.authExpired,
          lastFailureAt: DateTime.utc(2026, 6, 22, 10),
          lastFailureMessage:
              'Account deletion was requested. This device is now in Local-only Mode and its local data remains on the device.',
          observedAt: DateTime.utc(2026, 6, 22, 12),
        ),
      );

      await _openHubScreen(tester, SettingsScreen.syncTileKey);
      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.syncFailureBannerKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Sign in required'), findsOneWidget);
      expect(
        find.textContaining('Local-only Mode'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('shows Garmin stale status with manual FIT fallback', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      await _seedGarminConsentRows(database);

      await _pumpSettings(
        tester,
        database: database,
        syncStatus: SyncStatusState(
          kind: SyncStatusKind.synced,
          lastSuccessfulSyncAt: DateTime.utc(2026, 6, 22, 8),
          observedAt: DateTime.utc(2026, 6, 25, 12),
          integrationStatuses: <IntegrationStatusState>[
            IntegrationStatusState(
              source: 'garmin',
              condition: IntegrationStatusCondition.temporaryFailure,
              recoveryAction: IntegrationStatusRecoveryAction.retry,
              lastSuccessfulAt: DateTime.utc(2026, 6, 23, 8),
              firstFailureAt: DateTime.utc(2026, 6, 23, 9),
              lastFailureAt: DateTime.utc(2026, 6, 25, 10),
              failureKind: 'network',
              observedAt: DateTime.utc(2026, 6, 25, 12),
            ),
          ],
        ),
      );

      await _openHubScreen(tester, SettingsScreen.syncTileKey);
      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.integrationStatusRowKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        find.byKey(SettingsScreen.integrationStatusRowKey),
        findsOneWidget,
      );
      expect(find.text('Garmin'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(SettingsScreen.integrationStatusRowKey),
          matching: find.text('Feed failing'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Manual FIT import still works'),
        findsOneWidget,
      );
      expect(
        find.byKey(SettingsScreen.integrationFailureBannerKey),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _openGarminScreen(tester);
      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.garminImportAdapterTileKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Feed failing'), findsAtLeastNWidgets(1));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('shows Garmin re-auth and rate-limit recovery prompts', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        syncStatus: SyncStatusState(
          kind: SyncStatusKind.synced,
          observedAt: DateTime.utc(2026, 6, 25, 12),
          integrationStatuses: <IntegrationStatusState>[
            IntegrationStatusState(
              source: 'garmin',
              condition: IntegrationStatusCondition.reauthRequired,
              recoveryAction: IntegrationStatusRecoveryAction.reauth,
              lastFailureAt: DateTime.utc(2026, 6, 25, 10),
              failureKind: 'token_expired',
              observedAt: DateTime.utc(2026, 6, 25, 12),
            ),
          ],
        ),
      );

      await _openHubScreen(tester, SettingsScreen.syncTileKey);
      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.integrationFailureBannerKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Re-auth required'), findsOneWidget);
      expect(
        find.textContaining('new credentials in the self-host config'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Manual FIT import still works'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await _pumpSettings(
        tester,
        syncStatus: SyncStatusState(
          kind: SyncStatusKind.synced,
          observedAt: DateTime.utc(2026, 6, 25, 12),
          integrationStatuses: <IntegrationStatusState>[
            IntegrationStatusState(
              source: 'garmin',
              condition: IntegrationStatusCondition.rateLimited,
              recoveryAction: IntegrationStatusRecoveryAction.backoff,
              lastFailureAt: DateTime.utc(2026, 6, 25, 10),
              failureKind: 'rate_limit',
              retryAfterSeconds: 120,
              nextAttemptAt: DateTime.utc(2026, 6, 25, 10, 2),
              observedAt: DateTime.utc(2026, 6, 25, 12),
            ),
          ],
        ),
      );

      await _openHubScreen(tester, SettingsScreen.syncTileKey);
      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.integrationFailureBannerKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.integrationStatusRowKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Backoff active'), findsOneWidget);
      expect(find.textContaining('backing off after a rate limit'),
          findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('create sync token shows the one-time GarminDB token', (
      tester,
    ) async {
      final garminImportRepository = _FakeGarminImportRepository();
      final session = _session();
      final copiedSecrets = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments as Map<Object?, Object?>;
            copiedSecrets.add(arguments['text']! as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await _pumpSettings(
        tester,
        authState: AuthState(serverUrl: session.serverUrl, session: session),
        garminImportRepository: garminImportRepository,
      );

      await _openGarminScreen(tester);
      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.garminImportAdapterButtonKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Not connected'), findsOneWidget);
      expect(
        find.byKey(SettingsScreen.garminImportDisconnectButtonKey),
        findsNothing,
      );

      await tester.ensureVisible(
        find.byKey(SettingsScreen.garminImportAdapterButtonKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SettingsScreen.garminImportAdapterButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('GarminDB sync token'), findsOneWidget);
      expect(
          find.byKey(SettingsScreen.garminImportTokenTextKey), findsOneWidget);
      expect(find.text('prn_integ_test_secret'), findsOneWidget);
      expect(find.byKey(SettingsScreen.garminImportCopyTokenButtonKey),
          findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(garminImportRepository.createdSessions, <AuthSession>[session]);

      await tester
          .tap(find.byKey(SettingsScreen.garminImportCopyTokenButtonKey));
      await tester.pump();
      expect(copiedSecrets, <String>['prn_integ_test_secret']);
      expect(find.text('Sync token copied'), findsOneWidget);
    });

    testWidgets('Garmin FIT upload button is gated by session and consent', (
      tester,
    ) async {
      final session = _session();

      final noSessionDatabase = AppDatabase.inMemory();
      addTearDown(noSessionDatabase.close);
      await _seedGarminConsentRows(
        noSessionDatabase,
        enabled: <ImportDataClass, bool>{ImportDataClass.activities: true},
      );
      await _pumpSettings(tester, database: noSessionDatabase);
      await _expectGarminFitUploadEnabled(tester, false);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final noCredentialDatabase = AppDatabase.inMemory();
      addTearDown(noCredentialDatabase.close);
      await _pumpSettings(
        tester,
        database: noCredentialDatabase,
        authState: AuthState(serverUrl: session.serverUrl, session: session),
      );
      await _expectGarminFitUploadEnabled(tester, false);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final consentOffDatabase = AppDatabase.inMemory();
      addTearDown(consentOffDatabase.close);
      await _seedGarminConsentRows(consentOffDatabase);
      await _pumpSettings(
        tester,
        database: consentOffDatabase,
        authState: AuthState(serverUrl: session.serverUrl, session: session),
      );
      await _expectGarminFitUploadEnabled(tester, false);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final enabledDatabase = AppDatabase.inMemory();
      addTearDown(enabledDatabase.close);
      await _seedGarminConsentRows(
        enabledDatabase,
        enabled: <ImportDataClass, bool>{ImportDataClass.activities: true},
      );
      await _pumpSettings(
        tester,
        database: enabledDatabase,
        authState: AuthState(serverUrl: session.serverUrl, session: session),
      );
      await _expectGarminFitUploadEnabled(tester, true);
    });

    testWidgets('Garmin FIT upload sends the selected file to the repository', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final garminImportRepository = _FakeGarminImportRepository();
      final session = _session();
      final bytes =
          Uint8List.fromList(<int>[0x0e, 0x10, 0x2e, 0x46, 0x49, 0x54]);

      await _seedGarminConsentRows(
        database,
        enabled: <ImportDataClass, bool>{ImportDataClass.activities: true},
      );
      await _pumpSettings(
        tester,
        database: database,
        authState: AuthState(serverUrl: session.serverUrl, session: session),
        garminImportRepository: garminImportRepository,
        garminFitFilePicker: () async => <XFile>[
          XFile.fromData(bytes, path: 'strength.fit'),
        ],
      );
      await _openGarminScreen(tester);

      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.garminImportFitUploadButtonKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(SettingsScreen.garminImportFitUploadButtonKey),
      );
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(SettingsScreen.garminImportFitUploadButtonKey));
      await tester.pumpAndSettle();

      expect(garminImportRepository.uploads, hasLength(1));
      final upload = garminImportRepository.uploads.single;
      expect(upload.session, session);
      expect(upload.credentialId, _garminCredentialId);
      expect(upload.filename, 'strength.fit');
      expect(upload.bytes, bytes);
      expect(find.text('FIT import complete: 1 imported, 0 skipped.'),
          findsOneWidget);
    });

    testWidgets('renders pulled Garmin consent rows as switch state', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);

      await _pullGarminConsentRows(
        database,
        enabled: <ImportDataClass, bool>{
          ImportDataClass.heartRate: true,
          ImportDataClass.gps: false,
        },
      );
      await _pumpSettings(
        tester,
        database: database,
      );
      await _openGarminScreen(tester);

      final heartRateKey = SettingsScreen.garminImportConsentSwitchKey(
        ImportDataClass.heartRate,
      );
      final gpsKey = SettingsScreen.garminImportConsentSwitchKey(
        ImportDataClass.gps,
      );

      await tester.scrollUntilVisible(
        find.byKey(heartRateKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Create sync token'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(heartRateKey)).value,
          isTrue);
      expect(
        tester.widget<SwitchListTile>(find.byKey(gpsKey)).value,
        isFalse,
      );
    });

    testWidgets('toggling Garmin consent produces a consent sync push', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final requests = <http.Request>[];

      await _pullGarminConsentRows(database);
      await _pumpSettings(
        tester,
        database: database,
      );
      await _openGarminScreen(tester);

      final heartRateKey = SettingsScreen.garminImportConsentSwitchKey(
        ImportDataClass.heartRate,
      );
      await tester.scrollUntilVisible(
        find.byKey(heartRateKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      tester
          .widget<SwitchListTile>(find.byKey(heartRateKey))
          .onChanged
          ?.call(true);
      await tester.pump();

      final repository = SyncRepository(
        database: database,
        apiClientFactory: (baseUrl) => PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            requests.add(request);
            final body = jsonDecode(request.body) as Map<String, Object?>;
            final changes = body['changes']! as List<Object?>;
            final change = changes.single! as Map<String, Object?>;
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': 1,
                'accepted': <String>[change['id']! as String],
                'serverClock': '2026-06-25T10:00:01.000Z',
                'applied': <Object?>[
                  <String, Object?>{
                    'id': change['id'],
                    'updatedAt': change['updatedAt'],
                    'deviceId': 'device-a',
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final result = await repository.pushPendingIntegrationDataClassConsents(
        session: _session(),
        deviceId: 'device-a',
      );
      final requestBody =
          jsonDecode(requests.single.body) as Map<String, Object?>;
      final change = (requestBody['changes']! as List<Object?>).single!
          as Map<String, Object?>;
      final payload = change['payload']! as Map<String, Object?>;
      final row = await _garminConsentRow(
        database,
        ImportDataClass.heartRate,
      );
      final pendingRows = await (database.select(database.activityLog)
            ..where((row) => row.syncAcknowledgedAt.isNull()))
          .get();

      expect(result.pushedCount, 1);
      expect(result.acknowledgedActivityLogIds, hasLength(1));
      expect(
          requestBody['entity'], AppDatabase.integrationDataClassConsentsTable);
      expect(payload['credential_id'], _garminCredentialId);
      expect(payload['data_class'], ImportDataClass.heartRate.name);
      expect(payload['enabled'], isTrue);
      expect(row.enabled, isTrue);
      expect(row.syncPreviouslySynced, isTrue);
      expect(pendingRows, isEmpty);
    });

    testWidgets('disconnect clears connection and consent but keeps imports', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repositories = TrainingRepositories(database);
      await _seedGarminConsentRows(
        database,
        enabled: <ImportDataClass, bool>{
          for (final dataClass in ImportDataClass.values) dataClass: true,
        },
      );
      final metricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Resting Heart Rate',
          unit: 'beatsPerMinute',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.monitoring,
          enabled: true,
          pinned: false,
        ),
      );
      final importedReadingId =
          (await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: metricId,
            valueEntered: '61',
            atTime: DateTime.utc(2026, 6, 25, 7),
            source: 'garmin',
            externalId: 'rhr-2026-06-25',
          ),
        ],
      ))
              .single;

      await _pumpSettings(
        tester,
        database: database,
        trainingRepositories: repositories,
      );
      await _openGarminScreen(tester);

      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.garminImportDisconnectButtonKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(SettingsScreen.garminImportDisconnectButtonKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(SettingsScreen.garminImportDisconnectButtonKey),
      );
      await tester.pump();

      final activeConsents =
          await (database.select(database.integrationDataClassConsents)
                ..where((row) => row.deletedAt.isNull()))
              .get();
      final storedConsents =
          await database.select(database.integrationDataClassConsents).get();
      expect(activeConsents, isEmpty);
      expect(storedConsents, hasLength(ImportDataClass.values.length));
      expect(storedConsents.every((row) => !row.enabled), isTrue);
      expect(storedConsents.every((row) => row.deletedAt != null), isTrue);

      final readings = await repositories.metrics.listReadings(metricId);
      expect(readings.map((reading) => reading.id), <String>[
        importedReadingId,
      ]);
      final storedRows = await database.select(database.metricReadings).get();
      expect(storedRows, hasLength(1));
      expect(storedRows.single.id, importedReadingId);
      expect(storedRows.single.deletedAt, isNull);
      expect(find.byKey(SettingsScreen.garminImportPurgeGpsButtonKey),
          findsOneWidget);
      expect(find.byKey(SettingsScreen.garminImportPurgeAllButtonKey),
          findsOneWidget);
    });

    testWidgets('purge actions are explicit and separate from disconnect', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      await _seedGarminConsentRows(
        database,
        enabled: <ImportDataClass, bool>{
          for (final dataClass in ImportDataClass.values) dataClass: true,
        },
      );
      final purgeRepository = _FakeImportedDataPurgeRepository();

      await _pumpSettings(
        tester,
        database: database,
        authState:
            AuthState(serverUrl: _session().serverUrl, session: _session()),
        purgeRepository: purgeRepository,
      );
      await _openGarminScreen(tester);

      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.garminImportPurgeGpsButtonKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(SettingsScreen.garminImportPurgeGpsButtonKey),
      );
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(SettingsScreen.garminImportPurgeGpsButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('Purge GPS data?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(purgeRepository.calls, isEmpty);

      await tester.ensureVisible(
        find.byKey(SettingsScreen.garminImportPurgeGpsButtonKey),
      );
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(SettingsScreen.garminImportPurgeGpsButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(SettingsScreen.confirmGarminImportPurgeGpsButtonKey),
      );
      await tester.pumpAndSettle();
      expect(purgeRepository.calls.map((call) => call.scope),
          <ImportedDataPurgeScope>[ImportedDataPurgeScope.gpsOnly]);
      expect(find.text('Garmin GPS purged'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(SettingsScreen.garminImportDisconnectButtonKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(SettingsScreen.garminImportDisconnectButtonKey),
      );
      await tester.pump();
      expect(purgeRepository.calls, hasLength(1));

      await tester.ensureVisible(
        find.byKey(SettingsScreen.garminImportPurgeAllButtonKey),
      );
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(SettingsScreen.garminImportPurgeAllButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('Purge imported data?'), findsOneWidget);
      await tester.tap(
        find.byKey(SettingsScreen.confirmGarminImportPurgeAllButtonKey),
      );
      await tester.pumpAndSettle();
      expect(
          purgeRepository.calls.map((call) => call.scope),
          <ImportedDataPurgeScope>[
            ImportedDataPurgeScope.gpsOnly,
            ImportedDataPurgeScope.all,
          ]);
    });

    testWidgets('crash reporting toggle is default-off and persisted', (
      tester,
    ) async {
      final settingsRepository = InMemorySettingsRepository();

      await _pumpSettings(
        tester,
        settingsRepository: settingsRepository,
        crashReporter: _FakeClientCrashReporter(),
      );
      await _openHubScreen(tester, SettingsScreen.privacyTileKey);

      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.crashReportingSwitchKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(SettingsScreen.crashReportingSwitchKey),
            )
            .value,
        isFalse,
      );

      await tester.tap(find.byKey(SettingsScreen.crashReportingSwitchKey));
      await tester.pump();

      expect((await settingsRepository.load()).crashReportingEnabled, isTrue);
    });

    testWidgets('debug crash action is gated by crash reporting opt-in', (
      tester,
    ) async {
      final crashReporter = _FakeClientCrashReporter();

      await _pumpSettings(
        tester,
        settingsRepository: InMemorySettingsRepository(
          AppSettings.defaults.copyWith(crashReportingEnabled: true),
        ),
        crashReporter: crashReporter,
      );
      await _openHubScreen(tester, SettingsScreen.privacyTileKey);

      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.debugCrashReportButtonKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(SettingsScreen.debugCrashReportButtonKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SettingsScreen.debugCrashReportButtonKey));
      await tester.pump();

      expect(crashReporter.capturedThrowables, hasLength(1));

      await tester.ensureVisible(
        find.byKey(SettingsScreen.crashReportingSwitchKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SettingsScreen.crashReportingSwitchKey));
      await tester.pump();

      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(SettingsScreen.debugCrashReportButtonKey),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('shows auto-backup controls and folder re-grant prompt', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        settingsRepository: InMemorySettingsRepository(
          AppSettings.defaults.copyWith(
            autoBackupEnabled: true,
            autoBackupLastStatus: AutoBackupStatus.skippedMissingFolderGrant,
          ),
        ),
      );
      await _openHubScreen(tester, SettingsScreen.backupTileKey);

      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.autoBackupSwitchKey),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.byKey(SettingsScreen.autoBackupSwitchKey), findsOneWidget);
      expect(
          find.byKey(SettingsScreen.autoBackupFolderButtonKey), findsOneWidget);
      expect(find.byKey(SettingsScreen.autoBackupPassphraseFieldKey),
          findsOneWidget);
      expect(
          find.byKey(SettingsScreen.autoBackupGrantPromptKey), findsOneWidget);
      expect(find.text('Folder access needed'), findsOneWidget);
    });

    testWidgets(
        'auto-backup re-grant prompt meets accessibility guidelines in both themes',
        (tester) async {
      final settings = AppSettings.defaults.copyWith(
        autoBackupEnabled: true,
        autoBackupLastStatus: AutoBackupStatus.skippedMissingFolderGrant,
      );

      for (final theme in <ThemeData>[
        AppTheme.light(),
        AppTheme.dark(),
      ]) {
        final semantics = tester.ensureSemantics();
        await _pumpSettings(
          tester,
          theme: theme,
          settingsRepository: InMemorySettingsRepository(settings),
        );
        await _openHubScreen(tester, SettingsScreen.backupTileKey);

        await tester.scrollUntilVisible(
          find.byKey(SettingsScreen.autoBackupGrantPromptKey),
          400,
          scrollable: find.byType(Scrollable).first,
        );

        expect(
          find.semantics.byLabel(RegExp(r'^Auto-backup folder warning')),
          findsOne,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('failure banner meets accessibility guidelines in both themes',
        (tester) async {
      final bannerStatus = SyncStatusState(
        kind: SyncStatusKind.failed,
        lastSuccessfulSyncAt: DateTime.utc(2026, 6, 21, 8),
        firstFailureAt: DateTime.utc(2026, 6, 21, 9),
        lastFailureAt: DateTime.utc(2026, 6, 22, 10),
        lastFailureMessage: 'Network unavailable.',
        observedAt: DateTime.utc(2026, 6, 22, 12),
      );

      for (final theme in <ThemeData>[
        AppTheme.light(),
        AppTheme.dark(),
      ]) {
        final semantics = tester.ensureSemantics();
        await _pumpSettings(
          tester,
          theme: theme,
          syncStatus: bannerStatus,
        );
        await _openHubScreen(tester, SettingsScreen.syncTileKey);

        await tester.scrollUntilVisible(
          find.byKey(SettingsScreen.syncFailureBannerKey),
          400,
          scrollable: find.byType(Scrollable).first,
        );

        expect(
          find.semantics.byLabel(RegExp(r'^Sync warning')),
          findsOne,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets(
      'integration failure banner meets accessibility guidelines in both themes',
      (tester) async {
        final bannerStatus = SyncStatusState(
          kind: SyncStatusKind.synced,
          observedAt: DateTime.utc(2026, 6, 25, 12),
          integrationStatuses: <IntegrationStatusState>[
            IntegrationStatusState(
              source: 'garmin',
              condition: IntegrationStatusCondition.reauthRequired,
              recoveryAction: IntegrationStatusRecoveryAction.reauth,
              lastFailureAt: DateTime.utc(2026, 6, 25, 10),
              failureKind: 'token_expired',
              observedAt: DateTime.utc(2026, 6, 25, 12),
            ),
          ],
        );

        for (final theme in <ThemeData>[
          AppTheme.light(),
          AppTheme.dark(),
        ]) {
          final semantics = tester.ensureSemantics();
          await _pumpSettings(
            tester,
            theme: theme,
            syncStatus: bannerStatus,
          );
          await _openHubScreen(tester, SettingsScreen.syncTileKey);

          await tester.scrollUntilVisible(
            find.byKey(SettingsScreen.integrationFailureBannerKey),
            400,
            scrollable: find.byType(Scrollable).first,
          );

          expect(
            find.semantics.byLabel(RegExp(r'^Garmin integration warning')),
            findsOne,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'integration management controls meet accessibility guidelines in both themes',
      (tester) async {
        for (final theme in <ThemeData>[
          AppTheme.light(),
          AppTheme.dark(),
        ]) {
          final database = AppDatabase.inMemory();
          addTearDown(database.close);
          await _seedGarminConsentRows(
            database,
            enabled: <ImportDataClass, bool>{
              ImportDataClass.activities: true,
            },
          );
          final semantics = tester.ensureSemantics();
          await _pumpSettings(
            tester,
            theme: theme,
            database: database,
          );
          await _openGarminScreen(tester);

          await tester.scrollUntilVisible(
            find.byKey(
              SettingsScreen.garminImportConsentSwitchKey(
                ImportDataClass.bodyComposition,
              ),
            ),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -180),
          );
          await tester.pumpAndSettle();

          expect(
            find.semantics.byLabel(RegExp(r'^Body composition')),
            findsOne,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'enabled Garmin import controls meet accessibility guidelines in both themes',
      (tester) async {
        final session = _session();
        for (final theme in <ThemeData>[
          AppTheme.light(),
          AppTheme.dark(),
        ]) {
          final database = AppDatabase.inMemory();
          addTearDown(database.close);
          await _seedGarminConsentRows(
            database,
            enabled: <ImportDataClass, bool>{
              ImportDataClass.activities: true,
            },
          );
          final semantics = tester.ensureSemantics();
          await _pumpSettings(
            tester,
            theme: theme,
            database: database,
            authState: AuthState(
              serverUrl: session.serverUrl,
              session: session,
            ),
          );
          await _openGarminScreen(tester);

          await tester.scrollUntilVisible(
            find.byKey(SettingsScreen.garminImportFitUploadButtonKey),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(
            find.byKey(SettingsScreen.garminImportAdapterButtonKey),
          );
          await tester.pumpAndSettle();

          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(SettingsScreen.garminImportAdapterButtonKey),
                )
                .onPressed,
            isNotNull,
          );
          expect(
            tester
                .widget<OutlinedButton>(
                  find.byKey(SettingsScreen.garminImportFitUploadButtonKey),
                )
                .onPressed,
            isNotNull,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets('hub shows value subtitles and keeps danger off the hub', (
      tester,
    ) async {
      await _pumpSettings(tester);

      expect(
        find.text('System theme · Metric · Week starts Monday'),
        findsOneWidget,
      );
      expect(find.text('Increment 2.5 · PR tracking on'), findsOneWidget);
      expect(find.text('Auto-backup off'), findsOneWidget);
      expect(find.text('Crash reporting off'), findsOneWidget);
      // Destructive controls live on sub-screens, never on the hub.
      expect(find.byKey(SettingsScreen.eraseAllDataButtonKey), findsNothing);
      expect(
        find.byKey(SettingsScreen.garminImportPurgeAllButtonKey),
        findsNothing,
      );
      // The Supplements lock state is never readable from the hub
      // (hide-at-a-glance).
      expect(find.textContaining('Lock'), findsNothing);
    });

    testWidgets('hub rows navigate to their sub-screens', (tester) async {
      await _pumpSettings(tester);

      final destinations = <Key, Type>{
        SettingsScreen.generalTileKey: GeneralSettingsScreen,
        SettingsScreen.loggingTileKey: LoggingSettingsScreen,
        SettingsScreen.syncTileKey: SyncSettingsScreen,
        SettingsScreen.integrationsTileKey: IntegrationsScreen,
        SettingsScreen.agentApiTileKey: AgentApiScreen,
        SettingsScreen.backupTileKey: BackupSettingsScreen,
        SettingsScreen.dataManagementTileKey: DataManagementScreen,
        SettingsScreen.privacyTileKey: PrivacySettingsScreen,
        SettingsScreen.aboutTileKey: AboutScreen,
      };

      for (final destination in destinations.entries) {
        await _openHubScreen(tester, destination.key);
        expect(find.byType(destination.value), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Activity Log is a Data and privacy destination', (
      tester,
    ) async {
      await _pumpSettings(tester);

      await _openHubScreen(tester, SettingsScreen.activityLogTileKey);

      expect(find.byType(ActivityFeedScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Logging screen exposes the timer sounds toggle and persists it',
        (tester) async {
      // device-level `restTimerSoundsEnabled` (default on) on the
      // Logging sub-screen.
      final settingsRepository = InMemorySettingsRepository();
      await _pumpSettings(tester, settingsRepository: settingsRepository);
      await _openHubScreen(tester, SettingsScreen.loggingTileKey);

      final toggle = find.byKey(LoggingSettingsScreen.restTimerSoundsSwitchKey);
      await tester.scrollUntilVisible(
        toggle,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(toggle, findsOneWidget);
      expect(find.text('Timer sounds & vibration'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(toggle).value,
        isTrue,
        reason: 'Defaults on.',
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      final saved = await settingsRepository.load();
      expect(saved.restTimerSoundsEnabled, isFalse);
    });

    testWidgets(
        'preference and list sub-screens meet accessibility guidelines '
        'in both themes', (tester) async {
      for (final tileKey in <Key>[
        SettingsScreen.generalTileKey,
        SettingsScreen.loggingTileKey,
        SettingsScreen.privacyTileKey,
        SettingsScreen.integrationsTileKey,
      ]) {
        for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
          final semantics = tester.ensureSemantics();
          await _pumpSettings(tester, theme: theme);
          await _openHubScreen(tester, tileKey);

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets(
        'data management screen meets accessibility guidelines in both themes',
        (tester) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();
        await _pumpSettings(tester, theme: theme);
        await _openHubScreen(tester, SettingsScreen.dataManagementTileKey);

        expect(
          find.semantics.byLabel(RegExp(r'^Erase all data')),
          findsOne,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets(
      'the Supplements tile opens the discreet Compound list surface',
      (tester) async {
        // This is a NAVIGATION smoke test, not a Protocols data test (that's
        // protocols_repository_test.dart + compound_list_screen_test.dart):
        // stub the Compound-list providers so no real Drift `.watch()` stream
        // is ever created here, keeping the assertion to "does the tile land
        // on CompoundListScreen".
        await _pumpSettings(
          tester,
          extraOverrides: [
            compoundListProvider.overrideWith(
              (ref) => Stream<List<CompoundRecord>>.value(
                const <CompoundRecord>[],
              ),
            ),
            recentCompoundIdsProvider.overrideWith(
              (ref) => Stream<List<String>>.value(
                const <String>[],
              ),
            ),
            protocolDayControllerProvider.overrideWith(
              _StubProtocolDayController.new,
            ),
          ],
        );

        await tester.scrollUntilVisible(
          find.byKey(SettingsScreen.supplementsTileKey),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        // Neutral capsule iconography, never a syringe.
        expect(
          find.descendant(
            of: find.byKey(SettingsScreen.supplementsTileKey),
            matching: find.byIcon(Icons.medication_outlined),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(SettingsScreen.supplementsTileKey),
            matching: find.byIcon(Icons.vaccines),
          ),
          findsNothing,
        );

        await tester.tap(find.byKey(SettingsScreen.supplementsTileKey));
        await tester.pumpAndSettle();

        expect(find.byType(CompoundListScreen), findsOneWidget);
      },
    );
  });
}

const _garminCredentialId = 'credential-garmin-1';

Future<void> _openHubScreen(WidgetTester tester, Key tileKey) async {
  await tester.scrollUntilVisible(
    find.byKey(tileKey),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byKey(tileKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(tileKey));
  await tester.pumpAndSettle();
}

Future<void> _openGarminScreen(WidgetTester tester) async {
  await _openHubScreen(tester, SettingsScreen.integrationsTileKey);
  await tester.tap(find.byKey(IntegrationsScreen.garminTileKey));
  await tester.pumpAndSettle();
}

Future<void> _expectGarminFitUploadEnabled(
  WidgetTester tester,
  bool enabled,
) async {
  await _openGarminScreen(tester);
  await tester.scrollUntilVisible(
    find.byKey(SettingsScreen.garminImportFitUploadButtonKey),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  final button = tester.widget<OutlinedButton>(
    find.byKey(SettingsScreen.garminImportFitUploadButtonKey),
  );
  expect(button.onPressed, enabled ? isNotNull : isNull);
}

Future<void> _pullGarminConsentRows(
  AppDatabase database, {
  Map<ImportDataClass, bool> enabled = const <ImportDataClass, bool>{},
}) {
  final updatedAt = DateTime.utc(2026, 6, 25, 10);
  final repository = SyncRepository(
    database: database,
    apiClientFactory: (baseUrl) => PerenniaApiClient(
      baseUrl: baseUrl,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'protocolVersion': 1,
            'nextCursor': 'cursor-consent-1',
            'serverClock': '2026-06-25T10:00:00.000Z',
            'changes': <Object?>[
              for (final dataClass in ImportDataClass.values)
                _pulledGarminConsentChange(
                  dataClass,
                  enabled: enabled[dataClass] ?? false,
                  updatedAt: updatedAt,
                ),
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    ),
  );

  return repository.pullLoggedSetChanges(
    session: _session(),
    deviceId: 'device-a',
  );
}

Future<void> _seedGarminConsentRows(
  AppDatabase database, {
  Map<ImportDataClass, bool> enabled = const <ImportDataClass, bool>{},
}) async {
  final updatedAt = DateTime.utc(2026, 6, 25, 10);
  for (final dataClass in ImportDataClass.values) {
    await database.into(database.integrationDataClassConsents).insert(
          IntegrationDataClassConsentsCompanion.insert(
            id: _garminConsentId(dataClass),
            credentialId: _garminCredentialId,
            dataClass: dataClass.name,
            enabled: Value<bool>(enabled[dataClass] ?? false),
            syncDeviceId: const Value<String?>('edge:garmin-sidecar'),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: updatedAt,
          ),
        );
  }
}

Map<String, Object?> _pulledGarminConsentChange(
  ImportDataClass dataClass, {
  required bool enabled,
  required DateTime updatedAt,
}) {
  final id = _garminConsentId(dataClass);
  return <String, Object?>{
    'entity': AppDatabase.integrationDataClassConsentsTable,
    'id': id,
    'deviceId': 'edge:garmin-sidecar',
    'payload': <String, Object?>{
      'id': id,
      'credential_id': _garminCredentialId,
      'data_class': dataClass.name,
      'enabled': enabled,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': null,
    },
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': null,
  };
}

Future<IntegrationDataClassConsentRow> _garminConsentRow(
  AppDatabase database,
  ImportDataClass dataClass,
) {
  return (database.select(database.integrationDataClassConsents)
        ..where((row) => row.id.equals(_garminConsentId(dataClass))))
      .getSingle();
}

String _garminConsentId(ImportDataClass dataClass) {
  return 'garmin-consent-${dataClass.name}';
}

AuthSession _session() {
  return AuthSession(
    provider: AuthSessionProvider.email,
    serverUrl: Uri.parse('https://sync.example/'),
    token: 'session-token',
    userEmail: 'user@example.com',
    userId: 'user-1',
    userName: 'Sync User',
  );
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  ThemeData? theme,
  Future<void> Function()? onEraseAllData,
  SyncStatusState? syncStatus,
  AppDatabase? database,
  SettingsRepository? settingsRepository,
  TrainingRepositories? trainingRepositories,
  ClientCrashReporter? crashReporter,
  AuthState? authState,
  GarminImportRepository? garminImportRepository,
  GarminFitFilePicker? garminFitFilePicker,
  ImportedDataPurgeRepository? purgeRepository,
  ProtocolsLockStore? protocolsLockStore,
  List<Override> extraOverrides = const <Override>[],
  SettingsSyncNow? settingsSyncNow,
  String syncDeviceId = 'device-a',
}) async {
  final resolvedSyncStatus =
      syncStatus ?? SyncStatusState.initial(DateTime.utc(2026, 6, 22, 12));
  final resolvedDatabase =
      database ?? trainingRepositories?.database ?? AppDatabase.inMemory();
  if (database == null && trainingRepositories == null) {
    addTearDown(resolvedDatabase.close);
  }
  final resolvedTrainingRepositories =
      trainingRepositories ?? TrainingRepositories(resolvedDatabase);
  final resolvedConsentRepository =
      IntegrationConsentRepository(resolvedDatabase);
  final resolvedGarminConsentState =
      await resolvedConsentRepository.loadGarminImportConsentState();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => resolvedDatabase),
        integrationConsentRepositoryProvider.overrideWith(
          (ref) => resolvedConsentRepository,
        ),
        garminImportConsentStateProvider.overrideWith(
          (ref) => Stream<GarminImportConsentState>.value(
            resolvedGarminConsentState,
          ),
        ),
        settingsRepositoryProvider.overrideWith(
          (ref) => settingsRepository ?? InMemorySettingsRepository(),
        ),
        syncStatusControllerProvider.overrideWith(
          () => _StubSyncStatusController(resolvedSyncStatus),
        ),
        syncDeviceIdProvider.overrideWith((ref) => syncDeviceId),
        settingsSyncNowProvider.overrideWith(
          (ref) =>
              settingsSyncNow ??
              ({
                required AuthSession session,
                required String deviceId,
              }) async {
                throw StateError('Unexpected sync now.');
              },
        ),
        authRepositoryProvider.overrideWith(
          (ref) => InMemoryAuthRepository(authState ?? AuthState.defaults),
        ),
        garminImportRepositoryProvider.overrideWith(
          (ref) => garminImportRepository ?? _FakeGarminImportRepository(),
        ),
        garminFitFilePickerProvider.overrideWith(
          (ref) => garminFitFilePicker ?? () async => <XFile>[],
        ),
        importedDataPurgeRepositoryProvider.overrideWith(
          (ref) => purgeRepository ?? _FakeImportedDataPurgeRepository(),
        ),
        agentApiKeyRepositoryProvider.overrideWith(
          (ref) => InMemoryAgentApiKeyRepository(),
        ),
        trainingRepositoriesProvider.overrideWith(
          (ref) => resolvedTrainingRepositories,
        ),
        clientCrashReporterProvider.overrideWith(
          (ref) => crashReporter ?? _FakeClientCrashReporter(),
        ),
        // Keeps the new "Lock Supplements" toggle off the real
        // secure-storage plugin channel, which no widget test has a device
        // for, unless a test explicitly supplies its own fake to exercise
        // the lock itself.
        protocolsLockStoreProvider.overrideWith(
          (ref) => protocolsLockStore ?? _InMemoryProtocolsLockStore(),
        ),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(onEraseAllData: onEraseAllData),
      ),
    ),
  );
  await tester.pump();
}

class _StubSyncStatusController extends SyncStatusController {
  _StubSyncStatusController(this.status);

  final SyncStatusState status;

  @override
  Stream<SyncStatusState> build() => Stream<SyncStatusState>.value(status);
}

/// A stub for the Supplements-tile navigation smoke test: emits an empty
/// derived Protocol Day without ever touching the real repository/Drift
/// streams (mirrors protocols_day_view_test.dart's fake-controller pattern).
class _StubProtocolDayController extends ProtocolDayController {
  @override
  Stream<ProtocolDayState> build() {
    return Stream<ProtocolDayState>.value(
      ProtocolDayState(
        day: ProtocolDayRecord(
          localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
          doses: <DoseRecord>[],
        ),
      ),
    );
  }

  @override
  Future<void> ensureOtcLibrarySeeded() async {}
}

class _FakeClientCrashReporter implements ClientCrashReporter {
  final enabledValues = <bool>[];
  final capturedThrowables = <Object>[];

  @override
  Future<void> setEnabled(bool enabled) async {
    enabledValues.add(enabled);
  }

  @override
  Future<void> captureException(
    Object throwable,
    StackTrace stackTrace, {
    Hint? hint,
  }) async {
    capturedThrowables.add(throwable);
  }

  @override
  Future<void> addBreadcrumb(Breadcrumb breadcrumb, {Hint? hint}) async {}
}

class _FakeGarminImportRepository extends GarminImportRepository {
  _FakeGarminImportRepository()
      : super(
          apiClientFactory: (_) => throw StateError('Unexpected HTTP client'),
        );

  final createdSessions = <AuthSession>[];
  final uploads = <_GarminFitUpload>[];

  @override
  Future<IntegrationCredentialIssueResponse> createGarminDbCredential({
    required AuthSession session,
  }) async {
    createdSessions.add(session);
    return const IntegrationCredentialIssueResponse(
      credential: IntegrationCredentialMetadata(
        id: _garminCredentialId,
        source: 'garmin-garmindb',
        name: 'GarminDB sync',
        createdAt: '2026-06-30T10:00:00.000Z',
        revoked: false,
        scope: <String, Object?>{},
      ),
      secret: 'prn_integ_test_secret',
    );
  }

  @override
  Future<CanonicalImportResponse> uploadGarminFitFile({
    required AuthSession session,
    required String credentialId,
    required List<int> bytes,
    required String filename,
    String? timezone,
  }) async {
    uploads.add(
      _GarminFitUpload(
        session: session,
        credentialId: credentialId,
        bytes: bytes,
        filename: filename,
        timezone: timezone,
      ),
    );
    return CanonicalImportResponse(
      accepted: true,
      duplicate: uploads.length > 1,
      idempotencyKey: 'fit-${uploads.length}',
      batchId: 'batch-${uploads.length}',
      serverClock: '2026-06-30T10:00:00.000Z',
      activities: const <Map<String, Object?>>[],
      metricReadings: const <Map<String, Object?>>[],
      seriesAccepted: 0,
      reviewFlags: const <Map<String, Object?>>[],
      materializedWorkouts: const <Map<String, Object?>>[],
      activityLinks: const <Map<String, Object?>>[],
      activityLinkSuggestions: const <Map<String, Object?>>[],
    );
  }
}

class _GarminFitUpload {
  const _GarminFitUpload({
    required this.session,
    required this.credentialId,
    required this.bytes,
    required this.filename,
    required this.timezone,
  });

  final AuthSession session;
  final String credentialId;
  final List<int> bytes;
  final String filename;
  final String? timezone;
}

class _FakeImportedDataPurgeRepository implements ImportedDataPurgeRepository {
  final calls = <_ImportedDataPurgeCall>[];

  @override
  Future<ImportedDataPurgeResponse> purgeGarminImportedData({
    required AuthSession session,
    required ImportedDataPurgeScope scope,
  }) async {
    calls.add(_ImportedDataPurgeCall(session: session, scope: scope));
    return ImportedDataPurgeResponse(
      accepted: true,
      duplicate: false,
      batchId: 'purge-${calls.length}',
      serverClock: '2026-06-26T01:00:00.000Z',
      source: 'garmin',
      scope: scope.wireName,
      tombstonedCounts: const ImportedDataPurgeCounts(
        externalActivities: 0,
        metricReadings: 0,
        monitoringSeries: 0,
        materializedSets: 0,
        activityLinks: 0,
      ),
    );
  }
}

class _ImportedDataPurgeCall {
  const _ImportedDataPurgeCall({
    required this.session,
    required this.scope,
  });

  final AuthSession session;
  final ImportedDataPurgeScope scope;
}

/// An in-memory `ProtocolsLockStore` fake — keeps `ProtocolsLockSettingsTile`
/// off the real secure-storage plugin channel in widget tests that don't
/// specifically exercise the lock (mirrors `_NoLockStore` in
/// compound_list_screen_test.dart).
class _InMemoryProtocolsLockStore implements ProtocolsLockStore {
  bool _enabled = false;
  String? _pinHash;

  @override
  Future<bool> isEnabled() async => _enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
  }

  @override
  Future<String?> readPinHash() async => _pinHash;

  @override
  Future<void> writePinHash(String hash) async {
    _pinHash = hash;
  }

  @override
  Future<void> clearPin() async {
    _pinHash = null;
  }
}
