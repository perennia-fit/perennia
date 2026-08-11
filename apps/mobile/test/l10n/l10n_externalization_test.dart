import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary logging surfaces do not inline user-facing widget strings', () {
    final surfaceFiles = <String>[
      'lib/features/home/widgets/home_screen.dart',
      'lib/features/training/widgets/training_screen.dart',
      'lib/features/activity/widgets/activity_feed_screen.dart',
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
