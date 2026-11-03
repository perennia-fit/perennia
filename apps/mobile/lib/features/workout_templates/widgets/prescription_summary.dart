import 'package:flutter/widgets.dart';

import '../../../domain/training/training_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../repositories/workout_template_feature_repository.dart';

/// One Prescription as a single line, such as
/// "3 × (60 kg · 10 reps, Rest after 90 sec)" or "3 × (Copy previous values)".
///
/// Shared by the Template editor and the Routines preview so a Prescription
/// reads the same wherever it is shown; a change to the format changes both.
String prescriptionSummary(
  BuildContext context,
  TemplateExerciseDetail exercise,
  PrescriptionDetail prescription,
) {
  final l10n = context.l10n;
  final valueSummary =
      prescription.mode == TemplatePrescriptionMode.copyPrevious
          ? l10n.workoutTemplatePrescriptionCopyPreviousSummary
          : exercise.type.isCompletionOnly
              ? l10n.workoutTemplatePrescriptionCompletion
              : exercise.type.dimensions
                  .map((dimension) {
                    final value = prescription.values.valueFor(dimension);
                    if (value == null) {
                      return '';
                    }
                    return '${value.entered} '
                        '${trainingUnitLabel(context, value.unit)}';
                  })
                  .where((segment) => segment.isNotEmpty)
                  .join(' · ');
  final details = <String>[valueSummary];
  if (prescription.restAfter != null) {
    details.add(
      '${l10n.workoutTemplatePrescriptionRestAfter} '
      '${prescription.restAfter!.inSeconds} '
      '${l10n.workoutTemplatePrescriptionSeconds}',
    );
  }
  return '${prescription.repeat} × (${details.join(', ')})';
}

/// The short label a Training Unit is written with after a value ("kg").
String trainingUnitLabel(BuildContext context, TrainingUnit unit) {
  final l10n = context.l10n;
  return switch (unit) {
    TrainingUnit.kilogram => l10n.trainingUnitKilogram,
    TrainingUnit.pound => l10n.trainingUnitPound,
    TrainingUnit.repetition => l10n.trainingUnitRepetition,
    TrainingUnit.second => l10n.trainingUnitSecond,
    TrainingUnit.kilometer => l10n.trainingUnitKilometer,
    TrainingUnit.mile => l10n.trainingUnitMile,
  };
}
