import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';

import '../../tool/test_data/test_data_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
      warnAboutMultipleDatabases);

  // A Sunday, so two weeks cover two full Monday–Sunday programs.
  const options = TestDataOptions(
    endDate: TrainingDayDate(year: 2026, month: 6, day: 28),
    weeks: 2,
    seed: 7,
  );

  late AppDatabase database;
  late TrainingRepositories repositories;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
  });

  tearDown(() => database.close());

  test('writes finished workouts whose sets all use library exercises',
      () async {
    final summary = await generateTestData(repositories, options);

    final workouts = await repositories.workoutSessions.listActive();
    expect(workouts, hasLength(summary.workouts));
    expect(summary.workouts, greaterThanOrEqualTo(6));
    expect(workouts.every((workout) => workout.endedAt != null), isTrue);

    final library = {
      for (final exercise in await repositories.exercises.listActive())
        exercise.id: exercise,
    };
    var setCount = 0;
    for (final workout in workouts) {
      final sets = await repositories.sets.listActiveForWorkout(workout.id);
      setCount += sets.length;
      for (final set in sets) {
        expect(LibraryExercise.all, contains(set.exerciseId));
        expect(library[set.exerciseId]?.origin, ExerciseLibraryOrigin.platform);
        expect(set.isCompleted, isTrue);
      }
    }
    expect(setCount, summary.sets);

    final dates = workouts.map((workout) => workout.localDate).toList()..sort();
    expect(
        dates.first
            .compareTo(const TrainingDayDate(year: 2026, month: 6, day: 15)),
        greaterThanOrEqualTo(0));
    expect(dates.last.compareTo(options.endDate), lessThanOrEqualTo(0));
  });

  test('logs body weight and meals', () async {
    final summary = await generateTestData(repositories, options);

    final bodyWeight = (await repositories.measurements.listEnabled())
        .singleWhere((measurement) => measurement.name == 'Body Weight');
    final entries = await repositories.measurements
        .listHistoryEntries(measurementId: bodyWeight.id);
    expect(entries, hasLength(summary.bodyWeightEntries));
    expect(summary.bodyWeightEntries, greaterThan(0));
    expect(summary.meals, greaterThan(0));
    expect(summary.foodEntries, greaterThanOrEqualTo(summary.meals));
  });

  test('the same seed produces the same history', () async {
    final first = await generateTestData(repositories, options);

    final otherDatabase = AppDatabase.inMemory();
    addTearDown(otherDatabase.close);
    final second =
        await generateTestData(TrainingRepositories(otherDatabase), options);

    expect(second.toString(), first.toString());
  });

  test('round-trips through a portable archive into a fresh database',
      () async {
    final summary = await generateTestData(repositories, options);
    final archive = await repositories.portableArchives.exportPortableArchive();

    final restoredDatabase = AppDatabase.inMemory();
    addTearDown(restoredDatabase.close);
    final restored = TrainingRepositories(restoredDatabase);
    await restored.portableArchives.importPortableArchive(archive);

    expect(await restored.workoutSessions.listActive(),
        hasLength(summary.workouts));
  });
}
