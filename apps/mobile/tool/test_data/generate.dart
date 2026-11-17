/// Writes a ready-to-open app database full of test data.
///
/// Run through `flutter test` rather than `dart run` because the repositories
/// need Flutter's asset bundle to load the Platform Exercise Library. Use the
/// wrapper instead of calling this directly: `pnpm test-data` from the
/// repository root generates the file and loads it onto a device.
///
///   flutter test tool/test_data/generate.dart \
///     --dart-define=OUT=/abs/path/perennia.sqlite \
///     --dart-define=WEEKS=12 --dart-define=SEED=42 \
///     --dart-define=END=2026-10-23 --dart-define=TIMEZONE=UTC
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';

import 'test_data_generator.dart';

const _out = String.fromEnvironment('OUT');
const _weeks = int.fromEnvironment('WEEKS', defaultValue: 12);
const _seed = int.fromEnvironment('SEED', defaultValue: 42);
const _end = String.fromEnvironment('END');
const _timezone = String.fromEnvironment('TIMEZONE', defaultValue: 'UTC');
const _nutrition = bool.fromEnvironment('NUTRITION', defaultValue: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('generate test data', () async {
    if (_out.isEmpty) {
      fail('Pass --dart-define=OUT=/absolute/path/perennia.sqlite');
    }
    final file = File(_out);
    // A fresh file every time: generating into an existing database would
    // stack a second history on top of the first.
    for (final suffix in const ['', '-journal', '-wal', '-shm']) {
      final stale = File('$_out$suffix');
      if (stale.existsSync()) {
        stale.deleteSync();
      }
    }
    file.parent.createSync(recursive: true);

    final database = AppDatabase.openFile(file);
    try {
      final summary = await generateTestData(
        TrainingRepositories(database),
        TestDataOptions(
          endDate: _end.isEmpty
              ? TrainingDayDate.fromDateTime(DateTime.now())
              : TrainingDayDate.parse(_end),
          weeks: _weeks,
          seed: _seed,
          timezone: _timezone,
          includeNutrition: _nutrition,
        ),
      );
      // ignore: avoid_print
      print('TEST_DATA_SUMMARY $summary -> ${file.path}');
    } finally {
      await database.close();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
