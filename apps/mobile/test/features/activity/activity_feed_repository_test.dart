import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/app.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/activity/repositories/activity_feed_repository.dart';
import 'package:perennia/features/activity/widgets/activity_feed_screen.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/home/controllers/home_controller.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/home/widgets/home_screen.dart';
import 'package:perennia/features/settings/repositories/integration_consent_repository.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/settings/widgets/settings_screen.dart';
import 'package:perennia/features/sync/controllers/sync_status_controller.dart';
import 'package:perennia/features/up_next/repositories/up_next_feature_repository.dart';
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

  group('ActivityFeedRepository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late ActivityFeedRepository feedRepository;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      feedRepository = ActivityFeedRepository(repositories);
    });

    tearDown(() async {
      await database.close();
    });

    test('groups activity rows by batch newest-first inside retention',
        () async {
      final now = DateTime.utc(2026, 6, 16, 12);
      await _insertActivityRow(
        database,
        id: 'older-but-visible',
        actor: 'app',
        batchId: 'visible-batch',
        entityTable: AppDatabase.workoutSessionsTable,
        occurredAt: now.subtract(const Duration(days: 179)),
      );
      await _insertActivityRow(
        database,
        id: 'newer-one',
        actor: 'tester',
        batchId: 'new-batch',
        entityTable: AppDatabase.loggedSetsTable,
        occurredAt: now.subtract(const Duration(minutes: 3)),
      );
      await _insertActivityRow(
        database,
        id: 'newer-two',
        actor: 'tester',
        batchId: 'new-batch',
        entityTable: AppDatabase.workoutSessionsTable,
        occurredAt: now.subtract(const Duration(minutes: 2)),
      );
      await _insertActivityRow(
        database,
        id: 'expired',
        actor: 'app',
        batchId: 'expired-batch',
        entityTable: AppDatabase.loggedSetsTable,
        occurredAt: now.subtract(const Duration(days: 181)),
      );

      final batches = await feedRepository.listRecentBatches(now: now);

      expect(
        batches.map((batch) => batch.batchId),
        <String>['new-batch', 'visible-batch'],
      );
      expect(batches.first.actor, 'tester');
      expect(batches.first.entries, hasLength(2));
      expect(batches.first.affectedEntitySummary, contains('workout'));
      expect(batches.first.affectedEntitySummary, contains('set'));
    });

    test('logged set changes persist before and after images for feed rows',
        () async {
      final result = await _logWorkoutWithSet(repositories, actor: 'tester');

      await repositories.sets.updateValues(
        result.loggedSetId,
        values: _weightRepsSet(load: '105', reps: '5'),
        actor: 'tester',
      );

      final rawEntries = await repositories.activityLog.listEntries();
      final updateEntry = rawEntries.lastWhere(
        (entry) =>
            entry.entityTable == AppDatabase.loggedSetsTable &&
            entry.beforeImage != null &&
            entry.afterImage != null,
      );
      expect(updateEntry.beforeImage!['load_entered'], '100');
      expect(updateEntry.afterImage!['load_entered'], '105');

      final batches = await feedRepository.listRecentBatches();
      final updateBatch = batches.firstWhere(
        (batch) => batch.entries.any((entry) => entry.id == updateEntry.id),
      );
      expect(updateBatch.actor, 'tester');
      expect(updateBatch.affectedEntitySummary, contains('set'));
    });

    test('feed contents survive reopening the sqlite file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'perennia-activity-feed-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final file = File('${directory.path}${Platform.pathSeparator}app.sqlite');

      final firstDatabase = AppDatabase.openFile(file);
      final firstRepositories = TrainingRepositories(firstDatabase);
      final result = await _logWorkoutWithSet(
        firstRepositories,
        actor: 'tester',
      );
      await firstDatabase.close();

      final reopenedDatabase = AppDatabase.openFile(file);
      final reopenedRepositories = TrainingRepositories(reopenedDatabase);
      addTearDown(reopenedDatabase.close);

      final batches = await ActivityFeedRepository(reopenedRepositories)
          .listRecentBatches();

      expect(
        batches.any((batch) => batch.batchId == result.batchId),
        isTrue,
      );
      expect(
        batches
            .expand((batch) => batch.entries)
            .any((entry) => entry.entityId == result.loggedSetId),
        isTrue,
      );
    });

    test('undo restores a logged-set update and appends its own batch',
        () async {
      final result = await _logWorkoutWithSet(repositories, actor: 'tester');
      await repositories.sets.updateValues(
        result.loggedSetId,
        values: _weightRepsSet(load: '105', reps: '5'),
        actor: 'tester',
      );
      final updateEntry = (await repositories.activityLog.listEntries())
          .lastWhere((entry) => entry.entityId == result.loggedSetId);

      final undo = await feedRepository.undoBatch(
        updateEntry.batchId,
        actor: 'tester',
      );

      expect(undo.conflicts, isEmpty);
      expect(undo.undoBatchId, isNot(updateEntry.batchId));
      expect(undo.appliedEntries.map((entry) => entry.entityId), <String>[
        result.loggedSetId,
      ]);

      final set = await repositories.sets.getById(result.loggedSetId);
      expect(set, isNotNull);
      expect(set!.values.load!.entered, '100');

      final undoEntries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == undo.undoBatchId)
          .toList(growable: false);
      expect(undoEntries, hasLength(1));
      expect(undoEntries.single.beforeImage!['load_entered'], '105');
      expect(undoEntries.single.afterImage!['load_entered'], '100');
    });

    test('undoing a created logged-set batch soft-deletes instead of purging',
        () async {
      final result = await _logWorkoutWithSet(repositories, actor: 'tester');

      final undo = await feedRepository.undoBatch(
        result.batchId,
        actor: 'tester',
      );

      expect(undo.conflicts, isEmpty);
      expect(undo.appliedEntries, hasLength(2));
      expect(await repositories.sets.listAllActive(), isEmpty);
      expect(await repositories.workoutSessions.listActive(), isEmpty);

      final setRow = await (database.select(database.loggedSets)
            ..where((row) => row.id.equals(result.loggedSetId)))
          .getSingleOrNull();
      final sessionRow = await (database.select(database.workoutSessions)
            ..where((row) => row.id.equals(result.workoutSessionId)))
          .getSingleOrNull();
      expect(setRow, isNotNull);
      expect(sessionRow, isNotNull);
      expect(setRow!.deletedAt, isNotNull);
      expect(sessionRow!.deletedAt, isNotNull);

      final undoEntries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == undo.undoBatchId)
          .toList(growable: false);
      expect(undoEntries, hasLength(2));
      expect(undoEntries.every((entry) => entry.afterImage != null), isTrue);
    });

    test('undo reports per-row conflicts when rows changed since the batch',
        () async {
      final result = await _logWorkoutWithSet(repositories, actor: 'tester');
      await repositories.sets.updateValues(
        result.loggedSetId,
        values: _weightRepsSet(load: '105', reps: '5'),
        actor: 'tester',
      );
      final updateEntry = (await repositories.activityLog.listEntries())
          .lastWhere((entry) => entry.entityId == result.loggedSetId);
      await repositories.sets.updateValues(
        result.loggedSetId,
        values: _weightRepsSet(load: '110', reps: '5'),
        actor: 'tester',
      );

      final undo = await feedRepository.undoBatch(
        updateEntry.batchId,
        actor: 'tester',
      );

      expect(undo.appliedEntries, isEmpty);
      expect(undo.undoBatchId, isNull);
      expect(undo.conflicts, hasLength(1));
      expect(undo.conflicts.single.entityTable, AppDatabase.loggedSetsTable);
      expect(undo.conflicts.single.entityId, result.loggedSetId);
      expect(undo.conflicts.single.reason, ActivityLogUndoConflictReason.stale);

      final set = await repositories.sets.getById(result.loggedSetId);
      expect(set!.values.load!.entered, '110');
    });
  });

  group('ActivityFeedRepository agent nutrition batch', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late ActivityFeedRepository feedRepository;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      feedRepository = ActivityFeedRepository(repositories);
    });

    tearDown(() async {
      await database.close();
    });

    test('an agent Meal batch surfaces as exactly one Recent Activity entry',
        () async {
      final batch = await _applyAgentMealBatch(repositories);

      final batches = await feedRepository.listRecentBatches(now: _fixedNow);

      expect(batches, hasLength(1));
      final feedBatch = batches.single;
      expect(feedBatch.batchId, batch.batchId);
      expect(feedBatch.actor, 'agent:agent-key-1');
      // One Meal + two Food Entry rows => three activity rows, one entry.
      expect(feedBatch.entries, hasLength(3));
      // Reads as one logged Meal occasion, not a scatter of Food Entry events.
      expect(feedBatch.affectedEntitySummary, 'Logged Meal');
    });

    test(
        'one-tap undo reverts the whole Meal batch to tombstones together '
        'without touching the catalogue', () async {
      final batch = await _applyAgentMealBatch(repositories);

      final undo = await feedRepository.undoBatch(batch.batchId);

      expect(undo.conflicts, isEmpty);
      expect(undo.undoBatchId, isNot(batch.batchId));
      // Meal + both Food Entry rows reverted as one unit.
      expect(undo.appliedEntries, hasLength(3));

      // The Meal and every Food Entry are tombstones (hard-delete -> tombstone),
      // rows survive (recoverable, no purge, no cascade away).
      final mealRow = await (database.select(database.meals)
            ..where((row) => row.id.equals(batch.mealId)))
          .getSingleOrNull();
      expect(mealRow, isNotNull);
      expect(mealRow!.deletedAt, isNotNull);
      for (final foodEntryId in batch.foodEntryIds) {
        final entryRow = await (database.select(database.foodEntries)
              ..where((row) => row.id.equals(foodEntryId)))
            .getSingleOrNull();
        expect(entryRow, isNotNull);
        expect(entryRow!.deletedAt, isNotNull);
      }
      expect(
          await repositories.nutrition.listActiveEntriesForMeal(batch.mealId),
          isEmpty);
      // The Meal is gone from the derived Nutrition Day (active view).
      expect(await _activeMealCount(repositories, batch), 0);

      // Catalogue (User Food) is untouched — archive, not delete, governs it.
      final foodRow = await (database.select(database.foods)
            ..where((row) => row.id.equals(batch.foodId)))
          .getSingleOrNull();
      expect(foodRow, isNotNull);
      expect(foodRow!.deletedAt, isNull);
    });

    test('the undo is itself a recoverable Activity Log write', () async {
      final batch = await _applyAgentMealBatch(repositories);

      final undo = await feedRepository.undoBatch(batch.batchId);

      final undoEntries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == undo.undoBatchId)
          .toList(growable: false);
      // One undo row per reverted row, recorded as an 'app' batch.
      expect(undoEntries, hasLength(3));
      expect(undoEntries.every((entry) => entry.actor == 'app'), isTrue);
      // Loser is recoverable: each undo row keeps an after image (the tombstone)
      // and the before image is the live row it replaced.
      expect(undoEntries.every((entry) => entry.afterImage != null), isTrue);
      expect(undoEntries.every((entry) => entry.beforeImage != null), isTrue);
      final mealUndo = undoEntries.firstWhere(
        (entry) => entry.entityTable == AppDatabase.mealsTable,
      );
      expect(mealUndo.beforeImage!['deleted_at'], isNull);
      expect(mealUndo.afterImage!['deleted_at'], isNotNull);
    });

    test(
        'a stale agent replay does not resurrect an already-undone Meal '
        'outside the merge-by-UUID/LWW path', () async {
      final batch = await _applyAgentMealBatch(repositories);
      await feedRepository.undoBatch(batch.batchId);

      // The agent retries the same idempotent write: it pushes the original
      // create images again (same UUIDs, original — now stale — updated_at).
      await _replayAgentMealBatch(repositories, batch);

      // Convergence: the later undo wins LWW, so the Meal stays a tombstone.
      final mealRow = await (database.select(database.meals)
            ..where((row) => row.id.equals(batch.mealId)))
          .getSingleOrNull();
      expect(mealRow!.deletedAt, isNotNull);
      for (final foodEntryId in batch.foodEntryIds) {
        final entryRow = await (database.select(database.foodEntries)
              ..where((row) => row.id.equals(foodEntryId)))
            .getSingleOrNull();
        expect(entryRow!.deletedAt, isNotNull);
      }
      expect(await _activeMealCount(repositories, batch), 0);
    });
  });

  testWidgets('Settings Activity Log renders a logged set batch', (
    tester,
  ) async {
    final feedDatabase = AppDatabase.inMemory();
    addTearDown(feedDatabase.close);
    final feedRepository = _StaticActivityFeedRepository(
      <ActivityFeedBatch>[_loggedSetActivityBatch()],
      TrainingRepositories(feedDatabase),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) => feedDatabase),
          authRepositoryProvider.overrideWith(
            (ref) => InMemoryAuthRepository(),
          ),
          activityFeedRepositoryProvider.overrideWith((ref) => feedRepository),
          homeRepositoryProvider.overrideWith(
            (ref) => StubHomeRepository(),
          ),
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          homeNutritionDayProvider.overrideWith((ref) {
            final selectedDate = ref.watch(selectedTrainingDayProvider);
            return Stream<NutritionDayRecord>.value(
              _emptyNutritionDayFor(selectedDate),
            );
          }),
          settingsRepositoryProvider.overrideWith(
            (ref) => InMemorySettingsRepository(),
          ),
          garminImportConsentStateProvider.overrideWith(
            (ref) => Stream<GarminImportConsentState>.value(
              GarminImportConsentState.empty,
            ),
          ),
          syncStatusControllerProvider.overrideWith(
            _StaticSyncStatusController.new,
          ),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byKey(HomeScreen.accountAndAppButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.accountAndAppSettingsKey));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.activityLogTileKey),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(SettingsScreen.activityLogTileKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.activityLogTileKey));
    await tester.pumpAndSettle();

    expect(find.byType(ActivityFeedScreen), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.textContaining('tester'), findsOneWidget);
    expect(find.textContaining('set'), findsOneWidget);
    expect(find.textContaining('ago'), findsAtLeastNWidgets(1));

    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets('Activity Log cancels its live feed when the screen closes', (
    tester,
  ) async {
    final feedDatabase = AppDatabase.inMemory();
    addTearDown(feedDatabase.close);
    final feedRepository = _CancellationTrackingActivityFeedRepository(
      TrainingRepositories(feedDatabase),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityFeedRepositoryProvider.overrideWith((ref) => feedRepository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ActivityFeedScreen(),
                    ),
                  );
                },
                child: const Text('Open Activity Log'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Activity Log'));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityFeedScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(feedRepository.wasCancelled, isTrue);
  });

  testWidgets('activity feed undo button calls the controller', (
    tester,
  ) async {
    final feedDatabase = AppDatabase.inMemory();
    addTearDown(feedDatabase.close);
    final feedRepository = _StaticActivityFeedRepository(
      <ActivityFeedBatch>[_loggedSetActivityBatch()],
      TrainingRepositories(feedDatabase),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityFeedRepositoryProvider.overrideWith((ref) => feedRepository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ActivityFeedScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(ActivityFeedScreen.undoButtonKey('logged-set-batch')),
    );
    await tester.pump();

    expect(feedRepository.undoneBatchIds, <String>['logged-set-batch']);
    expect(find.text('Activity undone'), findsOneWidget);
  });

  testWidgets('activity feed undo surfaces per-row conflicts', (
    tester,
  ) async {
    final feedDatabase = AppDatabase.inMemory();
    addTearDown(feedDatabase.close);
    final feedRepository = _StaticActivityFeedRepository(
      <ActivityFeedBatch>[_loggedSetActivityBatch()],
      TrainingRepositories(feedDatabase),
      undoResult: ActivityLogUndoResult(
        originalBatchId: 'logged-set-batch',
        undoBatchId: null,
        appliedEntries: <ActivityLogEntry>[],
        conflicts: <ActivityLogUndoConflict>[
          ActivityLogUndoConflict(
            entryId: 'activity-entry',
            entityTable: AppDatabase.loggedSetsTable,
            entityId: 'set-1',
            reason: ActivityLogUndoConflictReason.stale,
            expectedImage: <String, Object?>{'load_entered': '105'},
            currentImage: <String, Object?>{'load_entered': '110'},
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityFeedRepositoryProvider.overrideWith((ref) => feedRepository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ActivityFeedScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(ActivityFeedScreen.undoButtonKey('logged-set-batch')),
    );
    await tester.pump();

    expect(feedRepository.undoneBatchIds, <String>['logged-set-batch']);
    expect(
      find.text('Could not undo 1 changed row: logged_sets set-1'),
      findsOneWidget,
    );
  });

  testWidgets('activity feed shows an agent batch as one attributed entry', (
    tester,
  ) async {
    final feedDatabase = AppDatabase.inMemory();
    addTearDown(feedDatabase.close);
    final feedRepository = _StaticActivityFeedRepository(
      <ActivityFeedBatch>[_agentLoggedSetActivityBatch()],
      TrainingRepositories(feedDatabase),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityFeedRepositoryProvider.overrideWith((ref) => feedRepository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ActivityFeedScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Logged 2 sets'), findsOneWidget);
    expect(find.textContaining('Agent key agent-key-1'), findsOneWidget);
    expect(
      find.semantics.byLabel(
        RegExp(r'^Logged 2 sets, Agent key agent-key-1, 2 changes, '),
      ),
      findsOne,
    );
  });

  testWidgets(
      'activity feed shows an agent Meal batch as one logged-Meal entry', (
    tester,
  ) async {
    final feedDatabase = AppDatabase.inMemory();
    addTearDown(feedDatabase.close);
    final feedRepository = _StaticActivityFeedRepository(
      <ActivityFeedBatch>[_agentMealActivityBatch()],
      TrainingRepositories(feedDatabase),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityFeedRepositoryProvider.overrideWith((ref) => feedRepository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ActivityFeedScreen(),
        ),
      ),
    );
    await tester.pump();

    // One undoable entry for the eating occasion, attributed to the agent.
    expect(find.text('Logged Meal'), findsOneWidget);
    expect(find.textContaining('Agent key agent-key-1'), findsOneWidget);
    expect(
      find.byKey(ActivityFeedScreen.undoButtonKey('agent-meal-batch')),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel(
        RegExp(r'^Logged Meal, Agent key agent-key-1, 3 changes, '),
      ),
      findsOne,
    );
  });

  testWidgets(
      'agent Meal activity entry meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[
      AppTheme.light(),
      AppTheme.dark(),
    ]) {
      final semantics = tester.ensureSemantics();
      final feedDatabase = AppDatabase.inMemory();
      final feedRepository = _StaticActivityFeedRepository(
        <ActivityFeedBatch>[_agentMealActivityBatch()],
        TrainingRepositories(feedDatabase),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activityFeedRepositoryProvider.overrideWith(
              (ref) => feedRepository,
            ),
          ],
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ActivityFeedScreen(),
          ),
        ),
      );
      await tester.pump();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await feedDatabase.close();
    }
  });

  testWidgets('activity feed meets accessibility guidelines in both themes', (
    tester,
  ) async {
    for (final theme in <ThemeData>[
      AppTheme.light(),
      AppTheme.dark(),
    ]) {
      final semantics = tester.ensureSemantics();
      final feedDatabase = AppDatabase.inMemory();
      final feedRepository = _StaticActivityFeedRepository(
        <ActivityFeedBatch>[_loggedSetActivityBatch()],
        TrainingRepositories(feedDatabase),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activityFeedRepositoryProvider.overrideWith(
              (ref) => feedRepository,
            ),
          ],
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ActivityFeedScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.semantics.byLabel(
          RegExp(
            r'^Logged set, tester, 1 change, '
            r'(less than 1 min|\d+ min|\d+ hour[s]?|\d+ day[s]?) ago$',
          ),
        ),
        findsOne,
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await feedDatabase.close();
    }
  });
}

class _StaticActivityFeedRepository extends ActivityFeedRepository {
  _StaticActivityFeedRepository(
      this._batches, TrainingRepositories repositories,
      {ActivityLogUndoResult? undoResult})
      : _undoResult = undoResult,
        super(repositories);

  final List<ActivityFeedBatch> _batches;
  final ActivityLogUndoResult? _undoResult;
  final List<String> undoneBatchIds = <String>[];

  @override
  Future<List<ActivityFeedBatch>> listRecentBatches({DateTime? now}) async {
    return _batches;
  }

  @override
  Stream<List<ActivityFeedBatch>> watchRecentBatches({DateTime? now}) {
    return Stream<List<ActivityFeedBatch>>.value(_batches);
  }

  @override
  Future<ActivityLogUndoResult> undoBatch(
    String batchId, {
    String actor = 'app',
  }) async {
    undoneBatchIds.add(batchId);
    return _undoResult ??
        ActivityLogUndoResult(
          originalBatchId: batchId,
          undoBatchId: 'undo-$batchId',
          appliedEntries: const <ActivityLogEntry>[],
          conflicts: const <ActivityLogUndoConflict>[],
        );
  }
}

class _CancellationTrackingActivityFeedRepository
    extends ActivityFeedRepository {
  _CancellationTrackingActivityFeedRepository(super.repositories);

  bool wasCancelled = false;

  @override
  Stream<List<ActivityFeedBatch>> watchRecentBatches({DateTime? now}) {
    final controller = StreamController<List<ActivityFeedBatch>>(
      onCancel: () {
        wasCancelled = true;
      },
    );
    controller.add(const <ActivityFeedBatch>[]);
    return controller.stream;
  }
}

class _StaticSyncStatusController extends SyncStatusController {
  @override
  Stream<SyncStatusState> build() {
    return Stream<SyncStatusState>.value(
      SyncStatusState.initial(DateTime.utc(2026, 7, 11)),
    );
  }
}

final DateTime _fixedNow = DateTime.utc(2026, 6, 16, 12);

class _AgentMealBatch {
  const _AgentMealBatch({
    required this.batchId,
    required this.mealId,
    required this.foodId,
    required this.foodEntryIds,
    required this.createdAt,
    required this.mealImage,
    required this.foodEntryImages,
  });

  final String batchId;
  final String mealId;
  final String foodId;
  final List<String> foodEntryIds;
  final DateTime createdAt;
  final Map<String, Object?> mealImage;
  final List<Map<String, Object?>> foodEntryImages;
}

/// Materialises an agent nutrition write as it lands on the device after a
/// sync pull: one Meal plus its Food Entry rows, all under a single batch_id
/// with `actor: agent:agent-key-1`, each carrying before/after images.
Future<_AgentMealBatch> _applyAgentMealBatch(
  TrainingRepositories repositories, {
  String batchId = 'agent-meal-batch',
  String mealId = 'agent-meal-1',
  DateTime? createdAt,
}) async {
  const actor = 'agent:agent-key-1';
  const deviceId = 'agent:agent-key-1';
  const foodId = 'user-food-oats';
  final at = createdAt ?? _fixedNow.subtract(const Duration(minutes: 4));
  final iso = at.toUtc().toIso8601String();

  // A User Food catalogue row the agent's Food Entries reference. It must not
  // be touched by undo (archive governs the catalogue, not the log path).
  await repositories.database.into(repositories.database.foods).insert(
        FoodsCompanion.insert(
          id: foodId,
          name: 'Rolled Oats',
          foodSource: const Value<String>('user'),
          nutrientValuesJson: '{"energy_kcal":389}',
          updatedAt: at,
        ),
      );

  final mealImage = <String, Object?>{
    'id': mealId,
    'meal_type': 'Breakfast',
    'started_at': iso,
    'timezone': 'UTC',
    'local_date': '2026-06-16',
    'ended_at': null,
    'updated_at': iso,
    'deleted_at': null,
  };
  await repositories.nutrition.applySyncImage(
    entityTable: AppDatabase.mealsTable,
    image: mealImage,
    deviceId: deviceId,
    actor: actor,
    batchId: batchId,
  );

  final foodEntryIds = <String>['agent-entry-1', 'agent-entry-2'];
  final foodEntryImages = <Map<String, Object?>>[];
  for (var index = 0; index < foodEntryIds.length; index += 1) {
    final image = <String, Object?>{
      'id': foodEntryIds[index],
      'meal_id': mealId,
      'entry_kind': 'food',
      'position': index,
      'name': 'Rolled Oats',
      'nutrient_values_json': '{"energy_kcal":389}',
      'food_id': foodId,
      'portion_json': '{"unit":"g","quantity":100}',
      'food_source': 'user',
      'is_liquid': false,
      'serving_label': null,
      'serving_size': null,
      'package_size': null,
      'updated_at': iso,
      'deleted_at': null,
    };
    foodEntryImages.add(image);
    await repositories.nutrition.applySyncImage(
      entityTable: AppDatabase.foodEntriesTable,
      image: image,
      deviceId: deviceId,
      actor: actor,
      batchId: batchId,
    );
  }

  return _AgentMealBatch(
    batchId: batchId,
    mealId: mealId,
    foodId: foodId,
    foodEntryIds: foodEntryIds,
    createdAt: at,
    mealImage: mealImage,
    foodEntryImages: foodEntryImages,
  );
}

/// Replays the original (now stale) create images through the merge-by-UUID /
/// LWW gate, exactly as the sync pull path does for an idempotent agent retry.
/// The stale `updated_at` must lose to the later undo write, so nothing is
/// resurrected.
Future<void> _replayAgentMealBatch(
  TrainingRepositories repositories,
  _AgentMealBatch batch,
) async {
  Future<void> replay(String entityTable, Map<String, Object?> image) async {
    final id = image['id']! as String;
    final current = await _currentSyncRow(repositories, entityTable, id);
    final incomingUpdatedAt =
        DateTime.parse(image['updated_at']! as String).toUtc();
    if (current != null &&
        !_lwwWins(
          incomingUpdatedAt,
          'agent:agent-key-1',
          current.updatedAt.toUtc(),
          current.deviceId ?? 'agent:agent-key-1',
        )) {
      return;
    }
    await repositories.nutrition.applySyncImage(
      entityTable: entityTable,
      image: image,
      deviceId: 'agent:agent-key-1',
      actor: 'agent:agent-key-1',
      batchId: batch.batchId,
    );
  }

  await replay(AppDatabase.mealsTable, batch.mealImage);
  for (final image in batch.foodEntryImages) {
    await replay(AppDatabase.foodEntriesTable, image);
  }
}

/// Counts the agent batch's Meal in the derived Nutrition Day active view —
/// 0 once the batch is undone (the Meal is a tombstone, never listed).
Future<int> _activeMealCount(
  TrainingRepositories repositories,
  _AgentMealBatch batch,
) async {
  final localDate = batch.createdAt.toUtc();
  final day = NutritionDayDate(
    year: localDate.year,
    month: localDate.month,
    day: localDate.day,
  );
  final days = await repositories.nutrition.nutritionDaysInRange(
    NutritionDayRange(start: day, end: day),
  );
  return days
      .expand((record) => record.meals)
      .where((mealRecord) => mealRecord.meal.id == batch.mealId)
      .length;
}

class _SyncRowState {
  const _SyncRowState({required this.updatedAt, required this.deviceId});

  final DateTime updatedAt;
  final String? deviceId;
}

Future<_SyncRowState?> _currentSyncRow(
  TrainingRepositories repositories,
  String entityTable,
  String id,
) async {
  switch (entityTable) {
    case AppDatabase.mealsTable:
      final row = await (repositories.database.select(
        repositories.database.meals,
      )..where((row) => row.id.equals(id)))
          .getSingleOrNull();
      return row == null
          ? null
          : _SyncRowState(updatedAt: row.updatedAt, deviceId: row.syncDeviceId);
    case AppDatabase.foodEntriesTable:
      final row = await (repositories.database.select(
        repositories.database.foodEntries,
      )..where((row) => row.id.equals(id)))
          .getSingleOrNull();
      return row == null
          ? null
          : _SyncRowState(updatedAt: row.updatedAt, deviceId: row.syncDeviceId);
    default:
      throw ArgumentError.value(entityTable, 'entityTable');
  }
}

bool _lwwWins(
  DateTime incomingUpdatedAt,
  String incomingDeviceId,
  DateTime existingUpdatedAt,
  String existingDeviceId,
) {
  final timestampComparison = incomingUpdatedAt.compareTo(existingUpdatedAt);
  if (timestampComparison != 0) {
    return timestampComparison > 0;
  }
  return incomingDeviceId.compareTo(existingDeviceId) > 0;
}

ActivityFeedBatch _agentMealActivityBatch() {
  final occurredAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 4),
      );
  ActivityLogEntry entry(String id, String table, String entityId) {
    return ActivityLogEntry(
      id: id,
      actor: 'agent:agent-key-1',
      batchId: 'agent-meal-batch',
      entityTable: table,
      entityId: entityId,
      afterImage: <String, Object?>{'id': entityId},
      occurredAt: occurredAt,
      updatedAt: occurredAt,
    );
  }

  return ActivityFeedBatch(
    batchId: 'agent-meal-batch',
    actor: 'agent:agent-key-1',
    occurredAt: occurredAt,
    entries: <ActivityLogEntry>[
      entry('agent-meal-row', AppDatabase.mealsTable, 'agent-meal-1'),
      entry('agent-entry-row-1', AppDatabase.foodEntriesTable, 'agent-entry-1'),
      entry('agent-entry-row-2', AppDatabase.foodEntriesTable, 'agent-entry-2'),
    ],
  );
}

ActivityFeedBatch _loggedSetActivityBatch() {
  final occurredAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 3),
      );
  return ActivityFeedBatch(
    batchId: 'logged-set-batch',
    actor: 'tester',
    occurredAt: occurredAt,
    entries: <ActivityLogEntry>[
      ActivityLogEntry(
        id: 'activity-entry',
        actor: 'tester',
        batchId: 'logged-set-batch',
        entityTable: AppDatabase.loggedSetsTable,
        entityId: 'set-1',
        afterImage: const <String, Object?>{'id': 'set-1'},
        occurredAt: occurredAt,
        updatedAt: occurredAt,
      ),
    ],
  );
}

ActivityFeedBatch _agentLoggedSetActivityBatch() {
  final occurredAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 3),
      );
  return ActivityFeedBatch(
    batchId: 'agent-batch',
    actor: 'agent:agent-key-1',
    occurredAt: occurredAt,
    entries: <ActivityLogEntry>[
      ActivityLogEntry(
        id: 'activity-entry-1',
        actor: 'agent:agent-key-1',
        batchId: 'agent-batch',
        entityTable: AppDatabase.loggedSetsTable,
        entityId: 'set-1',
        afterImage: const <String, Object?>{'id': 'set-1'},
        occurredAt: occurredAt,
        updatedAt: occurredAt,
      ),
      ActivityLogEntry(
        id: 'activity-entry-2',
        actor: 'agent:agent-key-1',
        batchId: 'agent-batch',
        entityTable: AppDatabase.loggedSetsTable,
        entityId: 'set-2',
        afterImage: const <String, Object?>{'id': 'set-2'},
        occurredAt: occurredAt,
        updatedAt: occurredAt,
      ),
    ],
  );
}

NutritionDayRecord _emptyNutritionDayFor(TrainingDayDate localDate) {
  return NutritionDayRecord(
    localDate: NutritionDayDate(
      year: localDate.year,
      month: localDate.month,
      day: localDate.day,
    ),
    meals: const <NutritionDayMealRecord>[],
  );
}

Future<void> _insertActivityRow(
  AppDatabase database, {
  required String id,
  required String actor,
  required String batchId,
  required String entityTable,
  required DateTime occurredAt,
}) async {
  await database.into(database.activityLog).insert(
        ActivityLogCompanion.insert(
          id: id,
          actor: actor,
          batchId: batchId,
          entityTable: entityTable,
          entityId: '$id-entity',
          beforeImage: const Value<String?>('{"before":true}'),
          afterImage: const Value<String?>('{"after":true}'),
          occurredAt: occurredAt,
          updatedAt: occurredAt,
        ),
      );
}

Future<LogWorkoutResult> _logWorkoutWithSet(
  TrainingRepositories repositories, {
  required String actor,
}) async {
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Bench Press',
      type: ExerciseType(
        const <DimensionId>[DimensionId.load, DimensionId.reps],
      ),
    ),
    actor: 'setup',
  );
  final startedAt = DateTime.utc(2026, 6, 16, 10);
  return repositories.logWorkoutWithSet(
    WorkoutSessionDraft(
      startedAt: startedAt,
      timezone: 'UTC',
      localDate: TrainingDayDate.fromDateTime(startedAt),
    ),
    LoggedSetDraft(
      exerciseId: exerciseId,
      position: 0,
      values: _weightRepsSet(load: '100', reps: '5'),
    ),
    actor: actor,
  );
}

LoggedSet _weightRepsSet({
  required String load,
  required String reps,
}) {
  return LoggedSet.fromValues(
    <SetDimensionValue>[
      SetDimensionValue(
        dimension: DimensionId.load,
        entered: load,
        unit: TrainingUnit.kilogram,
      ),
      SetDimensionValue(
        dimension: DimensionId.reps,
        entered: reps,
        unit: TrainingUnit.repetition,
      ),
    ],
  );
}
