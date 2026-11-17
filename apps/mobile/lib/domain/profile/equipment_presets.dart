import '../training/training_dimensions.dart';

/// How the Training setup editor groups the Equipment registry, so 27 chips
/// read as four short rows instead of one wall. UI arrangement only: nothing
/// stored or synced depends on it.
enum EquipmentGroup { freeWeights, racksAndMachines, conditioning, accessories }

/// The registry ids each group offers, in display order. Together they are
/// every id in `ExerciseEquipment.known` except `bodyweight`: an empty list is
/// the only way to say "bodyweight only" (docs/designs/user-profile.md).
final Map<EquipmentGroup, List<String>> equipmentGroups = {
  EquipmentGroup.freeWeights: _ids(const [
    ExerciseEquipment.dumbbell,
    ExerciseEquipment.barbell,
    ExerciseEquipment.ezBar,
    ExerciseEquipment.plate,
    ExerciseEquipment.kettlebell,
    ExerciseEquipment.medicineBall,
    ExerciseEquipment.sandbag,
  ]),
  EquipmentGroup.racksAndMachines: _ids(const [
    ExerciseEquipment.rack,
    ExerciseEquipment.bench,
    ExerciseEquipment.inclineBench,
    ExerciseEquipment.pullUpBar,
    ExerciseEquipment.cable,
    ExerciseEquipment.machine,
    ExerciseEquipment.smithMachine,
  ]),
  EquipmentGroup.conditioning: _ids(const [
    ExerciseEquipment.spinBike,
    ExerciseEquipment.skiErg,
    ExerciseEquipment.sled,
    ExerciseEquipment.rope,
    ExerciseEquipment.box,
    ExerciseEquipment.step,
  ]),
  EquipmentGroup.accessories: _ids(const [
    ExerciseEquipment.band,
    ExerciseEquipment.trx,
    ExerciseEquipment.gymMat,
    ExerciseEquipment.swissBall,
    ExerciseEquipment.bosu,
    ExerciseEquipment.foamRoll,
    ExerciseEquipment.wall,
  ]),
};

/// A starting point for the equipment list. Picking one replaces the
/// selection; the user then adds or removes single items.
enum EquipmentPreset {
  /// A typical commercial gym: everything except the sled, SkiErg and sandbag,
  /// which mostly live in functional-training gyms. Onboarding starts here
  /// when nothing is stored, so a user who trains in a gym can tap Next.
  gym,

  /// Dumbbells, kettlebells, bands, a pull-up bar, a bench and floor kit.
  home,

  /// No equipment: saves `[]`, the stored meaning of "bodyweight only".
  bodyweightOnly;

  Set<String> get equipment => switch (this) {
        EquipmentPreset.gym => {
            for (final ids in equipmentGroups.values) ...ids,
          }..removeAll(_ids(const [
              ExerciseEquipment.sled,
              ExerciseEquipment.skiErg,
              ExerciseEquipment.sandbag,
            ])),
        EquipmentPreset.home => _ids(const [
            ExerciseEquipment.dumbbell,
            ExerciseEquipment.kettlebell,
            ExerciseEquipment.band,
            ExerciseEquipment.pullUpBar,
            ExerciseEquipment.bench,
            ExerciseEquipment.gymMat,
            ExerciseEquipment.swissBall,
            ExerciseEquipment.foamRoll,
            ExerciseEquipment.wall,
          ]).toSet(),
        EquipmentPreset.bodyweightOnly => <String>{},
      };

  /// The preset whose list is exactly [equipment], or null. Null [equipment]
  /// (*unset*) matches none, and `[]` matches [bodyweightOnly].
  static EquipmentPreset? matching(Iterable<String>? equipment) {
    if (equipment == null) {
      return null;
    }
    final selected = equipment.toSet();
    for (final preset in values) {
      final ids = preset.equipment;
      if (ids.length == selected.length && ids.containsAll(selected)) {
        return preset;
      }
    }
    return null;
  }
}

List<String> _ids(List<ExerciseEquipment> equipment) =>
    [for (final item in equipment) item.id];
