import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every vector under `packages/golden-vectors/vectors` must have a Dart
/// runner, or be named below as checked only by TypeScript. The CI golden job
/// runs whichever Dart tests mention `golden-vectors`, so without this guard a
/// new vector that no Dart test loads would pass silently on this side. The
/// TypeScript twin of this guard is `DOMAINS_OWNED_ELSEWHERE` in
/// `apps/server/test/agent-validation.golden.test.mjs`.
///
/// Owners are paths relative to `apps/mobile`, and each owner must name the
/// vector's file, so a stale entry fails here instead of vouching for a runner
/// that no longer reads the vector.
const Map<String, String> _dartRunnerByDomain = <String, String>{
  // Vectors with no `domain` are analytics, as in the TypeScript runner.
  'analytics': 'test/domain/exercise_analytics_test.dart',
  'set-validation': 'test/domain/set_validation_test.dart',
  'nutrient-validation': 'test/domain/set_validation_test.dart',
  'nutrition-goal-validation': 'test/domain/set_validation_test.dart',
  'nutrition-analytics': 'test/domain/nutrition_aggregation_golden_test.dart',
  'reading-normalization': 'test/domain/metric_reading_normalization_test.dart',
  'dose-validation': 'test/domain/dose_validation_test.dart',
  'effect-window': 'test/domain/effect_window_golden_test.dart',
  'barcode-candidates': 'test/domain/barcode_candidates_golden_test.dart',
  'food-history': 'test/domain/food_history_golden_test.dart',
  'plan-validation': 'test/domain/plan_validation_test.dart',
  'workout-capture': 'test/domain/workout_capture_golden_test.dart',
  'plan-divergence': 'test/domain/template_divergence_golden_test.dart',
  'template-materialize': 'test/domain/template_materialize_golden_test.dart',
  'routine-up-next': 'test/domain/routine_up_next_golden_test.dart',
  'training-progress': 'test/domain/training_progress_golden_test.dart',
  'progress-measure': 'test/domain/progress_measure_golden_test.dart',
  'protocol-plan': 'test/domain/protocol_plan_golden_test.dart',
  'protocol-plan-validation':
      'test/domain/protocol_plan_validation_test.dart',
  'settings-validation': 'test/domain/settings_validation_test.dart',
  'measurement-validation':
      'test/domain/body_tracker/measurement_validation_test.dart',
  'measurement-delta': 'test/features/body_tracker/measurement_delta_test.dart',
};

// Empty today: every vector domain is pinned on both sides. A domain that
// only the server implements goes here, with the reason it has no Dart twin.
const Set<String> _domainsCheckedOnlyInTypeScript = <String>{};

void main() {
  test('every golden vector domain has a Dart runner or is TypeScript-only',
      () {
    expect(
      _dartRunnerByDomain.keys.toSet().intersection(
            _domainsCheckedOnlyInTypeScript,
          ),
      isEmpty,
      reason: 'A domain is either run in Dart or TypeScript-only, not both.',
    );

    final repoRoot = _repoRoot();
    final vectorsDirectory = Directory(
      '${repoRoot.path}${Platform.pathSeparator}packages'
      '${Platform.pathSeparator}golden-vectors'
      '${Platform.pathSeparator}vectors',
    );
    final vectorFiles = vectorsDirectory
        .listSync()
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.json') &&
              !file.path.endsWith('.schema.json'),
        )
        .toList();
    expect(vectorFiles, isNotEmpty);

    for (final file in vectorFiles) {
      final filename = file.uri.pathSegments.last;
      final vector =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final domain = vector['domain'] as String? ?? 'analytics';
      if (_domainsCheckedOnlyInTypeScript.contains(domain)) {
        continue;
      }

      final owner = _dartRunnerByDomain[domain];
      expect(
        owner,
        isNotNull,
        reason: '$filename: no Dart golden runner owns domain "$domain". '
            'Add a Dart test that runs it and list it in _dartRunnerByDomain, '
            'or list it in _domainsCheckedOnlyInTypeScript with the reason.',
      );

      // A vector with no cases pins nothing, so there is nothing to run.
      final cases = vector['cases'] as List<Object?>? ?? const <Object?>[];
      if (cases.isEmpty) {
        continue;
      }
      final ownerFile = File(
        '${repoRoot.path}${Platform.pathSeparator}apps'
        '${Platform.pathSeparator}mobile'
        '${Platform.pathSeparator}$owner',
      );
      expect(
        ownerFile.existsSync() &&
            ownerFile.readAsStringSync().contains(filename),
        isTrue,
        reason: '$filename: _dartRunnerByDomain names $owner for "$domain", '
            'but that file does not load $filename.',
      );
    }
  });
}

Directory _repoRoot() {
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth += 1) {
    final vectors = Directory(
      '${directory.path}${Platform.pathSeparator}packages'
      '${Platform.pathSeparator}golden-vectors'
      '${Platform.pathSeparator}vectors',
    );
    if (vectors.existsSync()) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('packages/golden-vectors/vectors not found.');
}
