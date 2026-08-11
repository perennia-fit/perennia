import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/catalog/search/exercise_search.dart';

void main() {
  group('exerciseNameMatchesQuery', () {
    test('matches partial multi-term queries case-insensitively', () {
      expect(exerciseNameMatchesQuery('Barbell Press', 'ba pr'), isTrue);
      expect(exerciseNameMatchesQuery('Barbell Press', 'PR BA'), isTrue);
      expect(
          exerciseNameMatchesQuery('Barbell Press', '  bell   ess  '), isTrue);
    });

    test('requires every term to appear in the exercise name', () {
      expect(exerciseNameMatchesQuery('Barbell Press', 'ba row'), isFalse);
      expect(exerciseNameMatchesQuery('Mobility Flow', 'mob squat'), isFalse);
    });

    test('treats blank search as matching every exercise', () {
      expect(exerciseNameMatchesQuery('Barbell Press', ''), isTrue);
      expect(exerciseNameMatchesQuery('Barbell Press', '   '), isTrue);
    });
  });
}
