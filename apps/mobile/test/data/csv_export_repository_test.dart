import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

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

  group('CSV export repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('exports workout history as dimension-aware one-way CSV', () async {
      await _seedCsvWorkoutHistory(repositories);
      final exportDir = await Directory.systemTemp.createTemp('prn_csv_');
      addTearDown(() => exportDir.delete(recursive: true));
      final destination = File('${exportDir.path}/history.csv');

      final csv = await repositories.csvExports.exportWorkoutHistoryCsv();
      await repositories.csvExports.exportWorkoutHistoryCsvToFile(destination);
      final writtenCsv = await destination.readAsString();
      final rows = _csvRowsAsMaps(csv);

      expect(writtenCsv, csv);
      expect(_parseCsv(csv).first, CsvExportRepository.workoutHistoryColumns);
      expect(rows, hasLength(2));

      final bench = rows.singleWhere(
        (row) => row['exercise_name'] == 'Bench Press',
      );
      expect(bench['local_date'], '2026-06-14');
      expect(bench['workout_started_at'], '2026-06-13T20:30:00.000Z');
      expect(bench['timezone'], 'Australia/Brisbane');
      expect(bench['set_position'], '0');
      expect(bench['is_completed'], 'true');
      expect(bench['load_entered'], '102.5');
      expect(bench['load_unit'], 'kilogram');
      expect(bench['load_value'], '102.5');
      expect(bench['reps_entered'], '5');
      expect(bench['reps_unit'], 'repetition');
      expect(bench['reps_value'], '5.0');
      expect(bench['duration_entered'], isEmpty);
      expect(bench['distance_entered'], isEmpty);
      expect(bench['comment'], 'Heavy, "smooth"');
      expect(bench['side'], 'left');
      expect(bench['rpe'], '8.5');

      final run = rows.singleWhere(
        (row) => row['exercise_name'] == 'Park Run',
      );
      expect(run['local_date'], '2026-06-15');
      expect(run['distance_entered'], '5');
      expect(run['distance_unit'], 'kilometer');
      expect(run['distance_value'], '5.0');
      expect(run['duration_entered'], '1800');
      expect(run['duration_unit'], 'second');
      expect(run['duration_value'], '1800.0');
      expect(run['load_entered'], isEmpty);
      expect(run['reps_entered'], isEmpty);
      expect(run['comment'], 'Felt steady');
    });

    test(
        'excludes Protocols (Compound/Dose) from CSV export by default '
        ' (PROTOCOLS.md §8)', () async {
      await _seedCsvWorkoutHistory(repositories);
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Redacted Test Compound',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.subcutaneous,
          strength: CompoundStrength.parse('50 mg/mL'),
        ),
        actor: 'tester',
      );
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: compound.compoundId,
          compoundName: 'Redacted Test Compound',
          compoundStrength: CompoundStrength.parse('50 mg/mL'),
          amountValue: 12.5,
          amountEntered: '12.5',
          unit: DoseUnit.milligram,
          route: DoseRoute.subcutaneous,
          tookAt: DateTime.utc(2026, 6, 20, 8),
        ),
        actor: 'tester',
      );

      final csv = await repositories.csvExports.exportWorkoutHistoryCsv();

      // No trace of the seeded Dose/Compound content leaks into the CSV.
      for (final protocolsValue in <String>[
        'Redacted Test Compound',
        'subcutaneous',
        '12.5',
        '50 mg/mL',
      ]) {
        expect(csv, isNot(contains(protocolsValue)));
      }

      // The exported column schema itself carries no Compound/Dose
      // vocabulary — an explicit, permanent lock on the shape of the
      // export, not an accident of what happens to be seeded above.
      const protocolsVocabulary = <String>['compound', 'dose', 'route'];
      for (final column in CsvExportRepository.workoutHistoryColumns) {
        for (final word in protocolsVocabulary) {
          expect(column.toLowerCase(), isNot(contains(word)), reason: column);
        }
      }
    });

    test('does not expose a CSV import affordance', () {
      expect(CsvExportRepository.supportsImport, isFalse);
      final libSources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(
        libSources,
        isNot(
          contains(
            RegExp(
              r'\b(importCsv|importWorkoutHistoryCsv|CsvImport|csvImport)\b',
            ),
          ),
        ),
      );
    });
  });
}

Future<void> _seedCsvWorkoutHistory(TrainingRepositories repositories) async {
  final benchId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Bench Press',
      type: ExerciseType(<DimensionId>[
        DimensionId.load,
        DimensionId.reps,
      ]),
      usesRpe: true,
      isUnilateral: true,
    ),
    actor: 'tester',
  );
  final runId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Park Run',
      type: ExerciseType(<DimensionId>[
        DimensionId.distance,
        DimensionId.duration,
      ]),
    ),
    actor: 'tester',
  );
  final liftWorkoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 6, 13, 20, 30),
      timezone: 'Australia/Brisbane',
      localDate: const TrainingDayDate(year: 2026, month: 6, day: 14),
    ),
    actor: 'tester',
  );
  final runWorkoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 6, 14, 21),
      timezone: 'Australia/Brisbane',
      localDate: const TrainingDayDate(year: 2026, month: 6, day: 15),
    ),
    actor: 'tester',
  );

  await repositories.sets.create(
    LoggedSetDraft(
      workoutId: liftWorkoutId,
      exerciseId: benchId,
      position: 0,
      values: LoggedSet.fromValues(
        const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.load,
            entered: '102.5',
            unit: TrainingUnit.kilogram,
          ),
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '5',
            unit: TrainingUnit.repetition,
          ),
        ],
      ),
      comment: 'Heavy, "smooth"',
      side: SetSide.left,
      rpe: 8.5,
      isCompleted: true,
    ),
    actor: 'tester',
  );
  await repositories.sets.create(
    LoggedSetDraft(
      workoutId: runWorkoutId,
      exerciseId: runId,
      position: 0,
      values: LoggedSet.fromValues(
        const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.distance,
            entered: '5',
            unit: TrainingUnit.kilometer,
          ),
          SetDimensionValue(
            dimension: DimensionId.duration,
            entered: '1800',
            unit: TrainingUnit.second,
          ),
        ],
      ),
      comment: 'Felt steady',
    ),
    actor: 'tester',
  );
}

List<Map<String, String>> _csvRowsAsMaps(String csv) {
  final rows = _parseCsv(csv);
  final header = rows.first;
  return rows.skip(1).map((row) {
    return <String, String>{
      for (var index = 0; index < header.length; index += 1)
        header[index]: row[index],
    };
  }).toList(growable: false);
}

List<List<String>> _parseCsv(String csv) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  for (var index = 0; index < csv.length; index += 1) {
    final char = csv[index];
    if (inQuotes) {
      if (char == '"' && index + 1 < csv.length && csv[index + 1] == '"') {
        field.write('"');
        index += 1;
      } else if (char == '"') {
        inQuotes = false;
      } else {
        field.write(char);
      }
      continue;
    }

    if (char == '"') {
      inQuotes = true;
    } else if (char == ',') {
      row.add(field.toString());
      field.clear();
    } else if (char == '\n') {
      row.add(field.toString());
      rows.add(row);
      row = <String>[];
      field.clear();
    } else if (char != '\r') {
      field.write(char);
    }
  }

  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
