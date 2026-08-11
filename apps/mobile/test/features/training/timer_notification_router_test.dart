import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/training/services/timer_notification_router.dart';
import 'package:perennia/l10n/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('TimerNotificationRouter', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets('pushes the exercise once for a live target', (tester) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(repositories),
      );
      final observer = _RouteObserver();
      final harness = await _pumpRouterHost(
        tester,
        repositories,
        observer: observer,
      );

      await tester.runAsync(() => harness.router.handleTap(workoutExerciseId!));
      await tester.pumpAndSettle();

      expect(
        observer.pushedNames,
        contains(timerExerciseRouteName(workoutExerciseId!)),
      );
      // The pushed route is the exercise screen, not a missing-target snackbar.
      expect(find.text('exercise:$workoutExerciseId'), findsOneWidget);
      expect(find.text(_missingMessage), findsNothing);
    });

    testWidgets('does not push and shows a snackbar for an archived target', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(repositories),
      );
      await tester.runAsync(
        () => repositories.workoutExercises.softDelete(workoutExerciseId!),
      );
      final observer = _RouteObserver();
      final harness = await _pumpRouterHost(
        tester,
        repositories,
        observer: observer,
      );

      await tester.runAsync(() => harness.router.handleTap(workoutExerciseId!));
      await tester.pump();

      expect(
        observer.pushedNames,
        isNot(contains(timerExerciseRouteName(workoutExerciseId!))),
      );
      expect(find.text(_missingMessage), findsOneWidget);
    });

    testWidgets('shows a snackbar when the target does not exist', (
      tester,
    ) async {
      final observer = _RouteObserver();
      final harness = await _pumpRouterHost(
        tester,
        repositories,
        observer: observer,
      );

      await tester.runAsync(() => harness.router.handleTap('missing-id'));
      await tester.pump();

      expect(
        observer.pushedNames.where((name) => name.startsWith('/exercise/')),
        isEmpty,
      );
      expect(find.text(_missingMessage), findsOneWidget);
    });

    testWidgets('a duplicate tap does not push the same exercise twice', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(repositories),
      );
      final observer = _RouteObserver();
      final harness = await _pumpRouterHost(
        tester,
        repositories,
        observer: observer,
      );

      await tester.runAsync(() => harness.router.handleTap(workoutExerciseId!));
      await tester.pumpAndSettle();
      // Second tap while the exercise is already on top: no-op.
      await tester.runAsync(() => harness.router.handleTap(workoutExerciseId!));
      await tester.pumpAndSettle();

      final matches = observer.pushedNames
          .where((name) => name == timerExerciseRouteName(workoutExerciseId!))
          .length;
      expect(matches, 1);
    });
  });
}

const _missingMessage = 'That exercise is no longer in the workout';

class _RouterHarness {
  _RouterHarness(this.router);

  final TimerNotificationRouter router;
}

Future<_RouterHarness> _pumpRouterHost(
  WidgetTester tester,
  TrainingRepositories repositories, {
  required _RouteObserver observer,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  final router = TimerNotificationRouter(
    navigatorKey: navigatorKey,
    scaffoldMessengerKey: messengerKey,
    resolveWorkoutExercise: (id) =>
        repositories.workoutExercises.getById(id),
    // A channel name no native side answers: `start()` is never called here,
    // and we drive `handleTap` directly.
    channel: const MethodChannel('test_timer_notification_router'),
    // A lightweight destination keeps the test to the router's own logic —
    // resolve, dedup, push, snackbar — without pumping the full ExercisePage.
    pageBuilder: (workoutExerciseId) => (_) => Scaffold(
          body: Center(child: Text('exercise:$workoutExerciseId')),
        ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => repositories.database),
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        navigatorObservers: [observer],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TrainingScreenHostHome(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _RouterHarness(router);
}

class TrainingScreenHostHome extends StatelessWidget {
  const TrainingScreenHostHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('home')));
  }
}

class _RouteObserver extends NavigatorObserver {
  final pushedNames = <String>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) {
      pushedNames.add(name);
    }
    super.didPush(route, previousRoute);
  }
}

Future<String> _createWorkoutExercise(TrainingRepositories repositories) async {
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Bench Press',
      type: ExerciseType(
        const <DimensionId>[DimensionId.load, DimensionId.reps],
      ),
    ),
  );
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 7, 4, 6),
      timezone: 'Australia/Brisbane',
    ),
  );
  return repositories.workoutExercises.create(
    WorkoutExerciseDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
    ),
  );
}
