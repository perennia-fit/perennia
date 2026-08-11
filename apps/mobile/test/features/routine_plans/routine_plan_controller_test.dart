import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/routine_cadence.dart';
import 'package:perennia/features/routine_plans/controllers/routine_plan_controller.dart';
import 'package:perennia/features/routine_plans/repositories/routine_plan_feature_repository.dart';

void main() {
  test('controller normalizes authored values and forwards reference writes',
      () async {
    final repository = _RecordingRoutinePlanRepository();
    final container = ProviderContainer(
      overrides: [
        routinePlanFeatureRepositoryProvider.overrideWith(
          (ref) => repository,
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      routinePlanListControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final controller = container.read(routinePlanCommandsProvider);

    final routineId = await controller.createRoutine(
      name: '  Hybrid week  ',
      notes: '  Strength and running  ',
    );
    await controller.updateRoutine(
      routineId: routineId,
      name: '  Hybrid fortnight ',
      notes: '   ',
    );
    final entryId = await controller.addTemplateReference(
      routineId: routineId,
      workoutTemplateId: 'template-run',
      slot: 2,
    );
    await controller.reorderTemplateReferences(
      routineId: routineId,
      orderedEntryIds: <String>['entry-run', 'entry-strength'],
    );
    await controller.removeTemplateReference(entryId);
    expect(
      controller.validateCadence(const Cadence.rotating(32)).hasWarning,
      isTrue,
    );
    await controller.setCadence(
      routineId: routineId,
      cadence: const Cadence.weekly(),
    );
    await controller.moveTemplateReferenceToSlot(
      routineEntryId: entryId,
      slot: 3,
    );
    await controller.replaceCadenceLayout(
      routineId: routineId,
      placements: const <RoutineEntryPlacement>[
        RoutineEntryPlacement(entryId: 'entry-run', slot: 2),
        RoutineEntryPlacement(entryId: 'entry-strength', slot: 3),
      ],
    );
    await controller.restoreReferencedTemplate('template-run');
    await controller.archiveRoutine(routineId);
    await controller.restoreRoutine(routineId);

    expect(repository.createdName, 'Hybrid week');
    expect(repository.createdNotes, 'Strength and running');
    expect(repository.updatedName, 'Hybrid fortnight');
    expect(repository.updatedNotes, isNull);
    expect(repository.addedTemplateId, 'template-run');
    expect(repository.addedSlot, 2);
    expect(repository.orderedEntryIds, <String>['entry-run', 'entry-strength']);
    expect(repository.removedEntryId, 'entry-created');
    expect(repository.savedCadence?.kind, CadenceKind.weekly);
    expect(repository.movedEntryId, 'entry-created');
    expect(repository.movedSlot, 3);
    expect(
      repository.placements?.map((placement) => placement.slot),
      <int>[2, 3],
    );
    expect(repository.restoredTemplateId, 'template-run');
    expect(repository.archivedRoutineId, 'routine-created');
    expect(repository.restoredRoutineId, 'routine-created');
  });

  test('controller rejects blank Routine names', () {
    final container = ProviderContainer(
      overrides: [
        routinePlanFeatureRepositoryProvider.overrideWith(
          (ref) => _RecordingRoutinePlanRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      routinePlanListControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final controller = container.read(routinePlanCommandsProvider);

    expect(
      () => controller.createRoutine(name: '   '),
      throwsA(isA<RoutinePlanInputException>()),
    );
    expect(
      () => controller.updateRoutine(
        routineId: 'routine-a',
        name: ' ',
      ),
      throwsA(isA<RoutinePlanInputException>()),
    );
  });

  test('command provider does not subscribe to the Routine list', () {
    final repository = _RecordingRoutinePlanRepository();
    final container = ProviderContainer(
      overrides: [
        routinePlanFeatureRepositoryProvider.overrideWith(
          (ref) => repository,
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(routinePlanCommandsProvider);

    expect(repository.watchRoutinesCalls, 0);
  });
}

class _RecordingRoutinePlanRepository implements RoutinePlanFeatureRepository {
  int watchRoutinesCalls = 0;
  String? createdName;
  String? createdNotes;
  String? updatedName;
  String? updatedNotes;
  String? addedTemplateId;
  int? addedSlot;
  String? removedEntryId;
  List<String>? orderedEntryIds;
  String? restoredTemplateId;
  String? archivedRoutineId;
  String? restoredRoutineId;
  Cadence? savedCadence;
  String? movedEntryId;
  int? movedSlot;
  List<RoutineEntryPlacement>? placements;

  @override
  Stream<RoutinePlanListSnapshot> watchRoutines() {
    watchRoutinesCalls += 1;
    return Stream<RoutinePlanListSnapshot>.value(RoutinePlanListSnapshot.empty);
  }

  @override
  Stream<RoutinePlanDetail?> watchRoutine(String routineId) {
    return const Stream<RoutinePlanDetail?>.empty();
  }

  @override
  Stream<List<RoutineWorkoutTemplateOption>> watchAvailableTemplates() {
    return Stream<List<RoutineWorkoutTemplateOption>>.value(
      const <RoutineWorkoutTemplateOption>[],
    );
  }

  @override
  Future<String> createRoutine({required String name, String? notes}) async {
    createdName = name;
    createdNotes = notes;
    return 'routine-created';
  }

  @override
  Future<void> updateRoutine({
    required String routineId,
    required String name,
    String? notes,
  }) async {
    updatedName = name;
    updatedNotes = notes;
  }

  @override
  Future<String> addTemplateReference({
    required String routineId,
    required String workoutTemplateId,
    int? slot,
  }) async {
    addedTemplateId = workoutTemplateId;
    addedSlot = slot;
    return 'entry-created';
  }

  @override
  Future<void> removeTemplateReference(String routineEntryId) async {
    removedEntryId = routineEntryId;
  }

  @override
  Future<void> reorderTemplateReferences({
    required String routineId,
    required List<String> orderedEntryIds,
  }) async {
    this.orderedEntryIds = orderedEntryIds;
  }

  @override
  Future<void> restoreReferencedTemplate(String workoutTemplateId) async {
    restoredTemplateId = workoutTemplateId;
  }

  @override
  Future<void> archiveRoutine(String routineId) async {
    archivedRoutineId = routineId;
  }

  @override
  Future<void> restoreRoutine(String routineId) async {
    restoredRoutineId = routineId;
  }

  @override
  Future<void> setCadence({
    required String routineId,
    required Cadence? cadence,
  }) async {
    savedCadence = cadence;
  }

  @override
  Future<void> moveTemplateReferenceToSlot({
    required String routineEntryId,
    required int slot,
  }) async {
    movedEntryId = routineEntryId;
    movedSlot = slot;
  }

  @override
  Future<void> replaceCadenceLayout({
    required String routineId,
    required List<RoutineEntryPlacement> placements,
  }) async {
    this.placements = placements;
  }
}
