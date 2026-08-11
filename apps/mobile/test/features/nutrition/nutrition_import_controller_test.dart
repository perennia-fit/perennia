import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_import_controller.dart';
import 'package:perennia/features/nutrition/import/cronometer_csv_import_adapter.dart';
import 'package:perennia/features/nutrition/import/nutrition_import_consent_repository.dart';

class _DeferredNutritionImportParser implements NutritionImportParser {
  final completer = Completer<NutritionImportBatch>();
  final providers = <NutritionImportProvider>[];
  String? content;

  @override
  Future<NutritionImportBatch> parse({
    required NutritionImportProvider provider,
    required String content,
  }) {
    providers.add(provider);
    this.content = content;
    return completer.future;
  }
}

const _csv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g)
2026-06-01,08:00,Breakfast,Oats,100 g,389,16.9,66.3,6.9
''';

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

  group('NutritionImportController', () {
    late AppDatabase database;
    late ProviderContainer container;
    late _DeferredNutritionImportParser parser;

    setUp(() {
      database = AppDatabase.inMemory();
      parser = _DeferredNutritionImportParser();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          nutritionImportParserProvider.overrideWithValue(parser),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    test('keeps the import busy while file parsing is still pending', () async {
      await container.read(nutritionImportControllerProvider.future);
      await container
          .read(nutritionImportConsentRepositoryProvider)
          .setConsent(enabled: true);

      final controller =
          container.read(nutritionImportControllerProvider.notifier);
      final importFuture = controller.landFileText('large export');

      expect(parser.providers, <NutritionImportProvider>[
        NutritionImportProvider.cronometer,
      ]);
      expect(parser.content, 'large export');
      expect(
        container.read(nutritionImportControllerProvider).value?.phase,
        NutritionImportPhase.importing,
      );

      parser.completer.complete(const CronometerCsvImportAdapter().parse(_csv));

      final result = await importFuture;
      expect(result?.importedCount, 1);
      expect(
        container.read(nutritionImportControllerProvider).value?.phase,
        NutritionImportPhase.done,
      );
    });

    test('default parser parses provider exports in an isolate', () async {
      final batch = await const IsolateNutritionImportParser().parse(
        provider: NutritionImportProvider.cronometer,
        content: _csv,
      );

      expect(batch.meals.single.entries.single.name, 'Oats');
    });
  });
}
