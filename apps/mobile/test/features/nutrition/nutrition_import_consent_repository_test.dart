import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/features/nutrition/import/nutrition_import_consent_repository.dart';

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

  group('NutritionImportConsentRepository', () {
    late AppDatabase database;
    late NutritionImportConsentRepository repository;

    setUp(() {
      database = AppDatabase.inMemory();
      repository = NutritionImportConsentRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('defaults to no consent', () async {
      expect(await repository.hasConsent(), isFalse);
    });

    test('grants and revokes consent', () async {
      await repository.setConsent(enabled: true);
      expect(await repository.hasConsent(), isTrue);

      await repository.setConsent(enabled: false);
      expect(await repository.hasConsent(), isFalse);
    });

    test('granting consent is idempotent (no duplicate rows)', () async {
      await repository.setConsent(enabled: true);
      await repository.setConsent(enabled: true);
      final rows =
          await database.select(database.integrationDataClassConsents).get();
      expect(rows, hasLength(1));
      expect(await repository.hasConsent(), isTrue);
    });

    test('streams consent changes', () async {
      final values = <bool>[];
      final sub = repository.watchConsent().listen(values.add);
      await repository.setConsent(enabled: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      expect(values.last, isTrue);
    });
  });
}
