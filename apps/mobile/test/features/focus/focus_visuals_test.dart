import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/features/focus/widgets/focus_visuals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every starter Focus in the bundled seed has its own icon', () async {
    // The icon table is keyed by the seeded ids; renumbering or adding a
    // starter Focus in the seed must update it too.
    final seed = await const AssetPlatformExerciseSeedSource().load();

    expect(seed.focuses, isNotEmpty);
    for (final focus in seed.focuses) {
      expect(
        focusIcon(focus.id),
        isNot(Icons.flag_outlined),
        reason: '${focus.name} (${focus.id}) has no icon in focus_visuals.dart',
      );
    }
  });
}
