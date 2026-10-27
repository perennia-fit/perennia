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

  test('logs the supplement stack: its Compounds, Protocols and Doses',
      () async {
    final summary = await generateTestData(repositories, options);
    final protocols = repositories.protocols;

    final compounds = await protocols.listCompounds();
    for (final name in const [
      'TRT',
      'AgeMate',
      'MNEM',
      'Creatine',
      'GHK-Cu',
      'BPC-157',
    ]) {
      expect(
        compounds.where((compound) => compound.name == name),
        hasLength(1),
        reason: name,
      );
    }
    expect(summary.compounds, 6);

    final byName = {
      for (final protocol in await protocols.listProtocols())
        protocol.name: protocol,
    };
    expect(byName.keys, unorderedEquals(['Daily', 'Skin', 'Shoulder']));
    expect(summary.protocols, 3);
    const rangeStart = ProtocolDayDate(year: 2026, month: 6, day: 15);
    expect(byName['Daily']!.startLocalDate, rangeStart);
    expect(byName['Daily']!.members, hasLength(4));
    final skin = byName['Skin']!;
    expect(skin.startLocalDate,
        const ProtocolDayDate(year: 2026, month: 4, day: 29));
    expect(skin.period!.cycle!.onDays, 60);
    expect(skin.period!.cycle!.offDays, 30);
    final shoulder = byName['Shoulder']!;
    expect(
      shoulder.startLocalDate,
      const ProtocolDayDate(year: 2026, month: 6, day: 18),
    );
    // 20 doses at one a day: the helper's end date, inclusive.
    expect(
      shoulder.endLocalDate,
      const ProtocolDayDate(year: 2026, month: 7, day: 7),
    );
    for (final protocol in byName.values) {
      for (final member in protocol.members) {
        expect(member.currentVersion!.rule, isA<TimedScheduleRule>());
      }
    }

    // Every planned dose of the two weeks, one day in six left unlogged:
    // days 5 and 11 of the range. Daily plans four a day on all 14 days;
    // Skin is on through 2026-06-27 (cycle days 0-59) and off on the
    // range's last day; Shoulder runs from 2026-06-18.
    final doses = <DoseRecord>[];
    for (var day = 0; day < 14; day += 1) {
      doses.addAll(
        (await protocols.protocolDay(rangeStart.addDays(day))).doses,
      );
    }
    const loggedDays = 12;
    const shoulderLoggedDays = 9; // 2026-06-18 to 06-28, less 06-20, 06-26
    const skinLoggedDays = 11; // 2026-06-15 to 06-27, less 06-20, 06-26
    expect(
      doses,
      hasLength(4 * loggedDays + skinLoggedDays + shoulderLoggedDays),
    );
    expect(summary.doses, doses.length);
    expect(doses.every((dose) => dose.protocolId != null), isTrue);
    expect(
      doses.every((dose) => dose.timezoneOffsetMinutes != null),
      isTrue,
    );
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
