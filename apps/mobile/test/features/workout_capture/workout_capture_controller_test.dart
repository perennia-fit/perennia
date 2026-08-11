import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/routine_cadence.dart';
import 'package:perennia/domain/training/set_validation.dart';
import 'package:perennia/domain/training/workout_capture.dart';
import 'package:perennia/features/workout_capture/controllers/workout_capture_controller.dart';
import 'package:perennia/features/workout_capture/repositories/workout_capture_feature_repository.dart';

void main() {
  test('normalizes names and submits canonical placements and warning tokens',
      () async {
    final repository = _FakeWorkoutCaptureRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final provider = workoutCaptureControllerProvider('workout-1');
    final controller = container.read(provider.notifier);
    final warningValidation = WorkoutCaptureValidationResult(
      warnings: <WorkoutCaptureValidationIssue>[
        _issue(rule: 'unusual', sourcePath: 'exercises[0]'),
      ],
    );

    controller.setWarningsAccepted(true, warningValidation);
    await controller.submit(
      preview: _preview(validation: warningValidation),
      name: '  Hybrid day  ',
    );
    expect(repository.requests.single.name, 'Hybrid day');
    expect(
      repository.requests.single.placement,
      isA<WorkoutCaptureNoPlacement>(),
    );
    expect(
      repository.requests.single.acknowledgedWarningTokens,
      warningValidation.warningAcknowledgementTokenSet,
    );

    controller.selectRoutine(_collection);
    await controller.submit(preview: _preview(), name: 'Hybrid day');
    expect(
      repository.requests.last.placement,
      isA<WorkoutCaptureCollectionAppendPlacement>().having(
        (placement) => placement.routineId,
        'routineId',
        'collection',
      ),
    );

    controller
      ..selectRoutine(_rotation)
      ..selectSlot(2);
    await controller.submit(preview: _preview(), name: 'Hybrid day');
    expect(
      repository.requests.last.placement,
      isA<WorkoutCaptureCadenceSlotPlacement>()
          .having(
            (placement) => placement.routineId,
            'routineId',
            'rotation',
          )
          .having((placement) => placement.slot, 'slot', 2),
    );
  });

  test('blocks blank names, missing slots, and unavailable Routines', () async {
    final repository = _FakeWorkoutCaptureRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final provider = workoutCaptureControllerProvider('workout-1');
    final controller = container.read(provider.notifier);

    await controller.submit(preview: _preview(), name: '   ');
    expect(container.read(provider).showNameError, isTrue);

    controller.selectRoutine(_rotation);
    await controller.submit(preview: _preview(), name: 'Hybrid day');
    expect(container.read(provider).showSlotError, isTrue);

    controller.reconcileRoutines(const <WorkoutCaptureRoutineOption>[]);
    await controller.submit(preview: _preview(), name: 'Hybrid day');
    expect(
      container.read(provider).placementNotice,
      WorkoutCapturePlacementNotice.routineUnavailable,
    );
    expect(repository.requests, isEmpty);
  });

  test('edits clear commit-time validation and exact acknowledgement tokens',
      () async {
    final runtimeValidation = WorkoutCaptureValidationResult(
      errors: <WorkoutCaptureValidationIssue>[
        _issue(rule: 'placement_changed', sourcePath: 'placement'),
      ],
      warnings: <WorkoutCaptureValidationIssue>[
        _issue(rule: 'warning', sourcePath: 'placement'),
      ],
    );
    final repository = _FakeWorkoutCaptureRepository()
      ..saveError = WorkoutCaptureValidationException(runtimeValidation);
    final container = _container(repository);
    addTearDown(container.dispose);
    final provider = workoutCaptureControllerProvider('workout-1');
    final controller = container.read(provider.notifier)
      ..selectRoutine(_rotation)
      ..selectSlot(2);

    for (final edit in <void Function()>[
      controller.nameChanged,
      () => controller.selectRoutine(_rotation),
      () => controller.selectSlot(3),
    ]) {
      controller
        ..selectRoutine(_rotation)
        ..selectSlot(2);
      await controller.submit(preview: _preview(), name: 'Hybrid day');
      expect(container.read(provider).runtimeValidation, runtimeValidation);
      controller.setWarningsAccepted(true, runtimeValidation);
      expect(
        container.read(provider).acknowledgedWarningTokens,
        isNotEmpty,
      );

      edit();
      expect(container.read(provider).runtimeValidation, isNull);
      expect(
        container.read(provider).acknowledgedWarningTokens,
        isEmpty,
      );
    }

    repository.saveError = null;
    await controller.submit(preview: _preview(), name: 'Hybrid day');
    expect(repository.requests, hasLength(4));
  });

  test('reconciles removal and Cadence shrink without losing intent', () {
    final repository = _FakeWorkoutCaptureRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final provider = workoutCaptureControllerProvider('workout-1');
    final controller = container.read(provider.notifier)
      ..selectRoutine(_rotation)
      ..selectSlot(4);

    controller.reconcileRoutines(const <WorkoutCaptureRoutineOption>[]);
    var state = container.read(provider);
    expect(state.selectedRoutine?.id, 'rotation');
    expect(state.selectedSlot, isNull);
    expect(
      state.placementNotice,
      WorkoutCapturePlacementNotice.routineUnavailable,
    );

    controller.selectRoutine(_rotation);
    controller.selectSlot(4);
    controller.reconcileRoutines(<WorkoutCaptureRoutineOption>[
      const WorkoutCaptureRoutineOption(
        id: 'rotation',
        name: 'Rotation',
        cadenceKind: CadenceKind.rotating,
        slotCount: 2,
      ),
    ]);
    state = container.read(provider);
    expect(state.selectedSlot, isNull);
    expect(state.showSlotError, isTrue);
    expect(
      state.placementNotice,
      WorkoutCapturePlacementNotice.cadenceChanged,
    );

    controller.selectSlot(4);
    state = container.read(provider);
    expect(state.selectedSlot, isNull);
    expect(state.showSlotError, isTrue);
  });

  test('benign Routine refresh keeps a valid placement submittable', () {
    final repository = _FakeWorkoutCaptureRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final provider = workoutCaptureControllerProvider('workout-1');
    final controller = container.read(provider.notifier)
      ..selectRoutine(_rotation)
      ..selectSlot(2);

    controller.reconcileRoutines(<WorkoutCaptureRoutineOption>[
      const WorkoutCaptureRoutineOption(
        id: 'rotation',
        name: 'Renamed rotation',
        cadenceKind: CadenceKind.rotating,
        slotCount: 3,
      ),
    ]);

    final state = container.read(provider);
    expect(state.selectedRoutine?.name, 'Renamed rotation');
    expect(state.selectedSlot, 2);
    expect(state.showSlotError, isFalse);
    expect(state.placementNotice, isNull);
    expect(controller.canSubmit(_preview()), isTrue);
  });

  test('a Collection changing to a Cadence requires an explicit slot', () {
    final repository = _FakeWorkoutCaptureRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final provider = workoutCaptureControllerProvider('workout-1');
    final controller = container.read(provider.notifier)
      ..selectRoutine(_collection);

    controller.reconcileRoutines(<WorkoutCaptureRoutineOption>[
      const WorkoutCaptureRoutineOption(
        id: 'collection',
        name: 'Favourites',
        cadenceKind: CadenceKind.rotating,
        slotCount: 3,
      ),
    ]);

    final state = container.read(provider);
    expect(state.selectedSlot, isNull);
    expect(state.showSlotError, isTrue);
    expect(
      state.placementNotice,
      WorkoutCapturePlacementNotice.cadenceChanged,
    );
    expect(controller.canSubmit(_preview()), isFalse);
  });

  test('Cadence semantics changing always require placement review', () {
    final repository = _FakeWorkoutCaptureRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final provider = workoutCaptureControllerProvider('workout-1');
    final controller = container.read(provider.notifier)
      ..selectRoutine(_weekly)
      ..selectSlot(2);

    controller.reconcileRoutines(<WorkoutCaptureRoutineOption>[
      const WorkoutCaptureRoutineOption(
        id: 'weekly',
        name: 'Weekly plan',
        cadenceKind: CadenceKind.rotating,
        slotCount: 7,
      ),
    ]);
    var state = container.read(provider);
    expect(state.selectedSlot, isNull);
    expect(state.showSlotError, isTrue);
    expect(
      state.placementNotice,
      WorkoutCapturePlacementNotice.cadenceChanged,
    );
    expect(controller.canSubmit(_preview()), isFalse);

    controller
      ..selectRoutine(_rotation)
      ..selectSlot(2)
      ..reconcileRoutines(<WorkoutCaptureRoutineOption>[
        const WorkoutCaptureRoutineOption(
          id: 'rotation',
          name: 'Rotation',
          cadenceKind: null,
          slotCount: 0,
        ),
      ]);
    state = container.read(provider);
    expect(state.selectedSlot, isNull);
    expect(state.showSlotError, isFalse);
    expect(
      state.placementNotice,
      WorkoutCapturePlacementNotice.cadenceChanged,
    );
    expect(controller.canSubmit(_preview()), isFalse);

    controller.selectRoutine(state.selectedRoutine);
    expect(container.read(provider).placementNotice, isNull);
    expect(controller.canSubmit(_preview()), isTrue);
  });
}

ProviderContainer _container(_FakeWorkoutCaptureRepository repository) {
  return ProviderContainer(
    overrides: [
      workoutCaptureFeatureRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

WorkoutCapturePreview _preview({WorkoutCaptureValidationResult? validation}) {
  return WorkoutCapturePreview(
    workoutId: 'workout-1',
    content: CapturedWorkoutTemplateContent(exercises: [], groups: []),
    suggestedName: 'Hybrid day',
    exerciseCount: 2,
    setCount: 5,
    groupCount: 1,
    validation: validation ?? WorkoutCaptureValidationResult(),
  );
}

WorkoutCaptureValidationIssue _issue({
  required String rule,
  required String sourcePath,
}) {
  return WorkoutCaptureValidationIssue(
    sourcePath: sourcePath,
    issue: SetValidationIssue(
      field: 'values.load',
      dimension: null,
      rule: rule,
      message: '$rule message',
      limit: null,
    ),
  );
}

const _collection = WorkoutCaptureRoutineOption(
  id: 'collection',
  name: 'Favourites',
  cadenceKind: null,
  slotCount: 0,
);

const _rotation = WorkoutCaptureRoutineOption(
  id: 'rotation',
  name: 'Rotation',
  cadenceKind: CadenceKind.rotating,
  slotCount: 4,
);

const _weekly = WorkoutCaptureRoutineOption(
  id: 'weekly',
  name: 'Weekly plan',
  cadenceKind: CadenceKind.weekly,
  slotCount: 7,
);

class _FakeWorkoutCaptureRepository implements WorkoutCaptureFeatureRepository {
  final requests = <WorkoutCaptureSaveRequest>[];
  Object? saveError;

  @override
  Future<WorkoutCapturePreview> preview(String workoutId) async => _preview();

  @override
  Future<WorkoutCaptureSaveResult> save(
    WorkoutCaptureSaveRequest request,
  ) async {
    requests.add(request);
    final error = saveError;
    if (error != null) {
      throw error;
    }
    return const WorkoutCaptureSaveResult(
      workoutTemplateId: 'template-1',
      routineEntryId: null,
      activityBatchId: 'batch-1',
    );
  }

  @override
  Stream<List<WorkoutCaptureRoutineOption>> watchRoutines() {
    return const Stream<List<WorkoutCaptureRoutineOption>>.empty();
  }
}
