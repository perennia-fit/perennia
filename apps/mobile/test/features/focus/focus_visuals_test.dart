import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/focus_color.dart';
import 'package:perennia/features/focus/widgets/focus_visuals.dart';
import 'package:perennia/theme/theme.dart';

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

  group('resolvedFocusColor', () {
    const colors = AppColors.light;

    FocusRecord focus({String? colorHex}) => FocusRecord(
          id: starterFocusEnduranceId,
          name: 'Endurance',
          sortOrder: 1,
          colorHex: colorHex,
          updatedAt: DateTime.utc(2026, 10, 24),
        );

    test('uses the stored color', () {
      expect(
        resolvedFocusColor(focus(colorHex: '#4A8FE0'), colors),
        const Color(0xFF4A8FE0),
      );
    });

    test('falls back to the default token with none stored', () {
      expect(
        resolvedFocusColor(focus(), colors),
        colors.categoryColor('cardio'),
      );
    });

    test('falls back to the default token for a malformed value', () {
      expect(
        resolvedFocusColor(focus(colorHex: 'not-a-color'), colors),
        colors.categoryColor('cardio'),
      );
    });
  });
}
