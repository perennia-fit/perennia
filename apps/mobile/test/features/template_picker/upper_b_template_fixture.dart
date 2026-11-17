import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/workout_templates/repositories/workout_template_feature_repository.dart';

/// Upper B: Bench Press with a fixed and a copy-previous Prescription, then a
/// Template Group "Superset A" whose member order (Cable Row, Curl) differs
/// from Template order (Curl, Cable Row).
WorkoutTemplateDetail upperBTemplateDetail({
  String templateId = 'template-upper',
}) {
  final loadReps = ExerciseType(
    const <DimensionId>[DimensionId.load, DimensionId.reps],
  );
  LoggedSet values(String load, String reps) {
    return LoggedSet.fromValues(<SetDimensionValue>[
      SetDimensionValue(
        dimension: DimensionId.load,
        entered: load,
        unit: TrainingUnit.kilogram,
      ),
      SetDimensionValue(
        dimension: DimensionId.reps,
        entered: reps,
        unit: TrainingUnit.repetition,
      ),
    ]);
  }

  TemplateExerciseDetail exercise(
    String id,
    String name,
    List<PrescriptionDetail> prescriptions,
  ) {
    return TemplateExerciseDetail(
      id: id,
      exerciseId: 'exercise-$id',
      name: name,
      type: loadReps,
      defaultLoadUnit: TrainingUnit.kilogram,
      loadMode: ExerciseLoadMode.added,
      prescriptions: prescriptions,
    );
  }

  return WorkoutTemplateDetail(
    id: templateId,
    name: 'Upper B',
    exercises: <TemplateExerciseDetail>[
      exercise('bench', 'Bench Press', <PrescriptionDetail>[
        PrescriptionDetail(
          id: 'p-bench-fixed',
          mode: TemplatePrescriptionMode.fixed,
          values: values('60', '10'),
          repeat: 3,
          restAfter: const Duration(seconds: 90),
        ),
        PrescriptionDetail(
          id: 'p-bench-copy',
          mode: TemplatePrescriptionMode.copyPrevious,
          values: LoggedSet.completion(),
          repeat: 3,
          restAfter: null,
        ),
      ]),
      exercise('curl', 'Curl', <PrescriptionDetail>[
        PrescriptionDetail(
          id: 'p-curl',
          mode: TemplatePrescriptionMode.fixed,
          values: values('15', '12'),
          repeat: 2,
          restAfter: null,
        ),
      ]),
      exercise('row', 'Cable Row', <PrescriptionDetail>[
        PrescriptionDetail(
          id: 'p-row',
          mode: TemplatePrescriptionMode.fixed,
          values: values('20', '12'),
          repeat: 1,
          restAfter: null,
        ),
      ]),
    ],
    groups: <TemplateGroupDetail>[
      TemplateGroupDetail(
        id: 'group-a',
        name: 'Superset A',
        colorHex: '#3366FF',
        rounds: 3,
        members: const <TemplateGroupMemberDetail>[
          TemplateGroupMemberDetail(templateExerciseId: 'row'),
          TemplateGroupMemberDetail(templateExerciseId: 'curl'),
        ],
      ),
    ],
  );
}
