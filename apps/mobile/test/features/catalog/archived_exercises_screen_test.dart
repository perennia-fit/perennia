import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/catalog/widgets/archived_exercises_screen.dart';
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

  late AppDatabase database;
  late TrainingRepositories repositories;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(
      database,
      platformSeedSource: const _ArchivedExerciseSeedSource(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('restores archived user exercises', (tester) async {
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Tempo Row',
        type: ExerciseType(<DimensionId>[DimensionId.reps]),
      ),
    );
    await repositories.exercises.softDelete(exerciseId);
    await _pumpArchivedExercises(tester, repositories);

    expect(find.text('Tempo Row'), findsOneWidget);

    await tester.tap(
      find.byKey(ArchivedExercisesScreen.restoreButtonKey(exerciseId)),
    );
    await tester.pumpAndSettle();

    final restored = await repositories.exercises.getById(exerciseId);
    expect(restored?.deletedAt, isNull);
    expect(await repositories.exercises.listArchivedUser(), isEmpty);
    expect(find.text('Tempo Row'), findsNothing);
    expect(find.text('No archived exercises'), findsOneWidget);
  });

  testWidgets('explains restore name conflicts', (tester) async {
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Tempo Row',
        type: ExerciseType(<DimensionId>[DimensionId.reps]),
      ),
    );
    await repositories.exercises.softDelete(exerciseId);
    await repositories.exercises.create(
      ExerciseDraft(
        name: 'tempo row',
        type: ExerciseType(<DimensionId>[DimensionId.reps]),
      ),
    );
    await _pumpArchivedExercises(tester, repositories);

    await tester.tap(
      find.byKey(ArchivedExercisesScreen.restoreButtonKey(exerciseId)),
    );
    await tester.pumpAndSettle();

    final archived = await repositories.exercises.getById(exerciseId);
    expect(archived?.deletedAt, isNotNull);
    expect(
      find.text(
        'An active user exercise with this name already exists. Rename the '
        'active exercise before restoring.',
      ),
      findsOneWidget,
    );
    expect(find.text('Tempo Row'), findsOneWidget);
  });
}

Future<void> _pumpArchivedExercises(
  WidgetTester tester,
  TrainingRepositories repositories,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ArchivedExercisesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ArchivedExerciseSeedSource implements PlatformExerciseSeedSource {
  const _ArchivedExerciseSeedSource();

  @override
  Future<PlatformExerciseSeed> load() async {
    return PlatformExerciseSeed(
      categories: const <SeedExerciseCategory>[],
      exercises: const <SeedExercise>[],
    );
  }
}
