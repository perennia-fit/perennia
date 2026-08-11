import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/agent_keys/repositories/agent_api_key_repository.dart';
import 'package:perennia/features/agent_keys/widgets/agent_api_key_management.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/settings/repositories/integration_consent_repository.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/settings/widgets/settings_screen.dart';
import 'package:perennia/features/sync/controllers/sync_status_controller.dart';
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

  group('agent API key management', () {
    testWidgets(
      'meets accessibility guidelines in both themes for list and secret states',
      (tester) async {
        for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
          final semantics = tester.ensureSemantics();
          final repository = InMemoryAgentApiKeyRepository(
            initialKeys: [
              AgentApiKeyRecord(
                id: 'coach-key',
                name: 'Remote coach',
                prefix: 'prn_agent_',
                start: 'coach',
                createdAt: DateTime.utc(2026, 6, 22, 8),
                lastUsedAt: DateTime.utc(2026, 6, 23, 9, 30),
              ),
            ],
          );

          await _pumpSettings(
            tester,
            repository: repository,
            theme: theme,
          );
          await _scrollToAgentKeys(tester);

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          await tester.enterText(
            find.byKey(AgentApiKeyManagement.nameFieldKey),
            'Garage assistant',
          );
          await tester.pump();
          await tester.tap(find.byKey(AgentApiKeyManagement.createButtonKey));
          await tester.pumpAndSettle();

          expect(
            find.byKey(AgentApiKeyManagement.createdSecretPanelKey),
            findsOneWidget,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets('creates a key and reveals the secret exactly once', (
      tester,
    ) async {
      final repository = InMemoryAgentApiKeyRepository();
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

      await _pumpSettings(tester, repository: repository);
      await _scrollToAgentKeys(tester);

      await tester.enterText(
        find.byKey(AgentApiKeyManagement.nameFieldKey),
        'Garage assistant',
      );
      await tester.pump();
      await tester.tap(find.byKey(AgentApiKeyManagement.createButtonKey));
      await tester.pumpAndSettle();

      expect(repository.createdNames, <String>['Garage assistant']);
      expect(find.byKey(AgentApiKeyManagement.createdSecretPanelKey),
          findsOneWidget);
      expect(find.text('prn_agent_secret_1'), findsOneWidget);
      expect(find.textContaining('will not be shown again'), findsOneWidget);
      expect(find.byKey(AgentApiKeyManagement.keyTileKey('agent-key-1')),
          findsOneWidget);

      await tester.tap(find.byKey(AgentApiKeyManagement.copySecretButtonKey));
      await tester.pump();
      expect(copiedSecrets, <String>['prn_agent_secret_1']);

      await tester
          .tap(find.byKey(AgentApiKeyManagement.dismissSecretButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AgentApiKeyManagement.createdSecretPanelKey),
          findsNothing);
      expect(find.text('prn_agent_secret_1'), findsNothing);
      expect(find.text('Garage assistant'), findsOneWidget);

      await _pumpSettings(tester, repository: repository);
      await _scrollToAgentKeys(tester);

      expect(find.text('Garage assistant'), findsOneWidget);
      expect(find.text('prn_agent_secret_1'), findsNothing);
    });

    testWidgets('lists existing keys with created and last-used metadata', (
      tester,
    ) async {
      final repository = InMemoryAgentApiKeyRepository(
        initialKeys: [
          AgentApiKeyRecord(
            id: 'coach-key',
            name: 'Remote coach',
            prefix: 'prn_agent_',
            start: 'coach',
            createdAt: DateTime.utc(2026, 6, 22, 8),
            lastUsedAt: DateTime.utc(2026, 6, 23, 9, 30),
          ),
        ],
      );

      await _pumpSettings(tester, repository: repository);
      await _scrollToAgentKeys(tester);

      expect(find.byKey(AgentApiKeyManagement.keyTileKey('coach-key')),
          findsOneWidget);
      expect(find.text('Remote coach'), findsOneWidget);
      expect(find.textContaining('Created'), findsOneWidget);
      expect(find.textContaining('Last used'), findsOneWidget);
      expect(find.textContaining('Starts coach'), findsOneWidget);
      expect(find.textContaining('prn_agent_secret'), findsNothing);
    });

    testWidgets('revokes a key and removes it from the list', (tester) async {
      final repository = InMemoryAgentApiKeyRepository(
        initialKeys: [
          AgentApiKeyRecord(
            id: 'old-agent',
            name: 'Old agent',
            createdAt: DateTime.utc(2026, 6, 22, 8),
            lastUsedAt: null,
          ),
        ],
      );

      await _pumpSettings(tester, repository: repository);
      await _scrollToAgentKeys(tester);

      expect(find.text('Old agent'), findsOneWidget);

      await tester.tap(
        find.byKey(AgentApiKeyManagement.revokeButtonKey('old-agent')),
      );
      await tester.pumpAndSettle();

      expect(repository.revokedKeyIds, <String>['old-agent']);
      expect(find.text('Old agent'), findsNothing);
      expect(find.byKey(AgentApiKeyManagement.emptyListKey), findsOneWidget);
    });

    testWidgets('signed-out users get the sign-in affordance', (tester) async {
      await _pumpSettings(
        tester,
        repository: InMemoryAgentApiKeyRepository(),
        authState: AuthState.defaults,
      );
      await _scrollToSignIn(tester);

      expect(find.text('Sign in to manage agent keys'), findsOneWidget);
      expect(find.byKey(AgentApiKeyManagement.signInButtonKey), findsOneWidget);
    });
  });
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required AgentApiKeyRepository repository,
  ThemeData? theme,
  AuthState? authState,
}) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => database),
        garminImportConsentStateProvider.overrideWith(
          (ref) => Stream<GarminImportConsentState>.value(
            GarminImportConsentState.empty,
          ),
        ),
        settingsRepositoryProvider.overrideWith(
          (ref) => InMemorySettingsRepository(),
        ),
        syncStatusControllerProvider.overrideWith(
          () => _StubSyncStatusController(
            SyncStatusState.initial(DateTime.utc(2026, 6, 24, 8)),
          ),
        ),
        authRepositoryProvider.overrideWith(
          (ref) => InMemoryAuthRepository(authState ?? _signedInAuthState),
        ),
        agentApiKeyRepositoryProvider.overrideWith((ref) => repository),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The hub redesign moved key management to Settings → Agent API; these
  // tests still enter through the hub so the navigation path stays covered.
  // A mid-test re-pump keeps the Navigator stack, so skip the hop when the
  // Agent API screen is already on top.
  if (find.byType(AgentApiScreen).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.agentApiTileKey),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(SettingsScreen.agentApiTileKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.agentApiTileKey));
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollToAgentKeys(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(AgentApiKeyManagement.nameFieldKey),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToSignIn(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(AgentApiKeyManagement.signInButtonKey),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

final _signedInAuthState = AuthState(
  serverUrl: Uri.parse('https://cloud.example/'),
  session: AuthSession(
    provider: AuthSessionProvider.email,
    serverUrl: Uri.parse('https://cloud.example/'),
    token: 'session-token',
    userEmail: 'lifter@example.com',
    userId: 'user-1',
    userName: 'Lifter',
  ),
);

class _StubSyncStatusController extends SyncStatusController {
  _StubSyncStatusController(this.status);

  final SyncStatusState status;

  @override
  Stream<SyncStatusState> build() => Stream<SyncStatusState>.value(status);
}
