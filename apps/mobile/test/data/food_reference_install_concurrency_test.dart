import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/local/food_reference_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';

import 'open_food_facts_fixtures.dart';

/// While an install holds its transaction open on its own connection (as the
/// install isolate does), the app's connection still reads, the user's
/// database still saves, and a kept product waits for the lock instead of
/// failing (docs/designs/open-food-facts.md, "Installing the bundle on the
/// device"). Real files, because WAL and the busy timeout need them.
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
      warnAboutMultipleDatabases);

  late Directory directory;
  late File referenceFile;
  late FoodReferenceDatabase app;
  late FoodReferenceDatabase installer;
  late Completer<void> release;
  late Future<void> install;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('food_reference_');
    referenceFile = File(p.join(directory.path, 'food_reference.sqlite'));
    app = FoodReferenceDatabase.connect(referenceFile);
    // Create the schema and a first bundle on the app's connection.
    await app.replaceBundle(
      bundleLines([offProduct('1001', 'Committed oats')]),
      bundleHeader(contentHash: 'hash-1', productCount: 1),
    );
    installer = FoodReferenceDatabase.openInIsolate(referenceFile);

    release = Completer<void>();
    final started = Completer<void>();
    install = installer.replaceBundle(
      bundleLines([offProduct('2002', 'New bundle milk')]),
      bundleHeader(contentHash: 'hash-2', productCount: 1),
      beforeCommitForTesting: () {
        started.complete();
        return release.future;
      },
    );
    await started.future;
  });

  tearDown(() async {
    if (!release.isCompleted) {
      release.complete();
    }
    await install;
    await installer.close();
    await app.close();
    await directory.delete(recursive: true);
  });

  test('a read on the app connection returns the committed state in 100 ms',
      () async {
    final stopwatch = Stopwatch()..start();
    final rows = await app.productsByCodes(<String>['1001', '2002']);
    stopwatch.stop();

    expect([for (final row in rows) row.code], ['1001']);
    expect(stopwatch.elapsedMilliseconds, lessThan(100));
  });

  test('a Food Entry save on the user database completes', () async {
    final database = AppDatabase.openFile(
      File(p.join(directory.path, 'perennia.sqlite')),
    );
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);

    final mealId = await repositories.nutrition.createMeal(
      MealDraft(
        mealType: 'Breakfast',
        startedAt: DateTime.utc(2026, 10, 27, 7),
        timezone: 'Australia/Brisbane',
        localDate: const NutritionDayDate(year: 2026, month: 10, day: 27),
      ),
    );

    expect(await repositories.nutrition.getMealById(mealId), isNotNull);
  });

  test('keepProduct on the app connection completes after the install',
      () async {
    var kept = false;
    final keep = app
        .keepProduct(
          productCompanion(offProduct('3003', 'Opened'), origin: originOnline),
        )
        .then((_) => kept = true);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(kept, isFalse, reason: 'it waits for the install lock');

    release.complete();
    await install;
    await keep.timeout(const Duration(seconds: 5));

    final rows = await app.productsByCodes(<String>['1001', '2002', '3003']);
    expect([for (final row in rows) row.code], ['2002', '3003']);
  });
}
