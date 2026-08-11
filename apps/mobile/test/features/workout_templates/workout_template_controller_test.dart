import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/workout_templates/controllers/workout_template_controller.dart';
import 'package:perennia/features/workout_templates/repositories/workout_template_feature_repository.dart';

void main() {
  test('controller normalizes authored text and forwards ordered plan writes',
      () async {
    final repository = _RecordingWorkoutTemplateRepository();
    final container = ProviderContainer(
      overrides: [
        workoutTemplateFeatureRepositoryProvider.overrideWith(
          (ref) => repository,
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      workoutTemplateListControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final controller = container.read(
      workoutTemplateListControllerProvider.notifier,
    );

    final templateId = await controller.createTemplate(
      name: '  Push A  ',
      notes: '  Barbell day  ',
    );
    await controller.updateTemplate(
      templateId: templateId,
      name: '  Push B ',
      notes: '   ',
    );
    await controller.reorderExercises(
      templateId: templateId,
      orderedIds: const <String>['entry-b', 'entry-a'],
    );
    await controller.addPrescription(
      templateExerciseId: 'entry-b',
      input: PrescriptionInput(
        mode: TemplatePrescriptionMode.copyPrevious,
        repeat: 3,
        restAfter: const Duration(seconds: 90),
        values: LoggedSet.completion(),
      ),
    );
    final groupId = await controller.createTemplateGroup(
      templateId: templateId,
      input: TemplateGroupInput(
        name: '  A1 Pair  ',
        colorHex: ' #2f6fed ',
        rounds: 3,
        orderedTemplateExerciseIds: const <String>['entry-a', 'entry-b'],
      ),
    );
    await controller.reorderTemplateGroups(
      templateId: templateId,
      orderedIds: const <String>['group-b', 'group-a'],
    );
    await controller.dissolveTemplateGroup(groupId);

    expect(templateId, 'template-created');
    expect(repository.createdName, 'Push A');
    expect(repository.createdNotes, 'Barbell day');
    expect(repository.updatedName, 'Push B');
    expect(repository.updatedNotes, isNull);
    expect(repository.orderedExerciseIds, <String>['entry-b', 'entry-a']);
    expect(repository.lastPrescription?.mode,
        TemplatePrescriptionMode.copyPrevious);
    expect(repository.lastPrescription?.repeat, 3);
    expect(repository.lastPrescription?.restAfter, const Duration(seconds: 90));
    expect(repository.lastGroupInput?.name, 'A1 Pair');
    expect(repository.lastGroupInput?.colorHex, '#2F6FED');
    expect(repository.orderedGroupIds, <String>['group-b', 'group-a']);
    expect(repository.dissolvedGroupId, 'group-created');
  });

  test('controller rejects blank names and invalid Prescription structure',
      () async {
    final repository = _RecordingWorkoutTemplateRepository();
    final container = ProviderContainer(
      overrides: [
        workoutTemplateFeatureRepositoryProvider.overrideWith(
          (ref) => repository,
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      workoutTemplateListControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final controller = container.read(
      workoutTemplateListControllerProvider.notifier,
    );

    expect(
      () => controller.createTemplate(name: '   '),
      throwsA(isA<WorkoutTemplateInputException>()),
    );
    expect(
      () => controller.addPrescription(
        templateExerciseId: 'entry-a',
        input: PrescriptionInput(
          mode: TemplatePrescriptionMode.fixed,
          repeat: 0,
          values: LoggedSet.completion(),
        ),
      ),
      throwsA(isA<WorkoutTemplateInputException>()),
    );
  });
}

class _RecordingWorkoutTemplateRepository
    implements WorkoutTemplateFeatureRepository {
  String? createdName;
  String? createdNotes;
  String? updatedName;
  String? updatedNotes;
  List<String>? orderedExerciseIds;
  PrescriptionInput? lastPrescription;
  TemplateGroupInput? lastGroupInput;
  List<String>? orderedGroupIds;
  String? dissolvedGroupId;

  @override
  Stream<WorkoutTemplateListSnapshot> watchTemplates() {
    return Stream<WorkoutTemplateListSnapshot>.value(
      WorkoutTemplateListSnapshot.empty,
    );
  }

  @override
  Stream<WorkoutTemplateDetail?> watchTemplate(String templateId) {
    return const Stream<WorkoutTemplateDetail?>.empty();
  }

  @override
  Future<String> createTemplate({
    required String name,
    String? notes,
  }) async {
    createdName = name;
    createdNotes = notes;
    return 'template-created';
  }

  @override
  Future<void> updateTemplate({
    required String templateId,
    required String name,
    String? notes,
  }) async {
    updatedName = name;
    updatedNotes = notes;
  }

  @override
  Future<void> reorderExercises({
    required String templateId,
    required List<String> orderedIds,
  }) async {
    orderedExerciseIds = orderedIds;
  }

  @override
  Future<String> addPrescription({
    required String templateExerciseId,
    required PrescriptionInput input,
  }) async {
    lastPrescription = input;
    return 'prescription-created';
  }

  @override
  Future<String> addExercise({
    required String templateId,
    required String exerciseId,
    String? notes,
  }) async =>
      'entry-created';

  @override
  Future<void> archiveTemplate(String templateId) async {}

  @override
  Future<void> removeExercise(String templateExerciseId) async {}

  @override
  Future<void> removePrescription(String prescriptionId) async {}

  @override
  Future<void> reorderPrescriptions({
    required String templateExerciseId,
    required List<String> orderedIds,
  }) async {}

  @override
  Future<void> restoreTemplate(String templateId) async {}

  @override
  Future<void> updateExerciseNotes({
    required String templateExerciseId,
    String? notes,
  }) async {}

  @override
  Future<void> updatePrescription({
    required String prescriptionId,
    required PrescriptionInput input,
  }) async {}

  @override
  Future<String> createTemplateGroup({
    required String templateId,
    required TemplateGroupInput input,
  }) async {
    lastGroupInput = input;
    return 'group-created';
  }

  @override
  Future<void> updateTemplateGroup({
    required String groupId,
    required TemplateGroupInput input,
  }) async {
    lastGroupInput = input;
  }

  @override
  Future<void> reorderTemplateGroups({
    required String templateId,
    required List<String> orderedIds,
  }) async {
    orderedGroupIds = orderedIds;
  }

  @override
  Future<void> dissolveTemplateGroup(String groupId) async {
    dissolvedGroupId = groupId;
  }
}
