import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary logging surfaces do not inline user-facing widget strings', () {
    final surfaceFiles = <String>[
      'lib/features/home/widgets/home_screen.dart',
      'lib/features/training/widgets/training_screen.dart',
      'lib/features/activity/widgets/activity_feed_screen.dart',
      'lib/features/home/widgets/start_workout_sheet.dart',
      'lib/features/focus/widgets/focus_manager_screen.dart',
      'lib/features/focus/widgets/focus_picker_sheet.dart',
      'lib/features/focus/widgets/focused_exercise_list.dart',
      'lib/features/progress/widgets/progress_overview.dart',
      'lib/features/progress/widgets/progress_card.dart',
      'lib/features/progress/widgets/this_week_card.dart',
      'lib/features/progress/widgets/trained_days_card.dart',
      'lib/features/progress/widgets/focus_time_card.dart',
      'lib/features/progress/widgets/key_exercises_card.dart',
      'lib/features/progress/widgets/new_bests_card.dart',
      'lib/features/progress/widgets/protocols_progress_card.dart',
      'lib/features/progress/widgets/progress_format.dart',
    ];
    final forbiddenPatterns = <String, RegExp>{
      'Text literal': RegExp(r'\bText\(\s*[' '"]'),
      'tooltip literal': RegExp(r'\btooltip:\s*[' '"]'),
      'InputDecoration label literal': RegExp(r'\blabelText:\s*[' '"]'),
      'Tooltip message literal': RegExp(r'\bmessage:\s*[' '"]'),
    };

    final failures = <String>[];
    for (final path in surfaceFiles) {
      final lines = File(path).readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        final line = lines[index];
        for (final entry in forbiddenPatterns.entries) {
          if (entry.value.hasMatch(line)) {
            failures.add(
              '$path:${index + 1} ${entry.key}: ${line.trim()}',
            );
          }
        }
      }
    }

    expect(
      failures,
      isEmpty,
      reason: 'Use generated AppLocalizations accessors on the externalized '
          'logging surfaces.',
    );
  });
}
