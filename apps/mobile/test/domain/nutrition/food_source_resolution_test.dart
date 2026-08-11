import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/nutrition/nutrition_import.dart';

void main() {
  group('resolveImportedFoodSource', () {
    test('a recognised provider resolves to its specific Food Source registry '
        'value with a canonical import source and no preserved string', () {
      final resolution = resolveImportedFoodSource('Cronometer');

      expect(resolution.foodSource, FoodSource.cronometer);
      expect(resolution.importSource, 'cronometer');
      // A recognised provider needs no free-text preservation: the enum value
      // already names it (mirrors INTEGRATIONS.md §6 — a mapped vendor type
      // does not keep a separate vendor string).
      expect(resolution.preservedProvider, isNull);
    });

    test('recognition is case- and whitespace-insensitive', () {
      final resolution = resolveImportedFoodSource('  cRoNoMeTeR  ');
      expect(resolution.foodSource, FoodSource.cronometer);
      expect(resolution.importSource, 'cronometer');
      expect(resolution.preservedProvider, isNull);
    });

    test('an unrecognised provider resolves to the generic Imported origin and '
        'PRESERVES the exact provider string', () {
      final resolution = resolveImportedFoodSource('Acme Diet Tracker');

      expect(resolution.foodSource, FoodSource.imported);
      // The preserved string keeps the provider's exact, human-facing name so
      // it can be surfaced and later promoted (NUTRITION.md §9; INTEGRATIONS.md
      // §6 preserved-vendor-string rule).
      expect(resolution.preservedProvider, 'Acme Diet Tracker');
      // The idempotency-key source is a normalised, stable id derived from the
      // provider — distinct from the human-facing preserved string.
      expect(resolution.importSource, 'acme-diet-tracker');
    });

    test('an unrecognised provider preserves the trimmed original casing', () {
      final resolution = resolveImportedFoodSource('  MyObscureApp v2  ');
      expect(resolution.foodSource, FoodSource.imported);
      expect(resolution.preservedProvider, 'MyObscureApp v2');
      expect(resolution.importSource, 'myobscureapp-v2');
    });

    test('a blank provider string is rejected (an import always has a provider)',
        () {
      expect(
        () => resolveImportedFoodSource('   '),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
