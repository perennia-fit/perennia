import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/profile/equipment_presets.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  test('the groups offer every registry id but bodyweight, once each', () {
    final offered = [for (final ids in equipmentGroups.values) ...ids];

    expect(offered.toSet(), hasLength(offered.length));
    expect(offered.toSet(), {
      for (final equipment in ExerciseEquipment.known)
        if (equipment != ExerciseEquipment.bodyweight) equipment.id,
    });
  });

  test('every preset item is one the groups offer', () {
    final offered = {for (final ids in equipmentGroups.values) ...ids};
    for (final preset in EquipmentPreset.values) {
      expect(offered.containsAll(preset.equipment), isTrue, reason: '$preset');
    }
  });

  test('Gym leaves out the functional-gym items only', () {
    final offered = {for (final ids in equipmentGroups.values) ...ids};

    expect(
      offered.difference(EquipmentPreset.gym.equipment),
      {'sled', 'skiErg', 'sandbag'},
    );
  });

  group('matching', () {
    test('unset matches no preset', () {
      expect(EquipmentPreset.matching(null), isNull);
    });

    test('an empty list is Bodyweight only', () {
      expect(
        EquipmentPreset.matching(const <String>[]),
        EquipmentPreset.bodyweightOnly,
      );
    });

    test('a preset list in any order matches it', () {
      final home = EquipmentPreset.home.equipment.toList().reversed;

      expect(EquipmentPreset.matching(home), EquipmentPreset.home);
    });

    test('one item more or less matches nothing', () {
      final home = EquipmentPreset.home.equipment;

      expect(EquipmentPreset.matching({...home, 'sled'}), isNull);
      expect(EquipmentPreset.matching(home.skip(1)), isNull);
    });
  });
}
