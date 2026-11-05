import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/template_divergence/widgets/template_divergence_diff_text.dart';
import 'package:perennia/l10n/app_localizations_en.dart';

TemplateDivergenceExerciseRef _exercise(String name) {
  return TemplateDivergenceExerciseRef(
      exerciseId: 'e-$name', exerciseName: name);
}

/// Names deliberately out of alphabetical order, so a sort would show.
final _everyKind = TemplateDivergenceResult(
  addedExercises: [_exercise('Dips'), _exercise('Curl')],
  removedExercises: [_exercise('Hip Thrust'), _exercise('Calf Raise')],
  changedExercises: [_exercise('Deadlift'), _exercise('Bench Press')],
  groupsChanged: true,
);

const _noChanges = TemplateDivergenceResult(
  addedExercises: <TemplateDivergenceExerciseRef>[],
  removedExercises: <TemplateDivergenceExerciseRef>[],
  changedExercises: <TemplateDivergenceExerciseRef>[],
  groupsChanged: false,
);

void main() {
  final l10n = AppLocalizationsEn();

  group('templateDivergenceLines', () {
    test(
        'lists added, then removed, then changed, then groups, each kind in '
        'its given order', () {
      expect(templateDivergenceLines(_everyKind, l10n), [
        'Add Dips',
        'Add Curl',
        'Remove Hip Thrust',
        'Remove Calf Raise',
        'Deadlift: sets changed',
        'Bench Press: sets changed',
        'Exercise groups changed',
      ]);
    });

    test('has no groups line when groups did not change', () {
      final result = TemplateDivergenceResult(
        addedExercises: [_exercise('Dips')],
        removedExercises: const <TemplateDivergenceExerciseRef>[],
        changedExercises: const <TemplateDivergenceExerciseRef>[],
        groupsChanged: false,
      );

      expect(templateDivergenceLines(result, l10n), ['Add Dips']);
    });

    test('is empty with no changes', () {
      expect(templateDivergenceLines(_noChanges, l10n), isEmpty);
    });
  });

  group('templateDivergenceDiffText', () {
    test('joins the lines with new lines', () {
      expect(
        templateDivergenceDiffText(_everyKind, l10n),
        'Add Dips\n'
        'Add Curl\n'
        'Remove Hip Thrust\n'
        'Remove Calf Raise\n'
        'Deadlift: sets changed\n'
        'Bench Press: sets changed\n'
        'Exercise groups changed',
      );
    });

    test('keeps the no-changes text with no lines', () {
      expect(
        templateDivergenceDiffText(_noChanges, l10n),
        'No changes to update',
      );
    });
  });
}
